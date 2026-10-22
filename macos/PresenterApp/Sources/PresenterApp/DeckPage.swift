import AppKit
import WebKit
import PresenterCore

/// One WKWebView showing the deck as one view role.
@MainActor
final class DeckPage: NSObject, WKNavigationDelegate {
    let role: ViewRole
    let webView: WKWebView
    let presentationView: NSView
    private(set) var isRestoring = true
    private(set) var restorationID = UUID()
    private weak var controller: DeckController?

    init(role: ViewRole, deckURL: URL, controller: DeckController) {
        self.role = role
        self.controller = controller

        let content = WKUserContentController()
        content.addUserScript(WKUserScript(source: BridgeScript.injectView(role), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.addUserScript(WKUserScript(source: BridgeScript.injectSeed(controller.seed), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let config = WKWebViewConfiguration()
        config.userContentController = content
        // Video slides and soundtrack beds must start without a click.
        config.mediaTypesRequiringUserActionForPlayback = []
        // Only the audience view makes sound; the template mutes media in other views.
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720), configuration: config)
        presentationView = NSView(frame: webView.frame)
        super.init()

        content.add(ScriptMessageRelay(role: role, controller: controller), name: BridgeScript.handlerName)
        webView.navigationDelegate = self
        if role == .overlay {
            // Let the page's transparent background through (key/fill for NDI).
            webView.setValue(false, forKey: "drawsBackground")
        }
        presentationView.wantsLayer = true
        presentationView.layer?.backgroundColor = (role == .audience ? NSColor.black : NSColor.clear).cgColor
        webView.autoresizingMask = [.width, .height]
        presentationView.addSubview(webView)
        controller.register(webView, as: role) { [weak self] in
            self?.finishRestoration()
        }
        load(deckURL)
    }

    func load(_ deckURL: URL) {
        beginRestoration()
        var components = URLComponents(url: deckURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "view", value: role.rawValue)]
        let url = components?.url ?? deckURL
        // Read access to the deck's folder so relative images, videos/ and music/ load.
        webView.loadFileURL(url, allowingReadAccessTo: deckURL.deletingLastPathComponent())
    }

    func reload() {
        beginRestoration()
        webView.reload()
    }

    private func beginRestoration() {
        isRestoring = true
        restorationID = UUID()
        controller?.beginRestoration(for: role)
        if role == .audience || role == .overlay {
            // Native black cover for audience; transparent cover for overlay.
            // VERIFY-ON-MAC: confirm alpha concealment preserves WebKit animation
            // callbacks and that the first acknowledged state paints before reveal.
            webView.alphaValue = 0
        }
    }

    private func finishRestoration() {
        isRestoring = false
        webView.alphaValue = 1
    }

    // A crashed web process must not leave a projector black: reload, and the
    // page's `ready` message pulls the live state back in.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("[DeckPage] %@ web process terminated; reloading", role.title)
        reload()
    }
}

/// Weak relay so WKUserContentController (which retains its handlers) does not
/// keep the controller alive.
// VERIFY-ON-MAC: WKScriptMessageHandler isolation annotations vary by SDK.
final class ScriptMessageRelay: NSObject, WKScriptMessageHandler {
    private let role: ViewRole
    private weak var controller: DeckController?

    init(role: ViewRole, controller: DeckController) {
        self.role = role
        self.controller = controller
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let parsed = BridgeMessage(body: message.body) else {
            NSLog("[Bridge] ignored message from %@: %@", role.rawValue, String(describing: message.body))
            return
        }
        let role = self.role
        Task { @MainActor [weak controller] in
            controller?.handle(parsed, from: role)
        }
    }
}
