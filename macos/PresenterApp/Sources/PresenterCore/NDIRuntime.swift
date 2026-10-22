import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// NDI(R) is a registered trademark of Vizrt NDI AB. https://ndi.video
//
// Nothing from the NDI SDK is vendored in this repository. The NDI runtime
// (libndi.dylib) is installed by the user from https://ndi.video (NDI Tools /
// NDI runtime) and is opened at run time with dlopen. See
// docs/1214-macos-app-design.md, "NDI licensing".

public enum NDIRuntimeError: Error, CustomStringConvertible {
    case runtimeNotFound(searched: [String])
    case entryPointMissing(path: String)
    case bindingNotImplemented

    public var description: String {
        switch self {
        case .runtimeNotFound(let searched):
            return "NDI runtime not found (looked in: \(searched.joined(separator: ", "))). Install it from https://ndi.video"
        case .entryPointMissing(let path):
            return "\(path) has no NDIlib_v5_load symbol"
        case .bindingNotImplemented:
            return "NDI send binding not written yet (needs the NDI SDK headers; see NDIFrameSink)"
        }
    }
}

/// A dlopen'ed NDI runtime. Owning this does not start NDI.
public final class NDIRuntime {
    public let path: String
    /// Address of `NDIlib_v5_load`, which returns `const NDIlib_v5*`, a table of
    /// C function pointers declared in the SDK's Processing.NDI.DynamicLoad.h.
    /// The NDI v6 runtime still exports this entry point.
    public let loadEntryPoint: UnsafeMutableRawPointer
    private let handle: UnsafeMutableRawPointer

    private init(path: String, handle: UnsafeMutableRawPointer, loadEntryPoint: UnsafeMutableRawPointer) {
        self.path = path
        self.handle = handle
        self.loadEntryPoint = loadEntryPoint
    }

    /// Where to look, in order. The runtime-dir variables are the SDK's own
    /// redistributable convention; /usr/local/lib is where the macOS NDI
    /// runtime installer puts libndi.dylib.
    public static func candidatePaths(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        #if os(macOS)
        let libraryName = "libndi.dylib"
        var paths: [String] = []
        for key in ["NDI_RUNTIME_DIR_V6", "NDI_RUNTIME_DIR_V5"] {
            if let dir = environment[key], !dir.isEmpty {
                paths.append((dir as NSString).appendingPathComponent(libraryName))
            }
        }
        paths.append("/usr/local/lib/" + libraryName)
        paths.append("/Library/NDI SDK for Apple/lib/macOS/" + libraryName)
        return paths
        #else
        return ["libndi.so.6", "libndi.so.5"]
        #endif
    }

    public static func load(searching paths: [String] = NDIRuntime.candidatePaths()) throws -> NDIRuntime {
        for path in paths {
            guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
                continue
            }
            guard let entry = dlsym(handle, "NDIlib_v5_load") else {
                dlclose(handle)
                throw NDIRuntimeError.entryPointMissing(path: path)
            }
            return NDIRuntime(path: path, handle: handle, loadEntryPoint: entry)
        }
        throw NDIRuntimeError.runtimeNotFound(searched: paths)
    }

    deinit {
        dlclose(handle)
    }
}

/// NDI sender for overlay frames.
///
/// ===================== NDI SDK PLUG-IN POINT =====================
/// This is the only place NDI code goes. To finish it (phase 3 of the plan):
///  1. Add the SDK's MIT-licensed header Processing.NDI.DynamicLoad.h (and the
///     headers it includes) as a small C target, e.g. `CNDI`, with a module map.
///     Do not add libndi itself; it stays a user-installed runtime.
///  2. Cast `runtime.loadEntryPoint` to `@convention(c) () -> UnsafePointer<NDIlib_v5>?`
///     and call it to get the function table.
///  3. start(): table.initialize(); create an `NDIlib_send_create_t` with
///     p_ndi_name = sourceName, clock_video = false (we pace frames ourselves),
///     then table.send_create(&settings).
///  4. send(): fill `NDIlib_video_frame_v2_t` with xres/yres, FourCC BGRA,
///     frame_rate_N/D, frame_format_type progressive, line_stride_in_bytes =
///     frame.bytesPerRow, p_data = frame.pixels, timecode synthesized; call
///     table.send_send_video_v2 (synchronous copy) or send_send_video_async_v2
///     (zero copy: keep the buffer alive until the next call).
///  5. stop(): send_destroy, then destroy().
///  6. Settle premultiplied vs straight alpha against the SDK docs for BGRA
///     and set `preferredFormat`; the capture side converts either way.
/// ==================================================================
public final class NDIFrameSink: FrameSink {
    /// Flip to true once steps 1-6 above are done.
    public static let bindingImplemented = false

    public let displayName = "NDI"
    public let preferredFormat = PixelFormat.bgra8Straight
    public let runtime: NDIRuntime

    public init(runtime: NDIRuntime) {
        self.runtime = runtime
    }

    public func start(sourceName: String, width: Int, height: Int, framesPerSecond: Double) throws {
        throw NDIRuntimeError.bindingNotImplemented
    }

    public func send(_ frame: VideoFrame) {
    }

    public func stop() {
    }
}
