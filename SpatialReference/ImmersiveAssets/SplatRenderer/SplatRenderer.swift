//
//  SplatRenderer.swift
//  SpatialReference
//

import ARKit
import CompositorServices
import Metal
import OSLog
import QuartzCore
import simd

/// Draws a Gaussian splat capture life size into a CompositorServices layer,
/// with the capture's camera at the viewer's eyes.
///
/// Each frame, on the GPU: a depth key per splat from the centre eye (culling
/// what's behind or out of view), a 16-bit counting sort into back-to-front
/// order, then one instanced draw of screen-space ellipses into both eyes
/// at once with vertex amplification. See `SplatShaders.metal`.
///
/// Runs its own render thread; everything it shares with the UI goes
/// through `SplatViewer`.
nonisolated final class SplatRenderer: @unchecked Sendable {

    /// Mirrors `EyeUniforms` in `SplatShaders.metal`.
    struct EyeUniforms {
        var viewProjection = simd_float4x4()
        var modelView = simd_float4x4()
        var focal = SIMD2<Float>()
        var screenSize = SIMD2<Float>()
        var tanLimit = SIMD2<Float>()
        var padding = SIMD2<Float>()
    }

    /// Mirrors `FrameUniforms` in `SplatShaders.metal`.
    struct FrameUniforms {
        var eyes = (EyeUniforms(), EyeUniforms())
        var sortModelView = simd_float4x4()
        var gain: Float = 1
        var splatCount: UInt32 = 0
        var logNear: Float = 0
        var inverseLogRange: Float = 0
        var cullTangent: Float = 0
        var padding = SIMD3<Float>()
    }

    /// One capture's splats on the GPU, with room to sort them.
    final class Scene: @unchecked Sendable {
        let count: Int
        let isGaussianSplat: Bool
        /// From the file's coordinates to the capture camera's, y up and
        /// looking down -z.
        let cameraFromFile: simd_float4x4
        let splats: MTLBuffer
        let keys: MTLBuffer
        let order: MTLBuffer

        init(count: Int, isGaussianSplat: Bool, cameraFromFile: simd_float4x4, splats: MTLBuffer, keys: MTLBuffer, order: MTLBuffer) {
            self.count = count
            self.isGaussianSplat = isGaussianSplat
            self.cameraFromFile = cameraFromFile
            self.splats = splats
            self.keys = keys
            self.order = order
        }
    }

    private static let logger = Logger(subsystem: "com.esri.storymaps.SpatialReference", category: "SplatRenderer")
    private static let binCount = 65_536
    private static let maxFramesInFlight = 3
    /// The depth range the sort spreads its keys over, in metres.
    private static let sortRange: ClosedRange<Float> = 0.05...2_000

    let device: MTLDevice
    private let layerRenderer: LayerRenderer
    private let viewer: SplatViewer
    private let onClose: @MainActor @Sendable () -> Void
    private let queue: MTLCommandQueue
    private let keys: MTLComputePipelineState
    private let scan: MTLComputePipelineState
    private let scatter: MTLComputePipelineState
    private let draw: MTLRenderPipelineState
    /// Whether both eyes draw in one pass. The simulator draws one at a time.
    private let amplifies: Bool
    private let depthState: MTLDepthStencilState
    private let histogram: MTLBuffer
    private let drawArgs: MTLBuffer
    private let inFlight = DispatchSemaphore(value: maxFramesInFlight)

    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()

    private var scene: Scene?
    /// Where the capture camera goes: the viewer's eyes, level, facing
    /// where they faced when it was placed.
    private var eyeAnchor: simd_float4x4?
    private var placementGeneration = -1
    private let frameStats = FrameStats()

    init(layerRenderer: LayerRenderer, viewer: SplatViewer, onClose: @escaping @MainActor @Sendable () -> Void) throws {
        self.layerRenderer = layerRenderer
        self.viewer = viewer
        self.onClose = onClose
        let device = layerRenderer.device
        self.device = device
        guard let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let histogram = device.makeBuffer(length: Self.binCount * 4, options: .storageModePrivate),
              let drawArgs = device.makeBuffer(length: MemoryLayout<MTLDrawPrimitivesIndirectArguments>.stride, options: .storageModeShared) else {
            throw SplatRendererError.metalUnavailable
        }
        self.queue = queue
        self.histogram = histogram
        self.drawArgs = drawArgs
        func kernel(_ name: String) throws -> MTLComputePipelineState {
            guard let function = library.makeFunction(name: name) else { throw SplatRendererError.metalUnavailable }
            return try device.makeComputePipelineState(function: function)
        }
        keys = try kernel("splatKeys")
        scan = try kernel("splatScan")
        scatter = try kernel("splatScatter")
        let configuration = layerRenderer.configuration
        let pipeline = MTLRenderPipelineDescriptor()
        pipeline.label = "Splats"
        pipeline.vertexFunction = library.makeFunction(name: "splatVertex")
        pipeline.fragmentFunction = library.makeFunction(name: "splatFragment")
        pipeline.colorAttachments[0].pixelFormat = configuration.colorFormat
        pipeline.colorAttachments[0].isBlendingEnabled = true
        pipeline.colorAttachments[0].sourceRGBBlendFactor = .one
        pipeline.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipeline.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipeline.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline.depthAttachmentPixelFormat = configuration.depthFormat
        pipeline.inputPrimitiveTopology = .triangle
        amplifies = configuration.layout == .layered && device.supportsVertexAmplificationCount(2)
        pipeline.maxVertexAmplificationCount = amplifies ? 2 : 1
        draw = try device.makeRenderPipelineState(descriptor: pipeline)
        // Write each pixel's depth for the compositor, which uses it to
        // reproject frames. Splats draw back to front, so the nearest one at
        // a pixel wins.
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .always
        depth.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depth) else { throw SplatRendererError.metalUnavailable }
        self.depthState = depthState
    }

    // MARK: - Loading

    /// Uploads a capture and turns it into drawable splats on the GPU.
    /// `fileToCamera` is the capture camera's extrinsic stored in the file,
    /// if any (OpenCV convention: x right, y down, z forward).
    static func makeScene(from cloud: PLYPointCloud, fileToCamera: simd_float4x4? = nil, device: MTLDevice) throws -> Scene {
        guard let queue = device.makeCommandQueue(),
              let function = device.makeDefaultLibrary()?.makeFunction(name: "prepareSplats") else {
            throw SplatRendererError.metalUnavailable
        }
        let prepare = try device.makeComputePipelineState(function: function)
        let count = cloud.count
        guard count > 0 else { throw PLYPointCloud.ParseError.missingVertices }
        func upload(_ values: [Float]) throws -> MTLBuffer {
            let buffer = values.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: max($0.count, 16), options: .storageModeShared) }
            guard let buffer else { throw SplatRendererError.outOfMemory }
            return buffer
        }
        let inputs = try [cloud.positions, cloud.scales, cloud.rotations, cloud.opacities, cloud.colors].map(upload)
        guard let splats = device.makeBuffer(length: count * 40, options: .storageModePrivate),
              let keyBuffer = device.makeBuffer(length: count * 4, options: .storageModePrivate),
              let order = device.makeBuffer(length: count * 4, options: .storageModePrivate),
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeComputeCommandEncoder() else {
            throw SplatRendererError.outOfMemory
        }
        splats.label = "Splats"
        encoder.setComputePipelineState(prepare)
        for (index, buffer) in inputs.enumerated() { encoder.setBuffer(buffer, offset: 0, index: index) }
        encoder.setBuffer(splats, offset: 0, index: 5)
        var n = UInt32(count)
        encoder.setBytes(&n, length: 4, index: 6)
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        if let error = commands.error { throw error }
        let cameraFromFile: simd_float4x4
        if cloud.isGaussianSplat {
            // 3DGS captures use the COLMAP convention, y down and z forward,
            // with the capture camera at the origin unless the file says
            // otherwise: turn it half over. SHARP captures can store the
            // camera turned half round, putting everything behind it.
            cameraFromFile = simd_float4x4(simd_quatf(angle: .pi, axis: [1, 0, 0])) * (fileToCamera ?? matrix_identity_float4x4)
        } else {
            // A scan has no camera; stand it a little way ahead, centered at
            // eye height.
            var ahead = matrix_identity_float4x4
            ahead.columns.3 = SIMD4(-cloud.center.x, -cloud.center.y, -cloud.center.z - 1.2 - cloud.extents.z / 2, 1)
            cameraFromFile = ahead
        }
        return Scene(count: count, isGaussianSplat: cloud.isGaussianSplat, cameraFromFile: cameraFromFile, splats: splats, keys: keyBuffer, order: order)
    }

    // MARK: - Render loop

    /// Renders until the layer is invalidated, on the calling thread.
    func run() async {
        do {
            try await arSession.run([worldTracking])
        } catch {
            Self.logger.error("World tracking unavailable: \(error, privacy: .public)")
        }
        let thread = Thread { [self] in
            while true {
                switch layerRenderer.state {
                case .paused:
                    layerRenderer.waitUntilRunning()
                case .running:
                    autoreleasepool { renderFrame() }
                case .invalidated:
                    arSession.stop()
                    Task { @MainActor [onClose] in onClose() }
                    return
                @unknown default:
                    return
                }
            }
        }
        thread.name = "Splat render"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private func renderFrame() {
        guard let frame = layerRenderer.queryNextFrame() else { return }
        frame.startUpdate()
        let settings = viewer.renderSettings()
        if settings.scene !== scene {
            scene = settings.scene
            eyeAnchor = nil
        }
        frame.endUpdate()

        guard let timing = frame.predictTiming() else { return }
        LayerRenderer.Clock().wait(until: timing.optimalInputTime)
        inFlight.wait()
        frame.startSubmission()
        let cpuStart = CACurrentMediaTime()
        let drawables = frame.queryDrawables()
        guard !drawables.isEmpty else {
            // The frame was cancelled, as when the space pauses or closes;
            // it's invalid now, so it mustn't be ended either.
            inFlight.signal()
            return
        }
        let presentation = drawables[0].frameTiming.presentationTime
        let anchor = worldTracking.queryDeviceAnchor(atTimestamp: Self.seconds(LayerRenderer.Clock.Instant.epoch.duration(to: presentation)))
        let originFromDevice = anchor?.originFromAnchorTransform ?? matrix_identity_float4x4

        // Without world tracking (the simulator) the head stays at the origin.
        let tracked = anchor?.isTracked ?? !WorldTrackingProvider.isSupported
        if tracked, eyeAnchor == nil || placementGeneration != settings.placementGeneration {
            eyeAnchor = Self.levelAnchor(originFromDevice)
            placementGeneration = settings.placementGeneration
        }
        let placement = eyeAnchor.map { $0 * Self.orientation(yaw: settings.yaw, flipped: settings.flipped) * (scene?.cameraFromFile ?? matrix_identity_float4x4) }

        guard let commands = queue.makeCommandBuffer() else {
            inFlight.signal()
            frame.endSubmission()
            return
        }
        commands.addCompletedHandler { [inFlight, weak self] buffer in
            inFlight.signal()
            guard let self else { return }
            if buffer.status == .error || buffer.error != nil {
                frameStats.recordError(buffer.error.map { "\($0)" } ?? "status \(buffer.status.rawValue)")
            }
            // How many splats the sort found in view, for the stats.
            let visible = drawArgs.contents().load(as: MTLDrawPrimitivesIndirectArguments.self).instanceCount
            frameStats.recordGPU(buffer.gpuEndTime - buffer.gpuStartTime, visible: Int(visible))
        }
        for drawable in drawables {
            drawable.deviceAnchor = anchor
            encode(drawable, originFromDevice: originFromDevice, placement: placement, settings: settings, into: commands)
            drawable.encodePresent(commandBuffer: commands)
        }
        commands.commit()
        frame.endSubmission()
        frameStats.recordCPU(CACurrentMediaTime() - cpuStart, splats: scene?.count ?? 0)
        if let report = frameStats.reportIfDue() {
            Self.logger.info("\(report, privacy: .public)")
            #if DEBUG
            print("[splat]", report)
            #endif
            viewer.publish(report)
        }
    }

    private func encode(_ drawable: LayerRenderer.Drawable, originFromDevice: simd_float4x4, placement: simd_float4x4?, settings: SplatViewer.RenderSettings, into commands: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.colorTextures[0]
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.depthAttachment.texture = drawable.depthTextures[0]
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .store
        pass.depthAttachment.clearDepth = 0
        pass.rasterizationRateMap = drawable.rasterizationRateMaps.first
        let layered = layerRenderer.configuration.layout == .layered
        if layered { pass.renderTargetArrayLength = amplifies ? drawable.views.count : 1 }

        guard let scene, let placement else {
            // Nothing to show yet: just clear, so the room shows through.
            for view in amplifies ? Array(drawable.views.prefix(1)) : drawable.views {
                pass.colorAttachments[0].texture = drawable.colorTextures[view.textureMap.textureIndex]
                pass.depthAttachment.texture = drawable.depthTextures[view.textureMap.textureIndex]
                if !amplifies {
                    pass.colorAttachments[0].slice = view.textureMap.sliceIndex
                    pass.depthAttachment.slice = view.textureMap.sliceIndex
                }
                commands.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
            }
            return
        }

        var uniforms = FrameUniforms()
        let deviceFromOrigin = originFromDevice.inverse
        uniforms.sortModelView = deviceFromOrigin * placement
        uniforms.gain = settings.gain
        uniforms.splatCount = UInt32(scene.count)
        uniforms.logNear = log(Self.sortRange.lowerBound)
        uniforms.inverseLogRange = 1 / (log(Self.sortRange.upperBound) - log(Self.sortRange.lowerBound))
        var widest: Float = 0
        let rateMap = drawable.rasterizationRateMaps.first
        let eyeCount = min(drawable.views.count, 2)
        for index in 0..<eyeCount {
            let view = drawable.views[index]
            let viewFromScene = (originFromDevice * view.transform).inverse * placement
            let projection = drawable.computeProjection(convention: .rightUpBack, viewIndex: index)
            let viewport = view.textureMap.viewport
            var size = SIMD2(Float(viewport.width), Float(viewport.height))
            if let rateMap {
                let screen = rateMap.screenSize
                size = SIMD2(Float(screen.width), Float(screen.height))
            }
            // How far the view reaches off axis, as tangents, from where the
            // projection maps ±1.
            let reach = SIMD2((1 + abs(projection.columns.2.x)) / projection.columns.0.x,
                              (1 + abs(projection.columns.2.y)) / projection.columns.1.y)
            widest = max(widest, reach.max())
            var eye = EyeUniforms()
            eye.viewProjection = projection * viewFromScene
            eye.modelView = viewFromScene
            eye.focal = SIMD2(projection.columns.0.x, projection.columns.1.y) * size / 2
            eye.screenSize = size
            eye.tanLimit = reach
            if index == 0 { uniforms.eyes.0 = eye } else { uniforms.eyes.1 = eye }
        }
        if eyeCount == 1 { uniforms.eyes.1 = uniforms.eyes.0 }
        // Both eyes' views together, from the centre, with a margin for the
        // eyes' separation and splat size.
        uniforms.cullTangent = widest * 1.25 + 0.1

        // Sort.
        if let blit = commands.makeBlitCommandEncoder() {
            blit.fill(buffer: histogram, range: 0..<histogram.length, value: 0)
            blit.endEncoding()
        }
        guard let compute = commands.makeComputeCommandEncoder() else { return }
        let grid = MTLSize(width: scene.count, height: 1, depth: 1)
        let group = MTLSize(width: 256, height: 1, depth: 1)
        compute.setComputePipelineState(keys)
        compute.setBuffer(scene.splats, offset: 0, index: 0)
        compute.setBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        compute.setBuffer(scene.keys, offset: 0, index: 2)
        compute.setBuffer(histogram, offset: 0, index: 3)
        compute.dispatchThreads(grid, threadsPerThreadgroup: group)
        compute.memoryBarrier(scope: .buffers)
        compute.setComputePipelineState(scan)
        compute.setBuffer(histogram, offset: 0, index: 0)
        compute.setBuffer(drawArgs, offset: 0, index: 1)
        compute.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1024, height: 1, depth: 1))
        compute.memoryBarrier(scope: .buffers)
        compute.setComputePipelineState(scatter)
        compute.setBuffer(scene.keys, offset: 0, index: 0)
        compute.setBuffer(histogram, offset: 0, index: 1)
        compute.setBuffer(scene.order, offset: 0, index: 2)
        compute.setBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 3)
        compute.dispatchThreads(grid, threadsPerThreadgroup: group)
        compute.endEncoding()

        // Draw: both eyes in one pass into a layered drawable, otherwise
        // one pass per eye.
        if amplifies || drawable.views.count == 1 {
            drawSplats(scene, views: Array(drawable.views.indices), drawable: drawable, pass: pass, uniforms: uniforms, into: commands)
        } else {
            for index in drawable.views.indices {
                var single = uniforms
                single.eyes.0 = index == 0 ? uniforms.eyes.0 : uniforms.eyes.1
                let map = drawable.views[index].textureMap
                pass.colorAttachments[0].texture = drawable.colorTextures[map.textureIndex]
                pass.colorAttachments[0].slice = map.sliceIndex
                pass.depthAttachment.texture = drawable.depthTextures[map.textureIndex]
                pass.depthAttachment.slice = map.sliceIndex
                pass.rasterizationRateMap = layered ? nil : drawable.rasterizationRateMaps.indices.contains(index) ? drawable.rasterizationRateMaps[index] : nil
                drawSplats(scene, views: [index], drawable: drawable, pass: pass, uniforms: single, into: commands)
            }
        }
    }

    private func drawSplats(_ scene: Scene, views: [Int], drawable: LayerRenderer.Drawable, pass: MTLRenderPassDescriptor, uniforms: FrameUniforms, into commands: MTLCommandBuffer) {
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = uniforms
        encoder.setRenderPipelineState(draw)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        let viewports = views.map { drawable.views[$0].textureMap.viewport }
        encoder.setViewports(viewports)
        if viewports.count > 1 {
            var mappings = (0..<viewports.count).map {
                MTLVertexAmplificationViewMapping(viewportArrayIndexOffset: UInt32($0), renderTargetArrayIndexOffset: UInt32($0))
            }
            encoder.setVertexAmplificationCount(viewports.count, viewMappings: &mappings)
        }
        encoder.setVertexBuffer(scene.splats, offset: 0, index: 0)
        encoder.setVertexBuffer(scene.order, offset: 0, index: 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 2)
        encoder.drawPrimitives(type: .triangleStrip, indirectBuffer: drawArgs, indirectBufferOffset: 0)
        encoder.endEncoding()
    }

    // MARK: - Placement

    /// The eyes' pose, level (ignoring head tilt), facing where they face.
    private static func levelAnchor(_ originFromDevice: simd_float4x4) -> simd_float4x4 {
        let m = originFromDevice
        let forward = -SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        var anchor = simd_float4x4(simd_quatf(angle: atan2(-forward.x, -forward.z), axis: [0, 1, 0]))
        anchor.columns.3 = m.columns.3
        return anchor
    }

    /// Turns about the viewer, then upside down about where they look.
    private static func orientation(yaw: Float, flipped: Bool) -> simd_float4x4 {
        var rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        if flipped { rotation = rotation * simd_quatf(angle: .pi, axis: [0, 0, 1]) }
        return simd_float4x4(rotation)
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let (s, attoseconds) = duration.components
        return TimeInterval(s) + TimeInterval(attoseconds) * 1e-18
    }
}

enum SplatRendererError: LocalizedError {
    case metalUnavailable
    case outOfMemory

    var errorDescription: String? {
        switch self {
        case .metalUnavailable: "This device can’t draw splats."
        case .outOfMemory: "This capture is too big to show."
        }
    }
}

/// Frame times, logged and shown about every two seconds. GPU times come in
/// on Metal's completion thread.
nonisolated final class FrameStats: @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0
    private var cpu: Double = 0
    private var gpu: Double = 0
    private var gpuSamples = 0
    private var maxGPU: Double = 0
    private var splats = 0
    private var visible = 0
    private var errors = 0
    private var lastError = ""
    private var started = CACurrentMediaTime()

    func recordCPU(_ seconds: Double, splats: Int) {
        lock.withLock {
            frames += 1
            cpu += seconds
            self.splats = splats
        }
    }

    func recordError(_ description: String) {
        lock.withLock {
            errors += 1
            lastError = description
        }
    }

    func recordGPU(_ seconds: Double, visible: Int) {
        lock.withLock {
            self.visible = visible
            gpu += seconds
            gpuSamples += 1
            maxGPU = max(maxGPU, seconds)
        }
    }

    func reportIfDue() -> String? {
        lock.withLock {
            let now = CACurrentMediaTime()
            guard now - started >= 2, frames > 0 else { return nil }
            let fps = Double(frames) / (now - started)
            let failed = errors > 0 ? " · \(errors) GPU errors, last: \(lastError)" : ""
            let report = String(format: "%.0f fps · GPU %.1f ms avg, %.1f max · CPU %.2f ms · %d of %d splats in view",
                                fps, gpuSamples > 0 ? gpu / Double(gpuSamples) * 1000 : 0, maxGPU * 1000, cpu / Double(frames) * 1000, visible, splats) + failed
            frames = 0; cpu = 0; gpu = 0; gpuSamples = 0; maxGPU = 0; errors = 0
            started = now
            return report
        }
    }
}

extension PLYPointCloud {
    /// The capture camera's extrinsic (world to camera) from an `extrinsic`
    /// element of 16 row-major floats, as single-photo SHARP captures store.
    nonisolated static func captureExtrinsic(in data: Data) -> simd_float4x4? {
        guard let header = try? header(of: data), header.format == .binaryLittleEndian,
              let index = header.elements.firstIndex(where: { $0.name == "extrinsic" }) else { return nil }
        let element = header.elements[index]
        guard element.count == 16, element.properties.count == 1, element.properties[0].type == .float32 else { return nil }
        var offset = header.bodyOffset
        for before in header.elements[..<index] {
            guard !before.properties.contains(where: { $0.listCountType != nil }) else { return nil }
            offset += before.count * before.properties.reduce(0) { $0 + $1.type.size }
        }
        guard offset + 64 <= data.count else { return nil }
        let m = data.withUnsafeBytes { bytes in
            (0..<16).map { bytes.loadUnaligned(fromByteOffset: offset + $0 * 4, as: Float.self) }
        }
        guard m.allSatisfy(\.isFinite) else { return nil }
        return simd_float4x4(rows: [
            SIMD4(m[0], m[1], m[2], m[3]), SIMD4(m[4], m[5], m[6], m[7]),
            SIMD4(m[8], m[9], m[10], m[11]), SIMD4(m[12], m[13], m[14], m[15]),
        ])
    }
}
