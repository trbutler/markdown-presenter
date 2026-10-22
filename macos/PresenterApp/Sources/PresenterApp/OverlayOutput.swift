import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import PresenterCore

// The filename is retained; output now belongs to any ViewConfig, not an overlay role.
enum ViewOutputError: Error, LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let text): return text }
    }
}

/// SDK adapter boundary. Never advertise a discarded-frame stub as a live source.
private final class NDIGPUFrameSink: FrameSink {
    let displayName = "NDI"
    func start(sourceName: String, width: Int, height: Int, framesPerSecond: Double) throws {
        // VERIFY-ON-MAC/SDK: add the actual vendor GPU/IOSurface or mapped-buffer
        // binding and release callback; no zero-copy/codec capability is assumed.
        throw ViewOutputError.unavailable("NDI GPU output requires a verified NDI SDK binding")
    }
    func send(_ frame: GPUFrame) {}
    func stop() {}
}

private final class CaptureReceiver: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "PresenterApp.ViewCapture")
    private let converter: FrameConverter
    private let sink = NDIGPUFrameSink()
    private var stopped = false
    private var inFlight = false
    private let onError: @Sendable (String) -> Void

    init(width: Int, height: Int, onError: @escaping @Sendable (String) -> Void) throws {
        self.onError = onError
        converter = try FrameConverter(width: width, height: height)
        super.init()
    }

    static func make(width: Int, height: Int, onError: @escaping @Sendable (String) -> Void) async throws -> CaptureReceiver {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CaptureReceiver, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: try CaptureReceiver(width: width, height: height, onError: onError)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    func start(sourceName: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try sink.start(sourceName: sourceName, width: converter.width, height: converter.height, framesPerSecond: 30)
                    continuation.resume()
                } catch {
                    sink.stop()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        queue.async { [self] in
            stopped = true
            sink.stop()
        }
    }

    // VERIFY-ON-MAC: SCStream frame attachments/status and stop delegate imports.
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        stop()
        onError(error.localizedDescription)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !stopped, !inFlight, type == .screen, CMSampleBufferIsValid(sampleBuffer),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: status) == .complete,
              let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        inFlight = true
        converter.convert(image) { [weak self] frame in
            self?.queue.async { [weak self] in
                guard let self = self else { return }
                self.inFlight = false
                if !self.stopped, let frame = frame { self.sink.send(frame) }
            }
        }
    }
}

@MainActor
final class OverlayOutput {
    private var stream: SCStream?
    private var receiver: CaptureReceiver?
    private var runID: UUID?
    var onFailure: ((String) -> Void)?
    var isRunning: Bool { stream != nil && runID != nil }

    func start(window: NSWindow, sourceName: String) async throws {
        let runID = UUID()
        self.runID = runID
        let receiver = try await CaptureReceiver.make(width: 1920, height: 1080) { [weak self] text in
            Task { @MainActor in
                guard let self = self, self.runID == runID else { return }
                self.onFailure?(text)
                self.stop()
            }
        }
        guard self.runID == runID else { receiver.stop(); return }
        self.receiver = receiver
        do {
            // Binding failure is reported before requesting Screen Recording access.
            try await receiver.start(sourceName: sourceName)
            guard self.runID == runID else { receiver.stop(); return }
            // VERIFY-ON-MAC: confirm ScreenCaptureKit filter, configuration, async
            // signatures, window-ID mapping, permission UX and single-window alpha.
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard self.runID == runID else { receiver.stop(); return }
            guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                throw ViewOutputError.unavailable("Render window is not available to capture")
            }
            let filter = SCContentFilter(desktopIndependentWindow: target)
            let configuration = SCStreamConfiguration()
            configuration.width = 1920
            configuration.height = 1080
            // VERIFY-ON-MAC: sourceRect is in filter coordinates; confirm the
            // content crop excludes native title chrome at every backing scale.
            let contentRect = window.contentRect(forFrameRect: window.frame)
            configuration.sourceRect = CGRect(x: 0, y: window.frame.height - contentRect.height,
                                               width: contentRect.width, height: contentRect.height)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.queueDepth = 3
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.backgroundColor = NSColor.clear.cgColor
            let stream = SCStream(filter: filter, configuration: configuration, delegate: receiver)
            try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: receiver.queue)
            try await stream.startCapture()
            guard self.runID == runID else {
                try? await stream.stopCapture()
                receiver.stop()
                return
            }
            self.stream = stream
        } catch {
            receiver.stop()
            if self.runID == runID { self.receiver = nil; self.runID = nil }
            throw error
        }
    }

    func stop() {
        runID = nil
        receiver?.stop()
        receiver = nil
        let stream = stream
        self.stream = nil
        Task { try? await stream?.stopCapture() }
    }
}
