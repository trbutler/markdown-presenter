import Foundation

/// CoreMIDI-independent destination and bytes for a shutdown send.
public struct MIDIEndpointMessage: Equatable, Sendable {
    public let endpoint: UInt32
    public let bytes: [UInt8]
}

/// Used only on the MIDI worker queue. Each scheduled off has its own token,
/// including repeated notes on the same channel and endpoint.
public struct MIDIPendingNoteOffs: Sendable {
    private struct Pending: Sendable {
        let token: UUID
        let message: MIDIEndpointMessage
    }

    private var pending: [Pending] = []
    private var usedChannels: [UInt32: Set<UInt8>] = [:]

    public init() {}

    /// Recognize both explicit note-off and note-on with velocity zero.
    public mutating func track(_ bytes: [UInt8], to endpoint: UInt32) -> UUID? {
        guard bytes.count == 3 else { return nil }
        let kind = bytes[0] & 0xF0
        guard kind == 0x80 || (kind == 0x90 && bytes[2] == 0) else { return nil }
        let token = UUID()
        pending.append(Pending(token: token, message: MIDIEndpointMessage(endpoint: endpoint, bytes: bytes)))
        return token
    }

    /// Complete only after MIDISend succeeds, so failed offs remain retryable.
    public mutating func complete(_ token: UUID) {
        pending.removeAll { $0.token == token }
    }

    public mutating func recordSent(_ bytes: [UInt8], to endpoint: UInt32) {
        guard let status = bytes.first, status >= 0x80, status < 0xF0 else { return }
        usedChannels[endpoint, default: []].insert(status & 0x0F)
    }

    /// Every pending off first, then CC 123 value 0 on each used endpoint/channel.
    /// Draining is destructive and idempotent, so stop never replays an old flush.
    public mutating func drainForShutdown() -> [MIDIEndpointMessage] {
        var messages = pending.map(\.message)
        for message in messages {
            recordSent(message.bytes, to: message.endpoint)
        }
        for endpoint in usedChannels.keys.sorted() {
            for channel in (usedChannels[endpoint] ?? []).sorted() {
                messages.append(MIDIEndpointMessage(endpoint: endpoint, bytes: [0xB0 | channel, 123, 0]))
            }
        }
        pending.removeAll()
        usedChannels.removeAll()
        return messages
    }
}
