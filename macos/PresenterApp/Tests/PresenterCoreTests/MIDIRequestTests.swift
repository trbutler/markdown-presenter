import XCTest
@testable import PresenterCore

final class MIDIRequestTests: XCTestCase {
    private func body(bytes: Any = [0x90, 60, 100], delay: Any = 0) -> [String: Any] {
        ["type": "midi", "index": 3, "out": "Lighting", "messages": [["bytes": bytes, "delayMs": delay]]]
    }

    func testParsesAudienceNoteOnAndDelayedNoteOff() throws {
        var payload = body()
        payload["messages"] = [["bytes": [0x90, 60, 100], "delayMs": 0],
                               ["bytes": [0x80, 60, 0], "delayMs": 200]] as [[String: Any]]
        let request = try XCTUnwrap(MIDIRequest(body: payload))
        XCTAssertEqual(request.index, 3)
        XCTAssertEqual(request.out, "Lighting")
        XCTAssertEqual(request.messages.map(\.bytes), [[0x90, 60, 100], [0x80, 60, 0]])
        XCTAssertEqual(request.messages.map(\.delayMs), [0, 200])
        let bridge = try XCTUnwrap(BridgeMessage(body: payload))
        XCTAssertEqual(bridge, .midi(request))
        XCTAssertEqual(BridgeMessage(body: payload as NSDictionary), bridge)
        XCTAssertEqual(bridge.commands, [])

    }

    func testAcceptsByteLengthsAndNumericBoundaries() throws {
        for bytes in [[0x80], [0xC0, 0], [0xFF, 0, 255]] {
            let request = try XCTUnwrap(MIDIRequest(body: body(bytes: bytes, delay: 10000)))
            XCTAssertEqual(request.messages.first?.bytes, bytes.map { UInt8($0) })
        }
        let fractionalDelay = try XCTUnwrap(MIDIRequest(body: body(delay: 0.5)))
        XCTAssertEqual(fractionalDelay.messages.first?.delayMs, 0.5)
        let boxed = body(bytes: [NSNumber(value: 144), NSNumber(value: 60), NSNumber(value: 100)], delay: NSNumber(value: 200))
        XCTAssertNotNil(MIDIRequest(body: boxed))
        var anyOutput = body()
        anyOutput["out"] = ""
        anyOutput["index"] = 0
        XCTAssertNotNil(MIDIRequest(body: anyOutput))
    }

    func testRejectsMalformedBytesAtomically() {
        let invalidBytes: [Any] = [[] as [Int], [0x90, 1, 2, 3], [127], [-1], [256],
                                   [0x90, -1, 1], [0x90, 256, 1], [144.5, 60, 1],
                                   [0x90, 1.5, 1], [0x90, true, 1] as [Any], ["144", "60"],
                                   [0x90, NSNull()] as [Any], [Double.infinity], [Double.nan], [1e100], "144,60,1"]
        for bytes in invalidBytes {
            XCTAssertNil(MIDIRequest(body: body(bytes: bytes)))
            XCTAssertNil(BridgeMessage(body: body(bytes: bytes)))
        }
        var mixed = body()
        mixed["messages"] = [["bytes": [0x90, 60, 100], "delayMs": 0],
                             ["bytes": [0x80, 60, -1], "delayMs": 200]] as [[String: Any]]
        XCTAssertNil(BridgeMessage(body: mixed))
    }

    func testRejectsMalformedDelays() {
        let invalidDelays: [Any] = [-1, 10000.1, 1e100, Double.infinity, Double.nan, true, "200", NSNull()]
        for delay in invalidDelays {
            XCTAssertNil(MIDIRequest(body: body(delay: delay)))
        }
    }

    func testEnforcesBatchLimitAndMemberSchema() {
        let message: [String: Any] = ["bytes": [0xF8], "delayMs": 0]
        var payload = body()
        payload["messages"] = Array(repeating: message, count: 16)
        XCTAssertEqual(MIDIRequest(body: payload)?.messages.count, 16)
        payload["messages"] = Array(repeating: message, count: 17)
        XCTAssertNil(MIDIRequest(body: payload))
        payload["messages"] = [] as [Any]
        XCTAssertEqual(MIDIRequest(body: payload)?.messages.count, 0)
        let invalidMessages: [Any] = [["bytes": [0x90]], ["delayMs": 0],
                                      ["bytes": [0x90], "delayMs": 0, "extra": 1] as [String: Any], "message", NSNull()]
        for message in invalidMessages {
            payload["messages"] = [message]
            XCTAssertNil(MIDIRequest(body: payload))
        }
    }

    func testRejectsMalformedEnvelope() {
        for key in ["type", "index", "out", "messages"] {
            var payload = body()
            payload.removeValue(forKey: key)
            XCTAssertNil(MIDIRequest(body: payload))
        }
        let badIndices: [Any] = [-1, 1.5, 1e100, true, "3", Double.nan, NSNull()]
        for index in badIndices {
            var payload = body()
            payload["index"] = index
            XCTAssertNil(BridgeMessage(body: payload))
        }
        var payload = body()
        payload["out"] = 123
        XCTAssertNil(MIDIRequest(body: payload))
        payload = body()
        payload["messages"] = "messages"
        XCTAssertNil(MIDIRequest(body: payload))
        payload = body()
        payload["extra"] = 123
        XCTAssertNil(MIDIRequest(body: payload))
        payload = body()
        payload["type"] = "request"
        XCTAssertNil(MIDIRequest(body: payload))
        XCTAssertNil(MIDIRequest(body: "midi"))
    }
}
