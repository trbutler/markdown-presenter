import Foundation

/// The single source of truth for what every view shows. Swift owns it;
/// the web views only render it (see `BridgeScript.apply`).
public struct DeckState: Equatable, Codable, Sendable {
    public var index: Int
    public var black: Bool
    /// Timer origin in milliseconds since 1970, the same unit as JS `Date.now()`.
    public var timerStart: Double
    /// Slide count, learned from the first view's `ready` message.
    public var count: Int

    public init(index: Int = 0, black: Bool = false, timerStart: Double = DeckState.nowMillis(), count: Int = 0) {
        self.index = index
        self.black = black
        self.timerStart = timerStart
        self.count = count
    }

    public static func nowMillis() -> Double {
        Date().timeIntervalSince1970 * 1000
    }
}

public enum DeckCommand: Equatable, Sendable {
    case next
    case previous
    case first
    case last
    case toggleBlack
    case setBlack(Bool)
    case go(Int)
    case resetTimer(at: Double)
    /// A (re)loaded deck reported its slide count.
    case setCount(Int)
}

extension DeckState {
    /// Pure transition. Matches PowerPoint/Proclaim: while blacked, an advance
    /// or back key only lifts the black and does not move.
    public func applying(_ command: DeckCommand) -> DeckState {
        var s = self
        switch command {
        case .next:
            if black {
                s.black = false
            } else if index < count - 1 {
                s.index += 1
            }
        case .previous:
            if black {
                s.black = false
            } else if index > 0 {
                s.index -= 1
            }
        case .first:
            s.index = 0
        case .last:
            s.index = max(0, count - 1)
        case .toggleBlack:
            s.black.toggle()
        case .setBlack(let value):
            s.black = value
        case .go(let n):
            if n >= 0 && n < count {
                s.index = n
            }
        case .resetTimer(let at):
            s.timerStart = at
        case .setCount(let n):
            s.count = max(0, n)
            s.index = min(s.index, max(0, s.count - 1))
        }
        return s
    }
}
