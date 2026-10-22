import AppKit
import Accelerate
import WebKit
import PresenterCore

/// Renders the deck as `?view=overlay` in its own transparent window and feeds
/// snapshots to a `FrameSink` (NDI when the binding exists, else the stub).
///
/// Capture path (prototype): timer -> WKWebView.takeSnapshot -> CGImage ->
/// BGRA bytes at the output size -> sink. See the design doc for the
/// ScreenCaptureKit alternative if snapshots prove too slow.
@MainActor
final class OverlayOutput {
    let outputWidth: Int
    let outputHeight: Int
    let framesPerSecond: Double
    let sourceName: String

    private let page: DeckPage
    private let window: NSWindow
    private let sink: FrameSink
    private var timer: Timer?
    private var captureInFlight: UUID?
    private var runID: UUID?
    private(set) var droppedTicks = 0

    init(deckURL: URL, controller: DeckController, sink: FrameSink, width: Int = 1920, height: Int = 1080, framesPerSecond: Double = 30, sourceName: String = "markdown-presenter overlay") {
        outputWidth = width
        outputHeight = height
        self.framesPerSecond = framesPerSecond
        self.sourceName = sourceName
        self.sink = sink
        page = DeckPage(role: .overlay, deckURL: deckURL, controller: controller)

        // A visible, transparent preview window: the desktop shows through
        // wherever the overlay is clear. Kept on screen because WebKit may
        // throttle painting in fully hidden or occluded windows.
        window = PresenterWindow(contentRect: NSRect(x: 80, y: 80, width: 480, height: 270), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.title = ViewRole.overlay.title + " preview"
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentAspectRatio = NSSize(width: width, height: height)
        window.contentView = OverlayPreviewView(contentView: page.presentationView, renderSize: NSSize(width: width, height: height))
    }

    var sinkName: String { sink.displayName }

    func start() throws {
        guard runID == nil else {
            return
        }
        try sink.start(sourceName: sourceName, width: outputWidth, height: outputHeight, framesPerSecond: framesPerSecond)
        runID = UUID()
        window.orderFront(nil)
        let timer = Timer(timeInterval: 1 / framesPerSecond, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        // .common keeps frames flowing while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func reload() {
        page.reload()
    }

    func stop() {
        runID = nil
        captureInFlight = nil
        timer?.invalidate()
        timer = nil
        sink.stop()
        window.orderOut(nil)
    }

    private func tick() {
        guard let runID = runID else {
            return
        }
        guard !page.isRestoring else {
            sendTransparentFrame()
            return
        }
        let restorationID = page.restorationID
        // Never queue snapshots: if the last one has not returned, drop this
        // tick. Latency stays bounded at about one frame plus snapshot time.
        guard captureInFlight != restorationID else {
            droppedTicks += 1
            return
        }
        captureInFlight = restorationID
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = false
        config.rect = page.webView.bounds
        config.snapshotWidth = NSNumber(value: outputWidth)
        // VERIFY-ON-MAC: check snapshot callback/NSImage isolation with Swift 5.9 strict checking.
        page.webView.takeSnapshot(with: config) { [weak self] image, error in
            let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            Task { @MainActor in
                self?.deliver(cgImage, error: error, runID: runID, restorationID: restorationID)
            }
        }
    }

    private func sendTransparentFrame() {
        sink.send(VideoFrame(width: outputWidth, height: outputHeight, bytesPerRow: outputWidth * 4,
                             format: sink.preferredFormat, timestamp: Date().timeIntervalSince1970,
                             pixels: Data(count: outputWidth * outputHeight * 4)))
    }

    private func deliver(_ image: CGImage?, error: Error?, runID: UUID, restorationID: UUID) {
        guard self.runID == runID else {
            return
        }
        if captureInFlight == restorationID {
            captureInFlight = nil
        }
        guard page.restorationID == restorationID, !page.isRestoring else {
            // An old callback must not overwrite a frame from a restored page.
            return
        }
        guard let image = image else {
            if let error = error {
                NSLog("[OverlayOutput] snapshot failed: %@", String(describing: error))
            }
            return
        }
        if let frame = FrameConverter.bgra(from: image, width: outputWidth, height: outputHeight, format: sink.preferredFormat) {
            sink.send(frame)
        }
    }
}

/// Scale the full output viewport into the preview without relaying its size to WebKit.
@MainActor
private final class OverlayPreviewView: NSView {
    private let renderSize: NSSize

    init(contentView: NSView, renderSize: NSSize) {
        self.renderSize = renderSize
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 270))
        // VERIFY-ON-MAC: confirm WKWebView layout/snapshot use these logical bounds
        // under an NSView bounds transform, including preview resizing and Retina.
        setBoundsSize(renderSize)
        contentView.autoresizingMask = []
        contentView.frame = NSRect(origin: .zero, size: renderSize)
        addSubview(contentView)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        setBoundsSize(renderSize)
    }
}

enum FrameConverter {
    /// Draws `image` scaled to width x height into BGRA memory. CGBitmapContext
    /// only produces premultiplied alpha; straight alpha is derived with vImage.
    static func bgra(from image: CGImage, width: Int, height: Int, format: PixelFormat) -> VideoFrame? {
        let bytesPerRow = width * 4
        var pixels = Data(count: bytesPerRow * height)
        let drawn = pixels.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress,
                  let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
                return false
            }
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            context.clear(rect)
            context.interpolationQuality = .high
            context.draw(image, in: rect)
            if format == .bgra8Straight {
                // In place: source and destination describe the same memory.
                var source = vImage_Buffer(data: base, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
                var destination = source
                // Alpha is last in both RGBA and BGRA; all colour channels divide alike.
                // VERIFY-ON-MAC: confirm the RGBA8888 declaration and in-place conversion.
                let error = vImageUnpremultiplyData_RGBA8888(&source, &destination, vImage_Flags(kvImageNoFlags))
                guard error == kvImageNoError else {
                    return false
                }
            }
            return true
        }
        guard drawn else {
            return nil
        }
        return VideoFrame(width: width, height: height, bytesPerRow: bytesPerRow, format: format, timestamp: Date().timeIntervalSince1970, pixels: pixels)
    }
}
