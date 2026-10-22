import Foundation

/// Messages posted by the deck through
/// `window.webkit.messageHandlers.presenter.postMessage(...)`.
public enum BridgeMessage: Equatable, Sendable {
    /// A view finished loading (also sent after a reload or a web-process crash).
    case ready(view: ViewRole?, count: Int, titles: [String])
    /// A view asked for a change (control-view click, on-screen button).
    /// Swift applies it and pushes the resulting state to every view.
    case request(index: Int?, black: Bool?, timerStart: Double?)

    /// `body` is `WKScriptMessage.body`: an NSDictionary of NSString/NSNumber/NSArray.
    public init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else {
            return nil
        }
        switch type {
        case "ready":
            let view = (dict["view"] as? String).flatMap(ViewRole.init(rawValue:))
            self = .ready(view: view, count: BridgeMessage.int(dict["count"]) ?? 0, titles: dict["titles"] as? [String] ?? [])
        case "request":
            self = .request(index: BridgeMessage.int(dict["index"]), black: dict["black"] as? Bool, timerStart: BridgeMessage.double(dict["timerStart"]))
        default:
            return nil
        }
    }

    /// The state transitions this message asks for.
    public var commands: [DeckCommand] {
        switch self {
        case .ready(_, let count, _):
            return [.setCount(count)]
        case .request(let index, let black, let timerStart):
            var result: [DeckCommand] = []
            if let index = index {
                result.append(.go(index))
            }
            if let black = black {
                result.append(.setBlack(black))
            }
            if let timerStart = timerStart {
                result.append(.resetTimer(at: timerStart))
            }
            return result
        }
    }

    private static func int(_ value: Any?) -> Int? {
        if let n = value as? Int {
            return n
        }
        if let d = value as? Double, d.isFinite {
            return Int(d)
        }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let d = value as? Double {
            return d
        }
        if let n = value as? Int {
            return Double(n)
        }
        return nil
    }
}

/// JavaScript that Swift evaluates in the deck pages.
public enum BridgeScript {
    /// Name of the WKScriptMessageHandler the template looks for.
    public static let handlerName = "presenter"

    /// Injected at document start so the template knows its view even if a
    /// file URL loses its query string.
    public static func injectView(_ role: ViewRole) -> String {
        "window.__presenterView = '\(role.rawValue)';"
    }

    /// Render `state` in a page. The template's `presenter.apply` never echoes
    /// back, so pushing the same state to all views cannot loop.
    public static func apply(_ state: DeckState) -> String {
        "window.presenter && window.presenter.apply({index: \(state.index), black: \(state.black), timerStart: \(state.timerStart)});"
    }
}
