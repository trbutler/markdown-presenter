import CoreVideo
import Metal
import Foundation

/// Retains both input and output IOSurface-backed storage until the sink releases it.
struct GPUFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let texture: MTLTexture
    let textureReference: CVMetalTexture
    let sourceBuffer: CVPixelBuffer
    let sourceTextureReference: CVMetalTexture
}

/// Worker-queue owned. No CPU bitmap, pixel mapping or fallback conversion.
final class FrameConverter {
    private let device: MTLDevice
    private let commands: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let cache: CVMetalTextureCache
    private let pool: CVPixelBufferPool
    let width: Int
    let height: Int

    init(width: Int, height: Int) throws {
        self.width = width
        self.height = height
        guard let device = MTLCreateSystemDefaultDevice(), let commands = device.makeCommandQueue() else {
            throw ViewOutputError.unavailable("Metal is unavailable")
        }
        self.device = device
        self.commands = commands
        // VERIFY-ON-MAC: validate Metal BGRA texture access, shader alpha convention,
        // colour handling and GPU completion lifetimes on Apple Silicon/macOS 27.
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void convertFrame(texture2d<float, access::sample> input [[texture(0)]],
                                 texture2d<float, access::write> output [[texture(1)]],
                                 uint2 p [[thread_position_in_grid]]) {
            if (p.x >= output.get_width() || p.y >= output.get_height()) return;
            constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
            float2 uv = (float2(p) + 0.5) / float2(output.get_width(), output.get_height());
            float4 colour = input.sample(linearSampler, uv);
            colour.rgb = colour.a > 0.0 ? clamp(colour.rgb / colour.a, 0.0, 1.0) : float3(0.0);
            output.write(colour, p);
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "convertFrame") else {
            throw ViewOutputError.unavailable("Metal conversion function is unavailable")
        }
        pipeline = try device.makeComputePipelineState(function: function)
        // VERIFY-ON-MAC: confirm CoreVideo pool/cache imports, allocation threshold,
        // IOSurface backing and .bgra8Unorm shader-write support on the target SDK.
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess, let cache = cache else {
            throw ViewOutputError.unavailable("Cannot create Metal texture cache")
        }
        self.cache = cache
        let attributes: [CFString: Any] = [
            kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        var pool: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess, let pool = pool else {
            throw ViewOutputError.unavailable("Cannot create IOSurface pixel-buffer pool")
        }
        self.pool = pool
    }

    func convert(_ input: CVPixelBuffer, completion: @escaping @Sendable (GPUFrame?) -> Void) {
        guard CVPixelBufferGetIOSurface(input) != nil, CVPixelBufferGetPixelFormatType(input) == kCVPixelFormatType_32BGRA else {
            completion(nil)
            return
        }
        var output: CVPixelBuffer?
        let limits = [kCVPixelBufferPoolAllocationThresholdKey: 3] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, limits, &output) == kCVReturnSuccess,
              let output = output, CVPixelBufferGetIOSurface(output) != nil,
              let sourceReference = makeTexture(input, usage: .shaderRead), let sourceTexture = CVMetalTextureGetTexture(sourceReference),
              let targetReference = makeTexture(output, usage: .shaderWrite), let targetTexture = CVMetalTextureGetTexture(targetReference),
              let command = commands.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
            completion(nil)
            return
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setTexture(targetTexture, index: 1)
        let groupWidth = pipeline.threadExecutionWidth
        let groupHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / groupWidth)
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: groupWidth, height: groupHeight, depth: 1))
        encoder.endEncoding()
        let frame = GPUFrame(pixelBuffer: output, texture: targetTexture, textureReference: targetReference,
                             sourceBuffer: input, sourceTextureReference: sourceReference)
        command.addCompletedHandler { command in
            completion(command.status == .completed ? frame : nil)
        }
        command.commit()
    }

    private func makeTexture(_ buffer: CVPixelBuffer, usage: MTLTextureUsage) -> CVMetalTexture? {
        var texture: CVMetalTexture?
        let attributes = [kCVMetalTextureUsage: usage.rawValue] as CFDictionary
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, attributes, .bgra8Unorm,
                                                        CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer),
                                                        0, &texture) == kCVReturnSuccess else { return nil }
        return texture
    }
}
