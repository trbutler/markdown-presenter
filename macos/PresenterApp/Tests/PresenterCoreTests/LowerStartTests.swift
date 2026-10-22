import XCTest
@testable import PresenterCore

final class LowerStartTests: XCTestCase {
    func testFirstReadyStartsOriginAndLateReadyPreservesIt() {
        let initial = DeckState(timerStart: 100)
        let ready = initial.applying(.setCount(3), at: 1000)
        XCTAssertEqual(ready.lowerStart, 1000)
        XCTAssertEqual(ready.applying(.setCount(3), at: 9000).lowerStart, 1000)
        XCTAssertEqual(ready.applying(.setCount(4), at: 9000).lowerStart, 1000)
    }

    func testEveryActualSlideMoveRestartsTimingAndClearsOverride() {
        let initial = DeckState(index: 1, count: 3, lowerThird: false, lowerStart: 1000)
        for command in [DeckCommand.next, .previous, .first, .last, .go(2), .setCount(1)] {
            let moved = initial.applying(command, at: 5000)
            XCTAssertEqual(moved.lowerStart, 5000)
            XCTAssertNil(moved.lowerThird)
        }
        let returned = initial.applying(.go(2), at: 5000).applying(.go(1), at: 8000)
        XCTAssertEqual(returned.lowerStart, 8000)
    }

    func testSameSlideBlackTimerAndManualOverridePreserveOrigin() {
        let initial = DeckState(index: 1, count: 3, lowerStart: 1000)
        for command in [DeckCommand.go(1), .go(-1), .go(3), .setCount(3), .toggleBlack,
                        .setBlack(true), .resetTimer(at: 4000), .setLowerThird(true), .setLowerThird(false)] {
            XCTAssertEqual(initial.applying(command, at: 9000).lowerStart, 1000)
        }
        let blacked = initial.applying(.setBlack(true), at: 3000)
        for command in [DeckCommand.next, .previous] {
            XCTAssertEqual(blacked.applying(command, at: 9000).lowerStart, 1000)
        }
    }

    func testLateApplyIncludesOriginAndSeeksBeforeAcknowledgement() throws {
        let state = DeckState(index: 2, timerStart: 100, count: 3, lowerStart: 1234)
        for script in [BridgeScript.apply(state), BridgeScript.apply(state, acknowledgement: "late-view")] {
            XCTAssertTrue(script.contains("lowerStart: 1234.0"))
            XCTAssertTrue(script.contains("Date.now() - 1234.0"))
            XCTAssertTrue(script.contains("startLowerThird(slide,"))
            XCTAssertTrue(script.contains("Math.abs(lowerStart - 1234.0) > 1"))
        }
        let script = BridgeScript.apply(state, acknowledgement: "late-view")
        let seek = try XCTUnwrap(script.range(of: "startLowerThird(slide,"))
        let ack = try XCTUnwrap(script.range(of: "window.requestAnimationFrame"))
        XCTAssertLessThan(seek.lowerBound, ack.lowerBound)
        for value in [true, false] {
            var overridden = state
            overridden.lowerThird = value
            XCTAssertFalse(BridgeScript.apply(overridden).contains("startLowerThird(slide,"))
            XCTAssertTrue(BridgeScript.apply(overridden).contains("lowerThird: \(value)"))
        }
    }

    func testOriginRoundTripLegacyDecodeAndInvalidOriginScript() throws {
        let state = DeckState(index: 2, timerStart: 100, count: 3, lowerStart: 1234)
        XCTAssertEqual(try JSONDecoder().decode(DeckState.self, from: JSONEncoder().encode(state)), state)
        let legacy = Data(#"{"index":1,"black":false,"timerStart":1000,"count":3}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(DeckState.self, from: legacy).lowerStart)
        for value in [Double.nan, .infinity, -1, 0] {
            var invalid = state
            invalid.lowerStart = value
            let script = BridgeScript.apply(invalid)
            XCTAssertTrue(script.contains("lowerStart: null"))
            XCTAssertFalse(script.contains("startLowerThird(slide,"))
        }
    }
}
