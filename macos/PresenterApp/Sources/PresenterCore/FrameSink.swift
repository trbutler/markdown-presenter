/// A frame sink is independent of a window or preset kind. Native GPU frames
/// live in PresenterApp so PresenterCore stays free of Apple rendering frameworks.
public protocol FrameSink: AnyObject {
    associatedtype Frame
    var displayName: String { get }
    func start(sourceName: String, width: Int, height: Int, framesPerSecond: Double) throws
    /// The sink must retain storage until its asynchronous consumer releases it.
    func send(_ frame: Frame)
    func stop()
}
