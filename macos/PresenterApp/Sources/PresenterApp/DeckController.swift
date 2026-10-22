import AppKit
import WebKit
import PresenterCore

@MainActor
final class DeckController {
    private struct Registration {
        let webView: WKWebView
        let viewID: UUID
        let isCanonical: Bool
        let audienceRendering: Bool
        let onApplied: @MainActor () -> Void
    }

    private(set) var state = DeckState()
    let seed = UInt32.random(in: 0...UInt32.max)
    private var metadataViewID: UUID?
    private var registrations: [UUID: Registration] = [:]
    private var pendingApplies: [UUID: String] = [:]
    private var bridgeGate = ViewBridgeGate()
    private let midi = MIDIOutput()

    func stopMIDI(completion: @escaping @Sendable () -> Void = {}) { midi.stop(completion: completion) }

    func configure(_ list: ViewList, deckURL: URL) {
        bridgeGate.configure(list)
        metadataViewID = list.primaryMainID ?? list.views.first(where: {
            guard let url = try? $0.resolvedURL(deckURL: deckURL) else { return false }
            return ViewURLPolicy.allowsBridge(url, deckURL: deckURL)
        })?.id
    }

    func register(_ webView: WKWebView, instanceID: UUID, viewID: UUID, isCanonical: Bool,
                  audienceRendering: Bool, onApplied: @escaping @MainActor () -> Void) {
        bridgeGate.register(instanceID: instanceID, viewID: viewID, isCanonical: isCanonical,
                            audienceRendering: audienceRendering)
        registrations[instanceID] = Registration(webView: webView, viewID: viewID, isCanonical: isCanonical,
                                                audienceRendering: audienceRendering, onApplied: onApplied)
    }

    func beginRestoration(_ instanceID: UUID) { pendingApplies[instanceID] = nil }
    func unregister(_ instanceID: UUID) {
        bridgeGate.unregister(instanceID)
        registrations[instanceID] = nil
        pendingApplies[instanceID] = nil
    }

    var ownsFocusedWindow: Bool {
        guard let window = NSApp.keyWindow else { return false }
        return registrations.values.contains { $0.webView.window === window }
    }

    func perform(_ command: DeckCommand) { perform([command]) }
    func perform(_ commands: [DeckCommand]) {
        let now = DeckState.nowMillis()
        let next = commands.reduce(state) { $0.applying($1, at: now) }
        guard next != state else { return }
        state = next
        for id in registrations.keys { push(to: id) }
    }

    func handle(_ message: BridgeMessage, from instanceID: UUID, webView: WKWebView) {
        guard let registration = registrations[instanceID], registration.webView === webView else { return }
        switch message {
        case .applied(let token):
            guard pendingApplies[instanceID] == token else { return }
            pendingApplies[instanceID] = nil
            registration.onApplied()
        case .ready:
            if registration.isCanonical && registration.viewID == metadataViewID { perform(message.commands) }
            push(to: instanceID)
        case .midi(let request):
            guard bridgeGate.permitsMIDI(from: instanceID) else { return }
            midi.send(request)
        case .request:
            guard bridgeGate.permitsRequest(from: instanceID) else { return }
            perform(message.commands)
        }
    }

    private func push(to instanceID: UUID) {
        guard let registration = registrations[instanceID] else { return }
        let token = UUID().uuidString
        pendingApplies[instanceID] = token
        registration.webView.evaluateJavaScript(BridgeScript.apply(state, acknowledgement: token), completionHandler: nil)
    }
}
