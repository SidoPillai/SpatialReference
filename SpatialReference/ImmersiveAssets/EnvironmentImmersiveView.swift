//
//  EnvironmentImmersiveView.swift
//  SpatialReference
//

import CoreGraphics
import Foundation
import RealityKit
import SwiftUI

/// What the environment space is showing.
struct ActiveEnvironment {
    enum Content {
        case bundledPanorama(String)
        case panorama(URL)
        case model(URL, isRealityFile: Bool)
        /// A `.ply` Gaussian splat capture or point cloud.
        case pointCloud(URL)
    }

    let title: String
    let subtitle: String
    let content: Content

    var isModel: Bool {
        switch content {
        case .model, .pointCloud: true
        case .bundledPanorama, .panorama: false
        }
    }
}

/// The environment immersive space. A panorama is mapped onto the inside of
/// a huge sphere around the viewer (progressive immersion); a model stands
/// in the room (mixed immersion) and can be dragged to move it, pinched with
/// both hands to resize or turn it, and tapped to run any behaviors authored
/// into a `.reality` file. A small glass panel names it and leads out.
struct EnvironmentImmersiveView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var root = Entity()
    @State private var model: InteractiveModel?
    @State private var isLoading = false
    @State private var loadError: String?

    // Gesture start values, so each gesture applies relative to where it began.
    @State private var dragStart: SIMD3<Float>?
    @State private var scaleStart: Float?
    @State private var rotationStart: simd_quatf?

    /// Where a model first appears: centered at chest height, 1.4 m ahead.
    private static let modelHome: SIMD3<Float> = [0, 1.15, -1.4]
    /// A model's largest dimension when it first appears, in metres.
    private static let modelSize: Float = 0.8

    var body: some View {
        RealityView { content, attachments in
            content.add(root)
            if let panel = attachments.entity(for: "panel") {
                panel.position = [0, 0.62, -0.95]
                // Tip it back to face someone looking down at it.
                panel.orientation = simd_quatf(angle: -25 * .pi / 180, axis: [1, 0, 0])
                content.add(panel)
            }
        } attachments: {
            Attachment(id: "panel") { panel }
        }
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { model?.tap($0.entity) })
        .gesture(drag.simultaneously(with: magnify).simultaneously(with: rotate))
        .task(id: appModel.activeEnvironmentID) {
            await load()
        }
    }

    // MARK: - Loading

    private func load() async {
        root.children.removeAll()
        model = nil
        loadError = nil
        guard let env = appModel.activeEnvironment else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            switch env.content {
            case .bundledPanorama(let name):
                root.addChild(Self.skybox(try await Panorama.texture(named: name)))
            case .panorama(let url):
                root.addChild(Self.skybox(try await TextureResource(contentsOf: url)))
            case .model(let url, let isRealityFile):
                let entity = try await Entity(contentsOf: url)
                Self.addGroundingShadows(to: entity)
                let model = InteractiveModel(entity, isRealityFile: isRealityFile)
                root.addChild(model.pivot)
                self.model = model
                reset(animated: false)
            case .pointCloud(let url):
                let cloud = try await Self.readPointCloud(url)
                let extents = cloud.extents
                let model = InteractiveModel(
                    try await cloud.makeEntity(), isRealityFile: false,
                    bounds: BoundingBox(min: -extents / 2, max: extents / 2)
                )
                root.addChild(model.pivot)
                self.model = model
                reset(animated: false)
            }
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Parses off the main thread; splat captures run to hundreds of MB.
    @concurrent
    private nonisolated static func readPointCloud(_ url: URL) async throws -> PLYPointCloud {
        try PLYPointCloud(contentsOf: url)
    }

    private static func skybox(_ texture: TextureResource) -> Entity {
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        let sphere = ModelEntity(mesh: .generateSphere(radius: 1000), materials: [material])
        // Flip the sphere inside out so the panorama faces the viewer,
        // then turn it so the image's center column sits straight ahead.
        sphere.scale = [-1, 1, 1]
        sphere.orientation = simd_quatf(angle: Panorama.forwardYaw, axis: [0, 1, 0])
        return sphere
    }

    /// Grounds a model in the room with soft contact shadows.
    private static func addGroundingShadows(to entity: Entity) {
        if entity.components.has(ModelComponent.self) {
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        }
        for child in entity.children { addGroundingShadows(to: child) }
    }

    // MARK: - Model handling

    /// The model's starting scale: its largest side at `modelSize`.
    private var fittedScale: Float {
        guard let model, model.extent > 0 else { return 1 }
        return Self.modelSize / model.extent
    }

    private func reset(animated: Bool = true) {
        guard let pivot = model?.pivot else { return }
        let home = Transform(scale: .init(repeating: fittedScale), rotation: simd_quatf(angle: 0, axis: [0, 1, 0]), translation: Self.modelHome)
        if animated {
            pivot.move(to: home, relativeTo: root, duration: 0.4, timingFunction: .easeInOut)
        } else {
            pivot.transform = home
        }
    }

    private var drag: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                guard let pivot = model?.pivot else { return }
                let start = dragStart ?? pivot.position(relativeTo: root)
                dragStart = start
                pivot.setPosition(start + value.convert(value.translation3D, from: .local, to: root), relativeTo: root)
            }
            .onEnded { _ in dragStart = nil }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                guard let pivot = model?.pivot else { return }
                let start = scaleStart ?? pivot.scale.x
                scaleStart = start
                let scale = min(fittedScale * 10, max(fittedScale * 0.1, start * Float(value.magnification)))
                pivot.scale = .init(repeating: scale)
            }
            .onEnded { _ in scaleStart = nil }
    }

    private var rotate: some Gesture {
        RotateGesture3D(constrainedToAxis: .y)
            .targetedToAnyEntity()
            .onChanged { value in
                guard let pivot = model?.pivot else { return }
                let start = rotationStart ?? pivot.orientation
                rotationStart = start
                let q = value.rotation.quaternion
                let turn = simd_quatf(ix: Float(q.imag.x), iy: Float(q.imag.y), iz: Float(q.imag.z), r: Float(q.real))
                pivot.orientation = turn * start
            }
            .onEnded { _ in rotationStart = nil }
    }

    // MARK: - Panel

    @ViewBuilder
    private var panel: some View {
        if let env = appModel.activeEnvironment {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(env.title)
                            .font(.system(size: 20, weight: .bold))
                            .lineLimit(1)
                        Text(env.subtitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 24)
                    if model != nil {
                        panelButton("Reset", systemImage: "arrow.counterclockwise") { reset() }
                    }
                    panelButton("Exit", systemImage: "xmark") {
                        Task { await appModel.dismissOpenImmersiveSpace(using: dismissImmersiveSpace) }
                    }
                    .disabled(appModel.isImmersiveSpaceInTransition)
                    .accessibilityLabel("Exit \(env.title)")
                }
                if isLoading {
                    Label("Loading…", systemImage: "hourglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                } else if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(3)
                } else if model != nil {
                    Text("Drag to move · Pinch with both hands to resize or turn · Tap to interact")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.leading, 26)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
            .frame(width: 520)
            .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 32))
        }
    }

    private func panelButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(.white.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverEffect()
    }
}

/// Equirectangular (2:1) panoramas for environments. A panorama is a file
/// bundled under that name (heic, jpg or png); until one is, an environment
/// with a painted placeholder still opens with that.
enum Panorama {
    /// NASA's Apollo 11 Tranquility Base pan (jsc2007e045375, frames
    /// AS11-40-5881 to 5891, public domain) blended into the painted sky and
    /// ground, since the photo only spans about 28° around the horizon.
    nonisolated static let moon = "MoonPanorama"

    /// RealityKit's sphere puts the image's center column behind the viewer;
    /// a half turn brings it to straight ahead (-Z).
    static let forwardYaw: Float = .pi

    private nonisolated static let extensions = ["heic", "jpg", "png"]

    nonisolated static func bundledURL(named name: String, in bundle: Bundle = .main) -> URL? {
        extensions.lazy.compactMap { bundle.url(forResource: name, withExtension: $0) }.first
    }

    nonisolated static func hasPlaceholder(named name: String) -> Bool {
        name == moon
    }

    nonisolated static func hasContent(named name: String) -> Bool {
        bundledURL(named: name) != nil || hasPlaceholder(named: name)
    }

    static func texture(named name: String) async throws -> TextureResource {
        if let url = bundledURL(named: name) {
            return try await TextureResource(contentsOf: url)
        }
        guard hasPlaceholder(named: name), let image = await paintPlaceholder(named: name) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try await TextureResource(image: image, options: .init(semantic: .color))
    }

    /// Painting a 4K panorama takes a moment, so keep it off the main thread.
    @concurrent
    private nonisolated static func paintPlaceholder(named name: String) async -> sending CGImage? {
        name == moon ? LunarPanoramaPainter.paint() : nil
    }
}

/// Paints a stand-in lunar panorama: a starry black sky with Earth hanging
/// over the horizon, low hills, and a cratered gray plain. Seeded, so every
/// launch draws the same landscape.
nonisolated enum LunarPanoramaPainter {

    static func paint(width: Int = 4096) -> CGImage? {
        let height = width / 2
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        // Draw top-down: y = 0 is the zenith, height / 2 the horizon.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        var rng = SeededGenerator(seed: 0x4170_6F6C_6C6F_3131)   // "Apollo11"
        let canvas = Canvas(width: CGFloat(width), height: CGFloat(height))
        paintSky(ctx, canvas, &rng)
        paintEarth(ctx, canvas, &rng)
        paintGround(ctx, canvas)
        paintHills(ctx, canvas, &rng)
        paintCraters(ctx, canvas, &rng)
        paintPebbles(ctx, canvas, &rng)
        return ctx.makeImage()
    }

    private struct Canvas {
        let width: CGFloat
        let height: CGFloat
        var horizon: CGFloat { height / 2 }
        /// Pixels per radian, the same on both axes of an equirectangular image.
        var scale: CGFloat { width / (2 * .pi) }
        /// Row for an elevation in radians (negative is below the horizon).
        func y(elevation: CGFloat) -> CGFloat { horizon - elevation * scale }
    }

    private static func paintSky(_ ctx: CGContext, _ c: Canvas, _ rng: inout SeededGenerator) {
        ctx.setFillColor(CGColor(gray: 0.01, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: c.width, height: c.horizon))

        for _ in 0..<2600 {
            // Uniform over the hemisphere, not the image, so stars don't
            // bunch up at the stretched-out zenith.
            let elevation = asin(CGFloat.random(in: 0.02..<1, using: &rng))
            let x = CGFloat.random(in: 0..<c.width, using: &rng)
            let y = c.y(elevation: elevation)
            let r = CGFloat.random(in: 0..<1, using: &rng) < 0.04 ? 1.8 : CGFloat.random(in: 0.5...1.1, using: &rng)
            let stretch = 1 / max(cos(elevation), 0.15)
            ctx.setFillColor(CGColor(gray: 1, alpha: .random(in: 0.3...1, using: &rng)))
            ctx.fillEllipse(in: CGRect(x: x - r * stretch, y: y - r, width: 2 * r * stretch, height: 2 * r))
        }
    }

    private static func paintEarth(_ ctx: CGContext, _ c: Canvas, _ rng: inout SeededGenerator) {
        let center = CGPoint(x: c.width / 2, y: c.y(elevation: 24 * .pi / 180))
        let r = 2.2 * .pi / 180 * c.scale
        let disc = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)

        // Faint atmosphere.
        ctx.setFillColor(CGColor(red: 0.45, green: 0.65, blue: 1, alpha: 0.18))
        ctx.fillEllipse(in: disc.insetBy(dx: -r * 0.12, dy: -r * 0.12))

        ctx.saveGState()
        ctx.addEllipse(in: disc)
        ctx.clip()
        ctx.setFillColor(CGColor(red: 0.12, green: 0.32, blue: 0.68, alpha: 1))
        ctx.fill(disc)
        // Continents and cloud bands.
        for _ in 0..<5 {
            let w = r * .random(in: 0.4...0.9, using: &rng), h = r * .random(in: 0.25...0.5, using: &rng)
            ctx.setFillColor(CGColor(red: 0.42, green: 0.48, blue: 0.3, alpha: 0.9))
            ctx.fillEllipse(in: CGRect(x: center.x + r * .random(in: -0.9...0.4, using: &rng), y: center.y + r * .random(in: -0.8...0.5, using: &rng), width: w, height: h))
        }
        for _ in 0..<9 {
            let w = r * .random(in: 0.5...1.2, using: &rng), h = r * .random(in: 0.08...0.2, using: &rng)
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.75))
            ctx.fillEllipse(in: CGRect(x: center.x + r * .random(in: -1.2...0.4, using: &rng), y: center.y + r * .random(in: -1...0.9, using: &rng), width: w, height: h))
        }
        // Night side, leaving a waxing gibbous Earth.
        ctx.setFillColor(CGColor(gray: 0.01, alpha: 0.92))
        ctx.fillEllipse(in: disc.offsetBy(dx: -r * 1.35, dy: 0).insetBy(dx: -r * 0.1, dy: -r * 0.1))
        ctx.restoreGState()
    }

    private static func paintGround(_ ctx: CGContext, _ c: Canvas) {
        let colors = [
            CGColor(red: 0.40, green: 0.39, blue: 0.37, alpha: 1),
            CGColor(red: 0.58, green: 0.57, blue: 0.54, alpha: 1),
            CGColor(red: 0.64, green: 0.63, blue: 0.60, alpha: 1),
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: c.horizon, width: c.width, height: c.horizon))
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: c.horizon), end: CGPoint(x: 0, y: c.height), options: [])
        ctx.restoreGState()
    }

    /// Low ridges on the horizon. Built from whole-number sine frequencies
    /// so the silhouette wraps seamlessly where the image's edges meet.
    private static func paintHills(_ ctx: CGContext, _ c: Canvas, _ rng: inout SeededGenerator) {
        let waves: [(frequency: CGFloat, amplitude: CGFloat, phase: CGFloat)] = [(2, 0.5), (5, 0.35), (11, 0.2), (23, 0.1)].map {
            ($0.0, $0.1, .random(in: 0..<(2 * .pi), using: &rng))
        }
        let peak = 1.1 * .pi / 180 * c.scale
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: c.horizon + 2))
        for x in stride(from: CGFloat(0), through: c.width, by: 4) {
            let t = x / c.width * 2 * .pi
            let h = waves.reduce(0) { $0 + $1.amplitude * (1 + sin($1.frequency * t + $1.phase)) / 2 }
            path.addLine(to: CGPoint(x: x, y: c.horizon - h * peak))
        }
        path.addLine(to: CGPoint(x: c.width, y: c.horizon + 2))
        path.closeSubpath()
        ctx.setFillColor(CGColor(red: 0.33, green: 0.32, blue: 0.31, alpha: 1))
        ctx.addPath(path)
        ctx.fillPath()
    }

    /// Craters sized for a 1.6 m eye height: farther ones are smaller and
    /// flattened toward the horizon. Sunlight comes from the left.
    private static func paintCraters(_ ctx: CGContext, _ c: Canvas, _ rng: inout SeededGenerator) {
        let eye: CGFloat = 1.6
        for _ in 0..<140 {
            let depression = pow(CGFloat.random(in: 0.02..<1, using: &rng), 1.8) * 75 * .pi / 180
            let radius = pow(CGFloat.random(in: 0..<1, using: &rng), 3) * 4 + 0.1   // meters
            let distance = eye / tan(depression)
            let rx = min(radius / distance * c.scale, c.width * 0.012)
            let ry = rx * sin(depression)
            guard ry > 0.6 else { continue }
            let x = CGFloat.random(in: 0..<c.width, using: &rng)
            let y = c.y(elevation: -depression)
            let bowl = CGRect(x: x - rx, y: y - ry, width: 2 * rx, height: 2 * ry)
            // Lit rim, shadowed bowl, then the sunlit far wall.
            ctx.setFillColor(CGColor(gray: 0.85, alpha: 0.12))
            ctx.fillEllipse(in: bowl.insetBy(dx: -rx * 0.12, dy: -ry * 0.12))
            ctx.setFillColor(CGColor(gray: 0.08, alpha: 0.38))
            ctx.fillEllipse(in: bowl)
            ctx.setFillColor(CGColor(red: 0.6, green: 0.59, blue: 0.56, alpha: 0.55))
            ctx.fillEllipse(in: bowl.offsetBy(dx: rx * 0.3, dy: 0).insetBy(dx: rx * 0.15, dy: ry * 0.12))
        }
    }

    /// Scattered rocks, mostly close by where they're big enough to see.
    private static func paintPebbles(_ ctx: CGContext, _ c: Canvas, _ rng: inout SeededGenerator) {
        for _ in 0..<900 {
            let depression = CGFloat.random(in: 0.08...1.35, using: &rng)
            let size = CGFloat.random(in: 0.01...0.04, using: &rng) * sin(depression) / 1.6 * c.scale
            guard size * sin(depression) > 0.6 else { continue }
            let x = CGFloat.random(in: 0..<c.width, using: &rng)
            let y = c.y(elevation: -depression)
            let gray = CGFloat.random(in: 0..<1, using: &rng) < 0.5 ? 0.2 : 0.8
            ctx.setFillColor(CGColor(gray: gray, alpha: 0.25))
            ctx.fillEllipse(in: CGRect(x: x - size, y: y - size * sin(depression), width: 2 * size, height: 2 * size * sin(depression)))
        }
    }
}

/// SplitMix64, so the painted placeholder looks the same every launch.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE5_E9B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

#Preview(immersionStyle: .progressive) {
    let model = AppModel()
    model.activeEnvironmentID = "The Moon"
    return EnvironmentImmersiveView()
        .environment(model)
}
