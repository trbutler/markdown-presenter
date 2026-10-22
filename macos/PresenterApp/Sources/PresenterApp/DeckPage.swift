import AppKit
import WebKit
import PresenterCore

@MainActor
final class DeckPage: NSObject, WKNavigationDelegate, WKUIDelegate {
    let instanceID = UUID()
    let viewID: UUID
    let webView: WKWebView
    let presentationView: NSView
    let bridgeEnabled: Bool
    private let deckURL: URL
    private let initialURL: URL
    private weak var controller: DeckController?
    private(set) var isRestoring = true

    init(config: ViewConfig, deckURL: URL, controller: DeckController, isCanonical: Bool, isAuthority: Bool) throws {
        self.viewID = config.id
        self.deckURL = ViewURLPolicy.canonicalFile(deckURL)
        self.controller = controller
        var url = try config.resolvedURL(deckURL: deckURL)
        bridgeEnabled = ViewURLPolicy.allowsBridge(url, deckURL: deckURL)
        if bridgeEnabled && !isAuthority, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var items = (components.queryItems ?? []).filter { $0.name.lowercased() != "mute" }
            items.append(URLQueryItem(name: "mute", value: "1"))
            components.queryItems = items
            url = components.url ?? url
        }
        initialURL = url
        let content = WKUserContentController()
        if bridgeEnabled {
            if let view = config.kind.queryView {
                content.addUserScript(WKUserScript(source: "window.__presenterView = '\(view)';", injectionTime: .atDocumentStart, forMainFrameOnly: true))
            }
            content.addUserScript(WKUserScript(source: BridgeScript.injectSeed(controller.seed), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = content
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080), configuration: configuration)
        presentationView = NSView(frame: webView.frame)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // VERIFY-ON-MAC: confirm public underPageBackgroundColor transparency and
        // layer composition for macOS 27; no private drawsBackground KVC fallback.
        webView.underPageBackgroundColor = .clear
        presentationView.wantsLayer = true
        let queryView = config.kind.queryView ?? URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "view" })?.value ?? "audience"
        let transparent = ["overlay", "lyrics"].contains(queryView.lowercased())
        presentationView.layer?.backgroundColor = (transparent ? NSColor.clear : NSColor.black).cgColor
        webView.autoresizingMask = [.width, .height]
        presentationView.addSubview(webView)
        if bridgeEnabled {
            let askedView = config.kind.queryView ?? URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "view" })?.value ?? "audience"
            let audienceRendering = !["notes", "confidence", "lyrics", "overlay", "service", "control"].contains(askedView.lowercased())
            content.add(ScriptMessageRelay(instanceID: instanceID, webView: webView, controller: controller), name: BridgeScript.handlerName)
            controller.register(webView, instanceID: instanceID, viewID: config.id, isCanonical: isCanonical,
                                audienceRendering: audienceRendering) { [weak self] in self?.finishRestoration() }
        }
        load()
    }

    private func load() {
        beginRestoration()
        if initialURL.isFileURL {
            webView.loadFileURL(initialURL, allowingReadAccessTo: deckURL.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: initialURL))
        }
    }

    func reload() { load() }
    func detach() {
        controller?.unregister(instanceID)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: BridgeScript.handlerName)
        webView.stopLoading()
    }

    private func beginRestoration() {
        isRestoring = bridgeEnabled
        if bridgeEnabled {
            controller?.beginRestoration(instanceID)
            // VERIFY-ON-MAC: validate concealment/animation-frame acknowledgements.
            webView.alphaValue = 0
        }
    }
    private func finishRestoration() { isRestoring = false; webView.alphaValue = 1 }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { load() }

    private func permitsNavigation(_ url: URL?) -> Bool {
        guard let url = url, (try? ViewURLPolicy.validate(url, deckURL: deckURL)) != nil else { return false }
        return !bridgeEnabled || ViewURLPolicy.allowsBridge(url, deckURL: deckURL)
    }

    // VERIFY-ON-MAC: validate WebKit action/response, redirects, subframes and
    // protocol isolation against the macOS 27 SDK. Trusted handlers never navigate away.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(permitsNavigation(navigationAction.request.url) && navigationAction.targetFrame != nil ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(permitsNavigation(navigationResponse.response.url) ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
}

// VERIFY-ON-MAC: WKScriptMessageHandler MainActor conformance with the current SDK.
@MainActor
private final class ScriptMessageRelay: NSObject, WKScriptMessageHandler {
    let instanceID: UUID
    weak var webView: WKWebView?
    weak var controller: DeckController?

    init(instanceID: UUID, webView: WKWebView, controller: DeckController) {
        self.instanceID = instanceID
        self.webView = webView
        self.controller = controller
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let webView = webView, message.webView === webView else { return }
        if let parsed = BridgeMessage(body: message.body) {
            controller?.handle(parsed, from: instanceID, webView: webView)
        }
    }
}
