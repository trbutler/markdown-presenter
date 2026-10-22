import WebKit
import PresenterCore

/// Owns `DeckState` and keeps every registered view in step with it.
/// All input (keys, menus, control-view clicks) becomes a `DeckCommand` here.
@MainActor
final class DeckController {
    private(set) var state = DeckState()
    /// Shared by every view so they agree on the filler order (see `BridgeScript.injectSeed`).
    let seed = UInt32.random(in: 0...UInt32.max)
    private(set) var titles: [String] = []
    private var webViews: [ViewRole: WKWebView] = [:]

    func register(_ webView: WKWebView, as role: ViewRole) {
        webViews[role] = webView
    }

    func unregister(_ role: ViewRole) {
        webViews[role] = nil
    }

    func perform(_ command: DeckCommand) {
        perform([command])
    }

    func perform(_ commands: [DeckCommand]) {
        let next = commands.reduce(state) { $0.applying($1) }
        guard next != state else {
            return
        }
        state = next
        broadcast()
    }

    func handle(_ message: BridgeMessage, from role: ViewRole) {
        if case .ready(_, _, let newTitles) = message {
            titles = newTitles
            perform(message.commands)
            // A view that (re)loaded starts at slide 0; bring it to the live state.
            push(to: role)
            return
        }
        perform(message.commands)
    }

    private func broadcast() {
        for role in webViews.keys {
            push(to: role)
        }
    }

    private func push(to role: ViewRole) {
        webViews[role]?.evaluateJavaScript(BridgeScript.apply(state), completionHandler: nil)
    }
}
