import XCTest
@testable import PresenterCore

final class DeckStateTests: XCTestCase {
    func testNextAndPreviousClampAtEnds() {
        var s = DeckState(index: 0, count: 3)
        s = s.applying(.previous)
        XCTAssertEqual(s.index, 0)
        s = s.applying(.next).applying(.next).applying(.next)
        XCTAssertEqual(s.index, 2)
    }

    func testAdvanceWhileBlackOnlyLiftsBlack() {
        let s = DeckState(index: 1, black: true, count: 3).applying(.next)
        XCTAssertEqual(s.index, 1)
        XCTAssertFalse(s.black)
    }

    func testGoIgnoresOutOfRange() {
        let s = DeckState(index: 1, count: 3)
        XCTAssertEqual(s.applying(.go(7)).index, 1)
        XCTAssertEqual(s.applying(.go(2)).index, 2)
    }

    func testShrinkingDeckClampsIndex() {
        let s = DeckState(index: 9, count: 10).applying(.setCount(4))
        XCTAssertEqual(s.index, 3)
    }
}

final class KeyMapTests: XCTestCase {
    func testPowerPointKeys() {
        let k = KeyMap.KeyCode.self
        for code in [k.rightArrow, k.downArrow, k.pageDown, k.space] {
            XCTAssertEqual(KeyMap.command(keyCode: code, characters: nil), .next)
        }
        for code in [k.leftArrow, k.upArrow, k.pageUp] {
            XCTAssertEqual(KeyMap.command(keyCode: code, characters: nil), .previous)
        }
        XCTAssertEqual(KeyMap.command(keyCode: k.home, characters: nil), .first)
        XCTAssertEqual(KeyMap.command(keyCode: k.end, characters: nil), .last)
        XCTAssertEqual(KeyMap.command(keyCode: 0x0B, characters: "b"), .toggleBlack)
        XCTAssertEqual(KeyMap.command(keyCode: 0x2F, characters: "."), .toggleBlack)
    }

    func testCommandChordsPassThrough() {
        XCTAssertNil(KeyMap.command(keyCode: KeyMap.KeyCode.rightArrow, characters: nil, hasCommandModifiers: true))
        XCTAssertNil(KeyMap.command(keyCode: 0x0C, characters: "q"))
    }
}

final class BridgeTests: XCTestCase {
    func testParsesReady() {
        let m = BridgeMessage(body: ["type": "ready", "view": "control", "count": 3, "titles": ["A", "B", "C"]] as [String: Any])
        XCTAssertEqual(m, .ready(view: .control, count: 3, titles: ["A", "B", "C"]))
        XCTAssertEqual(m?.commands, [.setCount(3)])
    }

    func testParsesRequest() {
        let m = BridgeMessage(body: ["type": "request", "index": 2, "black": false] as [String: Any])
        XCTAssertEqual(m?.commands, [.go(2), .setBlack(false)])
    }

    func testRejectsJunk() {
        XCTAssertNil(BridgeMessage(body: "next"))
        XCTAssertNil(BridgeMessage(body: ["type": "launch-missiles"] as [String: Any]))
    }

    func testInjectSeedScript() {
        XCTAssertEqual(BridgeScript.injectSeed(49), "window.__presenterSeed = 49;")
    }

    func testApplyScript() {
        let js = BridgeScript.apply(DeckState(index: 4, black: true, timerStart: 1000, count: 9))
        XCTAssertEqual(js, "window.presenter && window.presenter.apply({index: 4, black: true, timerStart: 1000.0});")
    }
}

final class ScreenAssignmentTests: XCTestCase {
    let laptop = DisplayInfo(id: "L", name: "Built-in", isPrimary: true)
    let projector = DisplayInfo(id: "P", name: "Projector", isPrimary: false)
    let stageTV = DisplayInfo(id: "S", name: "Stage TV", isPrimary: false)

    func testAutomaticWithOneExternal() {
        let all = [laptop, projector]
        XCTAssertEqual(ScreenAssignments.automatic(.audience, among: all), projector)
        XCTAssertEqual(ScreenAssignments.automatic(.confidence, among: all), laptop)
        XCTAssertEqual(ScreenAssignments.automatic(.control, among: all), laptop)
    }

    func testAutomaticWithTwoExternals() {
        XCTAssertEqual(ScreenAssignments.automatic(.confidence, among: [laptop, projector, stageTV]), stageTV)
    }

    func testSavedChoiceSurvivesUnplugAndReturns() {
        var a = ScreenAssignments()
        a.assign(.confidence, to: "S")
        XCTAssertEqual(a.resolve(.confidence, among: [laptop, projector]), laptop)
        XCTAssertEqual(a.savedDisplayID(for: .confidence), "S")
        XCTAssertEqual(a.resolve(.confidence, among: [laptop, projector, stageTV]), stageTV)
    }
}
