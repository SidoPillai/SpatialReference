//
//  SplatViewer.swift
//  SpatialReference
//

import CompositorServices
import Foundation
import Metal
import OSLog
import os
import SwiftUI

/// The life-size splat space's state: which capture is loaded and how it's
/// shown. The toolbar window drives it; `SplatRenderer` reads a snapshot of
/// it each frame from its own thread.
@MainActor
@Observable
final class SplatViewer {

    /// Whether this device draws splats with `SplatRenderer`. The simulator
    /// keeps RealityKit's tabletop view instead.
    nonisolated static var isSupported: Bool {
        #if targetEnvironment(simulator)
        #if DEBUG
        UserDefaults.standard.bool(forKey: "SplatForceMetal")
        #else
        false
        #endif
        #else
        true
        #endif
    }

    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    /// What the render thread needs each frame.
    nonisolated struct RenderSettings: Sendable {
        var scene: SplatRenderer.Scene?
        var gain: Float = 1
        var yaw: Float = 0
        var flipped = false
        /// Bumped to put the capture camera back at the viewer's eyes.
        var placementGeneration = 0
    }

    private(set) var phase = Phase.idle
    /// Splats in the loaded capture.
    private(set) var splatCount = 0
    /// Whether the loaded file is a Gaussian splat capture rather than a
    /// plain point cloud.
    private(set) var isGaussianSplat = true
    /// The latest frame rate and frame times.
    private(set) var performance: String?
    /// Exposure in stops: 0 is as captured, +1 twice as bright.
    var exposure: Float = 0 { didSet { sync() } }
    /// Turns applied about the viewer, in radians.
    private(set) var yaw: Float = 0
    private(set) var isFlipped = false

    @ObservationIgnored private var placementGeneration = 0
    @ObservationIgnored private var scene: SplatRenderer.Scene?
    @ObservationIgnored private var loadedURL: URL?
    @ObservationIgnored private nonisolated let shared = OSAllocatedUnfairLock(initialState: RenderSettings())

    private static let log = Logger(subsystem: "com.esri.storymaps.SpatialReference", category: "SplatViewer")

    // MARK: - Space

    /// Starts drawing into a new splat space's layer. `onClose` runs once
    /// the system tears the layer down.
    func start(_ layerRenderer: LayerRenderer, onClose: @escaping @MainActor @Sendable () -> Void) {
        do {
            let renderer = try SplatRenderer(layerRenderer: layerRenderer, viewer: self, onClose: onClose)
            Task { await renderer.run() }
        } catch {
            Self.log.error("Couldn’t start the splat renderer: \(error, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Loading

    /// Loads a capture, unless it's already showing.
    func load(_ url: URL) async {
        if loadedURL == url, phase == .ready || phase == .loading { return }
        loadedURL = url
        scene = nil
        splatCount = 0
        performance = nil
        phase = .loading
        resetOrientation()
        sync()
        do {
            let start = ContinuousClock.now
            let loaded = try await Self.loadScene(url)
            guard loadedURL == url, !Task.isCancelled else { return }
            Self.log.info("Loaded \(loaded.count) splats in \(ContinuousClock.now - start)")
            scene = loaded
            splatCount = loaded.count
            isGaussianSplat = loaded.isGaussianSplat
            placementGeneration += 1
            phase = .ready
            sync()
        } catch {
            guard loadedURL == url else { return }
            Self.log.error("Couldn’t load splats: \(error, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Lets go of the capture once the space closes.
    func unload() {
        loadedURL = nil
        scene = nil
        splatCount = 0
        performance = nil
        phase = .idle
        exposure = 0
        resetOrientation()
        sync()
    }

    /// Parses and uploads off the main thread; captures run to hundreds of MB.
    @concurrent
    private nonisolated static func loadScene(_ url: URL) async throws -> SplatRenderer.Scene {
        guard let device = MTLCreateSystemDefaultDevice() else { throw SplatRendererError.metalUnavailable }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let cloud = try PLYPointCloud(data: data)
        return try SplatRenderer.makeScene(from: cloud, fileToCamera: PLYPointCloud.captureExtrinsic(in: data), device: device)
    }

    // MARK: - Toolbar actions

    /// Puts the capture camera back at the viewer's eyes, as first shown.
    func recenter() {
        resetOrientation()
        placementGeneration += 1
        sync()
    }

    /// Turns the capture an eighth of a turn to the right, about the viewer.
    func turn() {
        yaw -= .pi / 4
        sync()
    }

    func toggleFlip() {
        isFlipped.toggle()
        sync()
    }

    private func resetOrientation() {
        yaw = 0
        isFlipped = false
    }

    // MARK: - Render thread

    private func sync() {
        let settings = RenderSettings(scene: scene, gain: pow(2, exposure), yaw: yaw, flipped: isFlipped, placementGeneration: placementGeneration)
        shared.withLock { $0 = settings }
    }

    nonisolated func renderSettings() -> RenderSettings {
        shared.withLock { $0 }
    }

    nonisolated func publish(_ performance: String) {
        Task { @MainActor in self.performance = performance }
    }
}

/// A layered, foveated layer with sRGB color, for `SplatRenderer`.
struct SplatLayerConfiguration: CompositorLayerConfiguration {
    func makeConfiguration(capabilities: LayerRenderer.Capabilities, configuration: inout LayerRenderer.Configuration) {
        let foveation = capabilities.supportsFoveation
        configuration.isFoveationEnabled = foveation
        let layouts = capabilities.supportedLayouts(options: foveation ? [.foveationEnabled] : [])
        configuration.layout = layouts.contains(.layered) ? .layered : .dedicated
        if capabilities.supportedColorFormats(options: []).contains(.bgra8Unorm_srgb) {
            configuration.colorFormat = .bgra8Unorm_srgb
        }
        configuration.depthFormat = .depth32Float
        // Reverse-z: far, then near. Captures put splats right up to the camera.
        configuration.defaultDepthRange = [2_000, max(0.02, capabilities.supportedMinimumNearPlaneDistance)]
    }
}
