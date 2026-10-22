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
    case noUsableRuntime(searched: [String], missingEntryPoints: [String])
    case bindingNotImplemented

    public var description: String {
        switch self {
        case .runtimeNotFound(let searched):
            return "NDI runtime not found (looked in: \(searched.joined(separator: ", "))). Install it from https://ndi.video"
        case .entryPointMissing(let path):
            return "\(path) has no NDIlib_v5_load symbol"
        case .noUsableRuntime(let searched, let missing):
            return "No usable NDI runtime (looked in: \(searched.joined(separator: ", "))); NDIlib_v5_load missing in: \(missing.joined(separator: ", "))"
        case .bindingNotImplemented:
            return "NDI send binding not written yet (needs verified NDI SDK headers and a GPUFrame adapter)"
        }
    }
}

/// A dlopen'ed NDI runtime. Owning this does not start NDI.
public final class NDIRuntime {
    public let path: String
    /// Address of `NDIlib_v5_load`, which returns `const NDIlib_v5*`, a table of
    /// C function pointers declared in the SDK's Processing.NDI.DynamicLoad.h.
    /// VERIFY-ON-MAC/SDK: confirm this entry point in the installed NDI runtime.
    public let loadEntryPoint: UnsafeMutableRawPointer
    private let handle: UnsafeMutableRawPointer
    private let closeHandle: (UnsafeMutableRawPointer) -> Void

    private init(path: String, handle: UnsafeMutableRawPointer, loadEntryPoint: UnsafeMutableRawPointer, closeHandle: @escaping (UnsafeMutableRawPointer) -> Void) {
        self.path = path
        self.handle = handle
        self.loadEntryPoint = loadEntryPoint
        self.closeHandle = closeHandle
    }

    /// Where to look, in order. The runtime-dir variables are the SDK's own
    /// redistributable convention. VERIFY-ON-MAC/SDK: confirm these environment
    /// keys, installer paths and ABI against the actual installed runtime.
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
        try load(searching: paths, openLibrary: { dlopen($0, RTLD_NOW | RTLD_LOCAL) },
                 findEntry: { dlsym($0, "NDIlib_v5_load") }, closeLibrary: { _ = dlclose($0) })
    }

    // Inject the loader operations so candidate fallback and ownership can be
    // checked without installing or opening an NDI runtime.
    static func load(searching paths: [String], openLibrary: (String) -> UnsafeMutableRawPointer?,
                     findEntry: (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?,
                     closeLibrary: @escaping (UnsafeMutableRawPointer) -> Void) throws -> NDIRuntime {
        var missingEntryPoints: [String] = []
        for path in paths {
            guard let handle = openLibrary(path) else {
                continue
            }
            guard let entry = findEntry(handle) else {
                closeLibrary(handle)
                missingEntryPoints.append(path)
                continue
            }
            return NDIRuntime(path: path, handle: handle, loadEntryPoint: entry, closeHandle: closeLibrary)
        }
        if !missingEntryPoints.isEmpty {
            throw NDIRuntimeError.noUsableRuntime(searched: paths, missingEntryPoints: missingEntryPoints)
        }
        throw NDIRuntimeError.runtimeNotFound(searched: paths)
    }

    deinit {
        closeHandle(handle)
    }
}

// The GPUFrame sender adapter now lives in PresenterApp/OverlayOutput.swift.
// No SDK table layout or CPU pixel-buffer binding is guessed in PresenterCore.
