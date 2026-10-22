import XCTest
@testable import PresenterCore

final class LowerThirdTests: XCTestCase {
    func testParsesSwiftAndBridgeBooleans() throws {
        for value in [true, false] {
            let rawValues: [Any] = [value, NSNumber(value: value)]
            for rawValue in rawValues {
                let body: [String: Any] = ["type": "request", "lowerThird": rawValue]
                let message = try XCTUnwrap(BridgeMessage(body: body))
                XCTAssertEqual(message.commands, [.setLowerThird(value)])
                XCTAssertEqual(BridgeMessage(body: body as NSDictionary), message)
                let state = message.commands.reduce(DeckState(count: 3)) { $0.applying($1) }
                XCTAssertEqual(state.lowerThird, value)
                XCTAssertEqual(state.index, 0)
            }
        }
    }

    func testRejectsNumericAndOtherNonBooleanOverrides() {
        let invalid: [Any] = [0, 1, NSNumber(value: 0), NSNumber(value: 1), 0.0, 1.0,
                              2, "true", "false", NSNull(), [] as [Bool]]
        for value in invalid {
            // A malformed override rejects the whole request, including its index.
            let body: [String: Any] = ["type": "request", "index": 2, "lowerThird": value]
            XCTAssertNil(BridgeMessage(body: body))
            XCTAssertNil(BridgeMessage(body: body as NSDictionary))
        }
    }

    func testMissingOverridePreservesStateAndCompoundOverrideTargetsNewSlide() throws {
        let start = DeckState(index: 1, count: 3, lowerThird: true)
        let noOverride = try XCTUnwrap(BridgeMessage(body: ["type": "request", "black": true] as [String: Any]))
        XCTAssertEqual(noOverride.commands.reduce(start) { $0.applying($1) }.lowerThird, true)
        let compound = try XCTUnwrap(BridgeMessage(body: ["type": "request", "index": 2, "lowerThird": false] as [String: Any]))
        XCTAssertEqual(compound.commands, [.go(2), .setLowerThird(false)])
        let state = compound.commands.reduce(start) { $0.applying($1) }
        XCTAssertEqual(state.index, 2)
        XCTAssertEqual(state.lowerThird, false)
    }

    func testEveryActualIndexChangeClearsManualOverride() {
        for value in [true, false] {
            let start = DeckState(index: 1, count: 3, lowerThird: value)
            let commands: [DeckCommand] = [.next, .previous, .first, .last, .go(2), .setCount(1)]
            for command in commands {
                let state = start.applying(command)
                XCTAssertNotEqual(state.index, start.index)
                XCTAssertNil(state.lowerThird)
            }
        }
    }

    func testSameSlideAndUnblackCommandsPreserveManualOverride() {
        for value in [true, false] {
            let start = DeckState(index: 1, count: 3, lowerThird: value)
            let commands: [DeckCommand] = [.go(1), .go(-1), .go(3), .setCount(3), .setCount(4),
                                           .toggleBlack, .setBlack(true), .resetTimer(at: 1000)]
            for command in commands {
                XCTAssertEqual(start.applying(command).lowerThird, value)
            }
            for command in [DeckCommand.next, .previous] {
                let blacked = DeckState(index: 1, black: true, count: 3, lowerThird: value).applying(command)
                XCTAssertEqual(blacked.index, 1)
                XCTAssertFalse(blacked.black)
                XCTAssertEqual(blacked.lowerThird, value)
            }
            let first = DeckState(count: 3, lowerThird: value)
            XCTAssertEqual(first.applying(.previous).lowerThird, value)
            XCTAssertEqual(first.applying(.first).lowerThird, value)
            let last = DeckState(index: 2, count: 3, lowerThird: value)
            XCTAssertEqual(last.applying(.next).lowerThird, value)
            XCTAssertEqual(last.applying(.last).lowerThird, value)
        }
    }

    func testBothApplyPathsCarryTrueFalseAndNull() {
        let values: [Bool?] = [nil, true, false]
        for value in values {
            let state = DeckState(timerStart: 1000, count: 3, lowerThird: value)
            let literal = value.map { $0 ? "true" : "false" } ?? "null"
            XCTAssertTrue(BridgeScript.apply(state).contains("lowerThird: \(literal)"))
            XCTAssertTrue(BridgeScript.apply(state, acknowledgement: "push-123").contains("lowerThird: \(literal)"))
        }
    }

    func testCodablePreservesOverridesAndAcceptsOlderState() throws {
        let legacy = Data(#"{"index":1,"black":false,"timerStart":1000,"count":3}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(DeckState.self, from: legacy).lowerThird)
        let values: [Bool?] = [nil, true, false]
        for value in values {
            let state = DeckState(index: 1, timerStart: 1000, count: 3, lowerThird: value)
            XCTAssertEqual(try JSONDecoder().decode(DeckState.self, from: JSONEncoder().encode(state)), state)
        }
    }
}
