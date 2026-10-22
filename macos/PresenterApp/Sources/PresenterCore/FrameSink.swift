import Foundation

public enum PixelFormat: Sendable {
    /// 8-bit B,G,R,A in memory, colour premultiplied by alpha (what CGContext produces).
    case bgra8Premultiplied
    /// 8-bit B,G,R,A in memory, straight (non-premultiplied) alpha.
    case bgra8Straight
}

/// One captured video frame of the overlay view.
public struct VideoFrame: Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let format: PixelFormat
    /// Capture time, seconds since 1970.
    public let timestamp: Double
    public let pixels: Data

    public init(width: Int, height: Int, bytesPerRow: Int, format: PixelFormat, timestamp: Double, pixels: Data) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.format = format
        self.timestamp = timestamp
        self.pixels = pixels
    }
}

/// Where overlay frames go. The capture loop does not know about NDI; a sink
/// can be NDI, a recorder, or the stub below.
public protocol FrameSink: AnyObject {
    /// Human-readable sink name for menus and logs.
    var displayName: String { get }
    /// The pixel format this sink wants; the capture side converts to it.
    var preferredFormat: PixelFormat { get }
    func start(sourceName: String, width: Int, height: Int, framesPerSecond: Double) throws
    func send(_ frame: VideoFrame)
    func stop()
}

/// Accepts frames and only counts them. Used until the NDI binding exists,
/// and to measure capture cost on its own.
public final class StubFrameSink: FrameSink {
    public let displayName = "Stub (no NDI)"
    public let preferredFormat = PixelFormat.bgra8Premultiplied
    public private(set) var framesReceived = 0
    public private(set) var lastFrameOpaquePixels = 0
    public private(set) var lastFrameTransparentPixels = 0
    private let log: (String) -> Void
    private var startedAt = Date()

    public init(log: @escaping (String) -> Void = { print($0) }) {
        self.log = log
    }

    public func start(sourceName: String, width: Int, height: Int, framesPerSecond: Double) throws {
        framesReceived = 0
        startedAt = Date()
        log("[StubFrameSink] start '\(sourceName)' \(width)x\(height) @ \(framesPerSecond) fps (frames are discarded)")
    }

    public func send(_ frame: VideoFrame) {
        framesReceived += 1
        // Every 5 s, log the achieved rate and an alpha sanity check so a
        // tester can confirm the overlay really carries transparency.
        if framesReceived % 150 == 1 {
            countAlpha(frame)
            let elapsed = max(Date().timeIntervalSince(startedAt), 0.001)
            log(String(format: "[StubFrameSink] %ld frames, %.1f fps, last frame %ldx%ld: %ld opaque / %ld transparent pixels",
                       framesReceived, Double(framesReceived) / elapsed, frame.width, frame.height,
                       lastFrameOpaquePixels, lastFrameTransparentPixels))
        }
    }

    public func stop() {
        log("[StubFrameSink] stop after \(framesReceived) frames")
    }

    private func countAlpha(_ frame: VideoFrame) {
        var opaque = 0
        var clear = 0
        frame.pixels.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for y in 0..<frame.height {
                let row = y * frame.bytesPerRow
                for x in 0..<frame.width {
                    let alpha = bytes[row + x * 4 + 3]
                    if alpha == 255 {
                        opaque += 1
                    } else if alpha == 0 {
                        clear += 1
                    }
                }
            }
        }
        lastFrameOpaquePixels = opaque
        lastFrameTransparentPixels = clear
    }
}
