import XCTest
@testable import PresenterCore

final class MIDIPendingNoteOffsTests: XCTestCase {
    func testShutdownFlushesPendingOffsBeforeAllNotesOffPerEndpointAndChannel() throws {
        var pending = MIDIPendingNoteOffs()
        pending.recordSent([0x90, 60, 100], to: 10)
        pending.recordSent([0x92, 64, 100], to: 20)
        let completed = try XCTUnwrap(pending.track([0x80, 60, 0], to: 10))
        _ = try XCTUnwrap(pending.track([0x82, 64, 0], to: 20))
        pending.complete(completed)

        XCTAssertEqual(pending.drainForShutdown(), [
            MIDIEndpointMessage(endpoint: 20, bytes: [0x82, 64, 0]),
            MIDIEndpointMessage(endpoint: 10, bytes: [0xB0, 123, 0]),
            MIDIEndpointMessage(endpoint: 20, bytes: [0xB2, 123, 0])
        ])
        XCTAssertEqual(pending.drainForShutdown(), [])
    }

    func testRepeatedNotesHaveIndependentCompletionTokens() throws {
        var pending = MIDIPendingNoteOffs()
        let first = try XCTUnwrap(pending.track([0x80, 60, 0], to: 10))
        let second = try XCTUnwrap(pending.track([0x80, 60, 0], to: 10))
        XCTAssertNotEqual(first, second)
        pending.complete(first)
        pending.complete(first)
        XCTAssertEqual(pending.drainForShutdown(), [
            MIDIEndpointMessage(endpoint: 10, bytes: [0x80, 60, 0]),
            MIDIEndpointMessage(endpoint: 10, bytes: [0xB0, 123, 0])
        ])
        // A late scheduled completion after shutdown cannot resurrect old state.
        pending.complete(second)
        XCTAssertEqual(pending.drainForShutdown(), [])
    }

    func testVelocityZeroNoteOnIsPendingOffAndOtherMessagesAreNot() throws {
        var pending = MIDIPendingNoteOffs()
        _ = try XCTUnwrap(pending.track([0x9F, 72, 0], to: 30))
        XCTAssertNil(pending.track([0x9F, 72, 100], to: 30))
        XCTAssertNil(pending.track([0xBF, 20, 100], to: 30))
        XCTAssertNil(pending.track([0x80, 72], to: 30))
        XCTAssertNil(pending.track([], to: 30))
        XCTAssertEqual(pending.drainForShutdown(), [
            MIDIEndpointMessage(endpoint: 30, bytes: [0x9F, 72, 0]),
            MIDIEndpointMessage(endpoint: 30, bytes: [0xBF, 123, 0])
        ])
    }

    func testAllNotesOffDeduplicatesUsedChannelsAndIgnoresSystemMessages() {
        var pending = MIDIPendingNoteOffs()
        pending.recordSent([0x90, 60, 100], to: 10)
        pending.recordSent([0x90, 64, 100], to: 10)
        pending.recordSent([0xC3, 5], to: 10)
        pending.recordSent([0x9F, 72, 100], to: 20)
        pending.recordSent([0xF8], to: 40)
        pending.recordSent([], to: 40)
        XCTAssertEqual(pending.drainForShutdown(), [
            MIDIEndpointMessage(endpoint: 10, bytes: [0xB0, 123, 0]),
            MIDIEndpointMessage(endpoint: 10, bytes: [0xB3, 123, 0]),
            MIDIEndpointMessage(endpoint: 20, bytes: [0xBF, 123, 0])
        ])
    }
}
