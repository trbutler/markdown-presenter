import AppKit
import PresenterCore

/// Borderless windows can be key, so clicks and keys still reach the app.
final class PresenterWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Creates the audience, confidence and control windows, places each on its
/// assigned display, persists the assignment, and re-places on hot-plug.
@MainActor
final class WindowManager {
    private static let defaultsKey = "screenAssignments"

    let deckURL: URL
    private let controller: DeckController
    private(set) var pages: [ViewRole: DeckPage] = [:]
    private var windows: [ViewRole: NSWindow] = [:]
    private(set) var assignments: ScreenAssignments
    private var screenObserver: NSObjectProtocol?

    init(deckURL: URL, controller: DeckController) {
        self.deckURL = deckURL
        self.controller = controller
        if let data = UserDefaults.standard.data(forKey: WindowManager.defaultsKey),
           let saved = try? JSONDecoder().decode(ScreenAssignments.self, from: data) {
            assignments = saved
        } else {
            assignments = ScreenAssignments()
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.placeAll()
            }
        }
    }

    func showAll() {
        for role in ViewRole.windowed {
            if windows[role] == nil {
                let page = DeckPage(role: role, deckURL: deckURL, controller: controller)
                pages[role] = page
                let window = PresenterWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540), styleMask: WindowManager.operatorStyle, backing: .buffered, defer: false)
                window.title = role.title
                window.isReleasedWhenClosed = false
                window.contentView = page.webView
                windows[role] = window
            }
        }
        placeAll()
        windows[.control]?.makeKeyAndOrderFront(nil)
    }

    func reloadAll() {
        pages.values.forEach { $0.reload() }
    }

    /// `displayID == nil` means Automatic.
    func assign(_ role: ViewRole, to displayID: String?) {
        assignments.assign(role, to: displayID)
        if let data = try? JSONEncoder().encode(assignments) {
            UserDefaults.standard.set(data, forKey: WindowManager.defaultsKey)
        }
        placeAll()
    }

    func resolvedDisplayID(for role: ViewRole) -> String? {
        assignments.resolve(role, among: NSScreen.displayInfos)?.id
    }

    func placeAll() {
        for role in ViewRole.windowed {
            place(role)
        }
    }

    private static let operatorStyle: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

    private func place(_ role: ViewRole) {
        guard let window = windows[role], let primary = NSScreen.screens.first else {
            return
        }
        let screen = NSScreen.screen(withUUID: resolvedDisplayID(for: role)) ?? primary
        let onOperatorScreen = screen.displayUUID == primary.displayUUID

        if role == .control || onOperatorScreen {
            // Operator screen (or the controls anywhere): an ordinary window,
            // so the menu bar, Dock and other apps stay usable.
            window.styleMask = WindowManager.operatorStyle
            window.level = .normal
            window.collectionBehavior = [.fullScreenAuxiliary]
            window.setFrame(operatorFrame(for: role, on: screen), display: true)
        } else {
            // A presentation display: cover it completely, above that screen's
            // menu bar when "Displays have separate Spaces" is on.
            window.styleMask = [.borderless]
            window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.setFrame(screen.frame, display: true)
        }
        window.orderFront(nil)
    }

    /// Tiles views that share the operator screen: controls on the left,
    /// confidence bottom-right, audience preview top-right.
    private func operatorFrame(for role: ViewRole, on screen: NSScreen) -> NSRect {
        let area = screen.visibleFrame
        let othersHere = ViewRole.windowed.filter { $0 != role && resolvedDisplayID(for: $0) == screen.displayUUID }
        if othersHere.isEmpty {
            return area
        }
        let left = NSRect(x: area.minX, y: area.minY, width: area.width * 0.55, height: area.height)
        let rightWidth = area.width - left.width
        let top = NSRect(x: left.maxX, y: area.midY, width: rightWidth, height: area.height / 2)
        let bottom = NSRect(x: left.maxX, y: area.minY, width: rightWidth, height: area.height / 2)
        switch role {
        case .control:
            return left
        case .audience:
            return top
        case .confidence, .overlay:
            return bottom
        }
    }
}
