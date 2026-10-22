import Foundation
import CoreFoundation

/// A validated short MIDI message. Delays are relative to receipt of its batch.
public struct MIDIMessage: Equatable, Sendable {
    public let bytes: [UInt8]
    public let delayMs: Double
}

/// The audience page's {type: 'midi', index, out, messages} bridge payload.
/// Validation is atomic: a malformed member rejects the whole batch.
public struct MIDIRequest: Equatable, Sendable {
    public let index: Int
    public let out: String
    public let messages: [MIDIMessage]

    public init?(body: Any) {
        guard let dict = body as? [String: Any],
              Set(dict.keys) == Set(["type", "index", "out", "messages"]),
              dict["type"] as? String == "midi",
              let indexValue = MIDIRequest.number(dict["index"]),
              let index = Int(exactly: indexValue), index >= 0,
              let out = dict["out"] as? String,
              let rawMessages = dict["messages"] as? [Any],
              rawMessages.count <= 16 else {
            return nil
        }
        var messages: [MIDIMessage] = []
        for rawMessage in rawMessages {
            guard let message = rawMessage as? [String: Any],
                  Set(message.keys) == Set(["bytes", "delayMs"]),
                  let rawBytes = message["bytes"] as? [Any],
                  (1...3).contains(rawBytes.count),
                  let delay = MIDIRequest.number(message["delayMs"]),
                  (0.0...10000.0).contains(delay) else {
                return nil
            }
            var bytes: [UInt8] = []
            for rawByte in rawBytes {
                guard let number = MIDIRequest.number(rawByte), let byte = UInt8(exactly: number) else {
                    return nil
                }
                bytes.append(byte)
            }
            guard let status = bytes.first, status >= 0x80 else {
                return nil
            }
            messages.append(MIDIMessage(bytes: bytes, delayMs: delay))
        }
        self.index = index
        self.out = out
        self.messages = messages
    }

    private static func number(_ value: Any?) -> Double? {
        // JavaScript booleans also bridge as NSNumber; they are not MIDI numbers.
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else {
            return nil
        }
        return number.doubleValue
    }
}
