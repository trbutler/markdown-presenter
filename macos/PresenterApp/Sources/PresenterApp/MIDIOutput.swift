import Foundation
import CoreMIDI
import PresenterCore

/// All CoreMIDI calls and mutable state belong to queue. Dispatch callbacks only
/// capture Sendable values or weak self; no MIDI work blocks the main actor.
final class MIDIOutput: @unchecked Sendable {
    private let queue = DispatchQueue(label: "PresenterApp.MIDIOutput")
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var destinations: [String: MIDIEndpointRef] = [:]
    private var missingOutputs: Set<String> = []
    private var reportedErrors: Set<String> = []
    private var stopped = false

    func send(_ request: MIDIRequest) {
        queue.async { [weak self] in
            self?.schedule(request)
        }
    }

    /// Enqueue shutdown; pending delayed messages become no-ops.
    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.stopped = true
            self.dispose()
        }
    }

    private func schedule(_ request: MIDIRequest) {
        guard !stopped, !request.messages.isEmpty, ensureStarted() else { return }
        let destination = resolveDestination(matching: request.out)
        guard destination != 0 else { return }
        let origin = DispatchTime.now()
        for message in request.messages {
            if message.delayMs == 0 {
                sendNow(message.bytes, to: destination)
            } else {
                // Keep a note-off on the endpoint that received its note-on.
                // A setup change invalidates lookup for future batches, not this one.
                queue.asyncAfter(deadline: origin + message.delayMs / 1000) { [weak self] in
                    guard let self = self, !self.stopped else { return }
                    self.sendNow(message.bytes, to: destination)
                }
            }
        }
    }

    private func ensureStarted() -> Bool {
        if client != 0 && port != 0 { return true }
        // VERIFY-ON-MAC: confirm CoreMIDI block signatures and notification enum
        // names with the macOS 13 SDK under Swift 5.9 strict concurrency checking.
        let clientStatus = MIDIClientCreateWithBlock("PresenterApp" as CFString, &client) { [weak self] notification in
            guard notification.pointee.messageID == .msgSetupChanged else { return }
            self?.queue.async { [weak self] in
                self?.destinations.removeAll()
            }
        }
        guard clientStatus == noErr else {
            reportOnce("client", "MIDI client creation failed (OSStatus \(clientStatus)); dropping MIDI")
            dispose()
            return false
        }
        let portStatus = MIDIOutputPortCreate(client, "PresenterApp Output" as CFString, &port)
        guard portStatus == noErr else {
            reportOnce("port", "MIDI output port creation failed (OSStatus \(portStatus)); dropping MIDI")
            dispose()
            return false
        }
        return true
    }

    private func resolveDestination(matching out: String) -> MIDIEndpointRef {
        let key = out.lowercased()
        if let cached = destinations[key] { return cached }
        for index in 0..<MIDIGetNumberOfDestinations() {
            let destination = MIDIGetDestination(index)
            guard destination != 0 else { continue }
            if out.isEmpty || displayName(of: destination)?.range(of: out, options: .caseInsensitive) != nil {
                destinations[key] = destination
                missingOutputs.remove(key)
                return destination
            }
        }
        destinations[key] = 0
        if missingOutputs.insert(key).inserted {
            NSLog("[MIDI] No destination matching '%@'; dropping MIDI", out)
        }
        return 0
    }

    private func displayName(of destination: MIDIEndpointRef) -> String? {
        // VERIFY-ON-MAC: check CFString ownership/import for MIDIObjectGetStringProperty.
        var name: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(destination, kMIDIPropertyDisplayName, &name) == noErr,
              let name = name?.takeRetainedValue() else { return nil }
        return name as String
    }

    private func sendNow(_ bytes: [UInt8], to destination: MIDIEndpointRef) {
        guard !stopped, port != 0 else { return }
        // One validated 1-3 byte message fits the C struct's inline packet storage.
        // VERIFY-ON-MAC: confirm MIDIPacketList pointer/size imports and MIDISend
        // with the target SDK; this legacy MIDI 1.0 API is available on macOS 13.
        var list = MIDIPacketList()
        let status: OSStatus = withUnsafeMutablePointer(to: &list) { listPointer in
            let packet = MIDIPacketListInit(listPointer)
            return bytes.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress,
                      MIDIPacketListAdd(listPointer, MemoryLayout<MIDIPacketList>.size, packet,
                                        0, buffer.count, base) != nil else {
                    return OSStatus(-50)
                }
                // CoreMIDI copies the list during this call; bytes/list remain alive.
                return MIDISend(port, destination, listPointer)
            }
        }
        if status != noErr {
            reportOnce("send-\(destination)", "MIDI send failed (OSStatus \(status)); dropping message")
        }
    }

    private func reportOnce(_ key: String, _ text: String) {
        if reportedErrors.insert(key).inserted {
            NSLog("[MIDI] %@", text)
        }
    }

    private func dispose() {
        if port != 0 {
            MIDIPortDispose(port)
            port = 0
        }
        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }
        destinations.removeAll()
    }

    deinit {
        // No task still owns self. Dispose copied handles on the worker even
        // when the last owner releases us on the main actor.
        let port = port
        let client = client
        queue.async {
            if port != 0 { MIDIPortDispose(port) }
            if client != 0 { MIDIClientDispose(client) }
        }
    }
}
