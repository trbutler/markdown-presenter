import Foundation
import CoreFoundation

/// Messages posted by the deck through
/// `window.webkit.messageHandlers.presenter.postMessage(...)`.
public enum BridgeMessage: Equatable, Sendable {
    /// A view finished loading (also sent after a reload or a web-process crash).
    /// `count` and `titles` follow the play order, fillers included. `view` is
    /// the name the page was opened with (an alias such as `confidence` stays
    /// as sent; the template's own `notes`/`lyrics`/`service` parse as nil).
    case ready(view: ViewRole?, count: Int, titles: [String])
    /// A view asked for a change (control-view click, on-screen button).
    /// Swift applies it and pushes the resulting state to every view.
    case request(index: Int?, black: Bool?, timerStart: Double?, lowerThird: Bool? = nil)
    /// An apply has reached the page; token identifies the native push being acknowledged.
    case applied(token: String)
    /// Short MIDI messages emitted once per audience slide change.
    case midi(MIDIRequest)

    /// `body` is `WKScriptMessage.body`: an NSDictionary of NSString/NSNumber/NSArray.
    public init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else {
            return nil
        }
        switch type {
        case "ready":
            let view = (dict["view"] as? String).flatMap(ViewRole.init(rawValue:))
            self = .ready(view: view, count: BridgeMessage.int(dict["count"]) ?? 0, titles: dict["titles"] as? [String] ?? [])
        case "applied":
            guard let token = dict["token"] as? String, !token.isEmpty else {
                return nil
            }
            self = .applied(token: token)
        case "midi":
            guard let request = MIDIRequest(body: dict) else {
                return nil
            }
            self = .midi(request)
        case "request":
            let lowerThird = BridgeMessage.bool(dict["lowerThird"])
            if dict["lowerThird"] != nil && lowerThird == nil {
                return nil
            }
            self = .request(index: BridgeMessage.int(dict["index"]), black: dict["black"] as? Bool, timerStart: BridgeMessage.double(dict["timerStart"]), lowerThird: lowerThird)
        default:
            return nil
        }
    }

    /// The state transitions this message asks for.
    public var commands: [DeckCommand] {
        switch self {
        case .ready(_, let count, _):
            return [.setCount(count)]
        case .applied, .midi:
            return []
        case .request(let index, let black, let timerStart, let lowerThird):
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
            if let lowerThird = lowerThird {
                result.append(.setLowerThird(lowerThird))
            }
            return result
        }
    }

    private static func bool(_ value: Any?) -> Bool? {
        // WKScriptMessage delivers JS booleans as CFBoolean-backed NSNumber.
        // Conditional `as? Bool` also accepts numeric NSNumber 0/1; reject those.
        // VERIFY-ON-MAC: confirm WKScriptMessage preserves JS boolean CFBoolean identity.
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }

    private static func int(_ value: Any?) -> Int? {
        if let n = value as? Int {
            return n
        }
        if let d = value as? Double, d.isFinite {
            return Int(exactly: d)
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

    /// Injected at document start with one seed per controller, so every view
    /// builds the same play order (filler placement) when the deck has no
    /// `// seed`. `presenter.apply`'s index counts that play order.
    public static func injectSeed(_ seed: UInt32) -> String {
        "window.__presenterSeed = \(seed);"
    }

    /// Render `state` in a page. The template's `presenter.apply` never echoes
    /// back, so pushing the same state to all views cannot loop.
    public static func apply(_ state: DeckState) -> String {
        "(function() { if (!window.presenter) return; window.presenter.apply(\(stateObject(state))); \(lowerTiming(state)) })();"
    }

    /// Native compatibility shim until the template acknowledges applies itself.
    /// The page must post {type: 'applied', token: <this push's token>} after
    /// applying state. Two animation frames let the restored state reach painting.
    public static func apply(_ state: DeckState, acknowledgement token: String) -> String {
        guard let data = try? JSONEncoder().encode(token), let tokenJSON = String(data: data, encoding: .utf8) else {
            return ""
        }
        return """
        (function() {
            if (!window.presenter || typeof window.presenter.apply !== 'function') return;
            window.presenter.apply(\(stateObject(state)), \(tokenJSON));
            \(lowerTiming(state))
            window.requestAnimationFrame(function() {
                window.requestAnimationFrame(function() {
                    window.webkit.messageHandlers.presenter.postMessage({type: 'applied', token: \(tokenJSON)});
                });
            });
        })();
        """
    }

    /// Compatibility with the current template: applyState ignores lowerStart.
    /// Its top-level helper clears the old timers and seeks buildIn/buildOut.
    /// Do this only when the timing origin differs, never while L overrides it.
    // VERIFY-ON-MAC: evaluateJavaScript must run in the page content world so
    // the template's global lexical lowerStart and startLowerThird are visible.
    private static func lowerTiming(_ state: DeckState) -> String {
        guard state.lowerThird == nil, let origin = state.lowerStart,
              origin.isFinite, origin > 0 else { return "" }
        return """
        if (typeof startLowerThird === 'function' && typeof lowerStart === 'number' &&
            Math.abs(lowerStart - \(origin)) > 1) {
            const slide = document.querySelector('.slide.active');
            if (slide) startLowerThird(slide, Math.max(0, Date.now() - \(origin)));
        }
        """
    }

    private static func stateObject(_ state: DeckState) -> String {
        let lowerThird = state.lowerThird.map { $0 ? "true" : "false" } ?? "null"
        let lowerStart = state.lowerStart.flatMap { $0.isFinite && $0 > 0 ? String($0) : nil } ?? "null"
        return "{index: \(state.index), black: \(state.black), timerStart: \(state.timerStart), lowerThird: \(lowerThird), lowerStart: \(lowerStart)}"
    }
}
