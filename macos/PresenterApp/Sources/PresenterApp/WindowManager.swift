import AppKit
import PresenterCore

final class PresenterWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class RenderInstance {
    let page: DeckPage
    let window: NSWindow
    init(config: ViewConfig, deckURL: URL, controller: DeckController, canonical: Bool, authority: Bool) throws {
        page = try DeckPage(config: config, deckURL: deckURL, controller: controller, isCanonical: canonical, isAuthority: authority)
        window = PresenterWindow(contentRect: NSRect(x: 100, y: 100, width: 960, height: 540),
                                 styleMask: canonical ? [.titled, .resizable] : [.borderless], backing: .buffered, defer: false)
        window.title = config.name + (canonical ? " preview" : "")
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        if canonical {
            window.contentView = FixedRenderView(contentView: page.presentationView)
        } else {
            window.contentView = page.presentationView
        }
    }
    func close() { page.detach(); window.orderOut(nil); window.close() }
}

@MainActor
private final class ViewRuntime {
    let config: ViewConfig
    let authority: Bool
    let preview: RenderInstance
    var output: OverlayOutput?
    init(config: ViewConfig, authority: Bool, preview: RenderInstance) {
        self.config = config; self.authority = authority; self.preview = preview
    }
}

@MainActor
final class WindowManager {
    let deckURL: URL
    let store: ViewStore
    private let controller: DeckController
    private var runtimes: [UUID: ViewRuntime] = [:]
    private var casts: [String: RenderInstance] = [:]
    private var observer: NSObjectProtocol?

    init(deckURL: URL, controller: DeckController) {
        self.deckURL = deckURL
        self.controller = controller
        store = ViewStore(deckURL: deckURL)
        store.onChange = { [weak self] in self?.reconcile() }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.store.displays = NSScreen.displayInfos
                self?.reconcile()
            }
        }
    }

    func showAll() {
        reconcile()
        for runtime in runtimes.values { runtime.preview.window.orderFront(nil) }
        let operatorID = store.list.views.first(where: { $0.kind == .presenter })?.id ?? store.list.views.first?.id
        if let id = operatorID { runtimes[id]?.preview.window.makeKeyAndOrderFront(nil) }
    }

    func reloadAll() {
        for runtime in runtimes.values {
            runtime.output?.stop()
            runtime.output = nil
            runtime.preview.page.reload()
        }
        for instance in casts.values { instance.page.reload() }
        reconcile()
    }

    func shutdown() {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        for id in Array(runtimes.keys) { removeView(id) }
        store.onChange = nil
    }

    private func removeView(_ id: UUID) {
        guard let runtime = runtimes.removeValue(forKey: id) else { return }
        runtime.output?.stop()
        runtime.preview.close()
        for displayID in Array(casts.keys) where casts[displayID]?.page.viewID == id {
            casts.removeValue(forKey: displayID)?.close()
        }
        store.outputStatus[id] = nil
    }

    private func reconcile() {
        let list = store.list
        controller.configure(list, deckURL: deckURL)
        for id in Array(runtimes.keys) {
            let config = list.views.first { $0.id == id }
            if config != runtimes[id]?.config || runtimes[id]?.authority != (list.primaryMainID == id) { removeView(id) }
        }
        for config in list.views {
            if runtimes[config.id] == nil {
                do {
                    let authority = list.primaryMainID == config.id
                    let preview = try RenderInstance(config: config, deckURL: deckURL, controller: controller, canonical: true, authority: authority)
                    runtimes[config.id] = ViewRuntime(config: config, authority: authority, preview: preview)
                    preview.window.orderFront(nil)
                } catch { store.outputStatus[config.id] = error.localizedDescription }
            }
        }
        let owners = list.displayOwners(connected: Set(store.displays.map(\.id)))
        for id in Array(casts.keys) where casts[id]?.page.viewID != owners[id] {
            casts.removeValue(forKey: id)?.close()
        }
        for displayID in owners.keys.sorted() {
            guard casts[displayID] == nil, let owner = owners[displayID], let runtime = runtimes[owner],
                  let screen = NSScreen.screen(withUUID: displayID) else { continue }
            do {
                let cast = try RenderInstance(config: runtime.config, deckURL: deckURL, controller: controller, canonical: false, authority: false)
                // VERIFY-ON-MAC: borderless screen placement/ordering with Spaces and hot-plug.
                cast.window.level = screen.displayUUID == NSScreen.screens.first?.displayUUID
                    ? .normal : NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
                cast.window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
                cast.window.setFrame(screen.frame, display: true)
                cast.window.orderFront(nil)
                casts[displayID] = cast
            } catch { store.error = "Display output failed: \(error.localizedDescription)" }
        }
        // A connected display may change geometry without changing UUID.
        for (id, cast) in casts {
            if let screen = NSScreen.screen(withUUID: id) { cast.window.setFrame(screen.frame, display: true) }
        }
        for runtime in runtimes.values {
            guard runtime.config.outputs.ndiEnabled else {
                store.outputStatus[runtime.config.id] = "NDI off"
                continue
            }
            guard runtime.output == nil else { continue }
            let output = OverlayOutput()
            runtime.output = output
            output.onFailure = { [weak self, weak runtime, weak output] message in
                guard let self = self, let runtime = runtime, let output = output,
                      self.runtimes[runtime.config.id] === runtime, runtime.output === output else { return }
                self.store.outputStatus[runtime.config.id] = "NDI stopped: \(message)"
            }
            store.outputStatus[runtime.config.id] = "Starting NDI…"
            Task { [weak self, weak runtime] in
                guard let self = self, let runtime = runtime else { return }
                do {
                    try await output.start(window: runtime.preview.window, sourceName: runtime.config.outputs.ndiSourceName)
                    if self.runtimes[runtime.config.id] === runtime, runtime.output === output, output.isRunning {
                        self.store.outputStatus[runtime.config.id] = "NDI running"
                    }
                } catch {
                    if self.runtimes[runtime.config.id] === runtime, runtime.output === output {
                        self.store.outputStatus[runtime.config.id] = "NDI unavailable: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

/// Full logical viewport, scaled for local preview. ScreenCaptureKit captures the
/// composed window; its physical resolution must be checked independently.
@MainActor
private final class FixedRenderView: NSView {
    private let renderSize = NSSize(width: 1920, height: 1080)
    init(contentView: NSView) {
        super.init(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
        // VERIFY-ON-MAC: WebKit layout under bounds scaling, Retina capture quality,
        // preview occlusion and full-resolution source-window strategy.
        setBoundsSize(renderSize)
        contentView.autoresizingMask = []
        contentView.frame = NSRect(origin: .zero, size: renderSize)
        addSubview(contentView)
    }
    required init?(coder: NSCoder) { nil }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); setBoundsSize(renderSize) }
}
