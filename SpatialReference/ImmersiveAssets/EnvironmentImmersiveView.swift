//
//  EnvironmentImmersiveView.swift
//  SpatialReference
//

import ARKit
import CoreGraphics
import Foundation
import ImageIO
import OSLog
import QuartzCore
import RealityKit
import SwiftUI

/// What the environment space is showing.
struct ActiveEnvironment {
    enum Content {
        case bundledPanorama(String)
        case panorama(URL)
        /// A story's 360° image, downloaded from the story item on demand.
        case storyPanorama(itemID: String, Image360)
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
        case .bundledPanorama, .panorama, .storyPanorama: false
        }
    }
}

/// The environment immersive space. A panorama is mapped onto the inside of
/// a huge sphere around the viewer (progressive immersion); a model, splat
/// capture or point cloud stands in the room (mixed immersion) and can be
/// dragged to move it, pinched with both hands to resize or turn it, and
/// tapped to run any behaviors authored into a `.reality` file.
///
/// A floating toolbar below eye level leads out, steps to the previous or
/// next environment, resets, turns, adjusts exposure, flips upside down, sets
/// the background music, and shows details.
struct EnvironmentImmersiveView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    @State private var root = Entity()
    /// Holds the toolbar; placed in front of the viewer when content loads.
    @State private var toolbarAnchor = Entity()
    @State private var model: InteractiveModel?
    /// The panorama sphere, turned and flipped in place.
    @State private var skybox: ModelEntity?
    @State private var isLoading = false
    @State private var loadError: String?
    /// Set when a capture shows fewer splats than it has.
    @State private var renderingNote: String?
    /// Splats kept / in the file, for the info card.
    @State private var splatCounts: (shown: Int, total: Int)?

    @State private var openCard: ToolbarCard?
    /// Exposure in stops: 0 is as captured, +1 twice as bright.
    @State private var exposure: Float = 0
    @State private var isFlipped = false
    /// Turns applied to a panorama, in radians.
    @State private var skyboxYaw: Float = 0
    #if !targetEnvironment(simulator)
    @State private var splatExposure: PLYPointCloud.SplatExposure?
    #endif
    /// Flat lighting a model is lit by while its exposure is changed.
    @State private var neutralLight: EnvironmentResource?

    // Gesture start values, so each gesture applies relative to where it began.
    @State private var dragStart: SIMD3<Float>?
    @State private var scaleStart: Float?
    @State private var rotationStart: simd_quatf?

    enum ToolbarCard { case exposure, music, info }

    /// Where a model first appears: centered at chest height, 1.4 m ahead.
    private static let modelHome: SIMD3<Float> = [0, 1.15, -1.4]
    /// A model's largest dimension when it first appears, in metres.
    private static let modelSize: Float = 0.8
    /// A splat renderer budget: above roughly this many splats, visionOS
    /// reports rendering as limited and draws nothing.
    private static let splatBudget = 200_000

    private static let log = Logger(subsystem: "com.esri.storymaps.SpatialReference", category: "Environments")

    var body: some View {
        RealityView { content, attachments in
            content.add(root)
            content.add(toolbarAnchor)
            toolbarAnchor.position = [0, 0.8, -0.85]
            if let toolbar = attachments.entity(for: "toolbar") {
                // Tip it back to face someone looking down at it.
                toolbar.orientation = simd_quatf(angle: -20 * .pi / 180, axis: [1, 0, 0])
                toolbarAnchor.addChild(toolbar)
            }
        } attachments: {
            Attachment(id: "toolbar") { toolbar }
        }
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { model?.tap($0.entity) })
        .gesture(drag.simultaneously(with: magnify).simultaneously(with: rotate))
        .task(id: appModel.activeEnvironmentID) {
            await load()
        }
        .task {
            await placeToolbarAtViewer()
        }
    }

    // MARK: - Loading

    private func load() async {
        root.children.removeAll()
        model = nil
        skybox = nil
        loadError = nil
        renderingNote = nil
        splatCounts = nil
        isFlipped = false
        skyboxYaw = 0
        #if !targetEnvironment(simulator)
        splatExposure = nil
        #endif
        guard let env = appModel.activeEnvironment else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            switch env.content {
            case .bundledPanorama(let name):
                showSkybox(try await Panorama.texture(named: name))
            case .panorama(let url):
                showSkybox(try await TextureResource(contentsOf: url))
            case .storyPanorama(let itemID, let image):
                let url = try await StoryAssetStore.fileURL(itemID: itemID, resourceName: image.resourceName, session: appModel.arcGISSession)
                showSkybox(try await Panorama.texture(contentsOf: url))
            case .model(let url, let isRealityFile):
                let entity = try await Entity(contentsOf: url)
                Self.addGroundingShadows(to: entity)
                show(InteractiveModel(entity, isRealityFile: isRealityFile))
            case .pointCloud(let url):
                let start = ContinuousClock.now
                let cloud = try await Self.readPointCloud(url)
                Self.log.info("Parsed \(cloud.count) points in \(ContinuousClock.now - start); core size \(cloud.extents)")
                let extents = cloud.extents
                let entity = try await cloud.makeEntity(splatLimit: Self.splatBudget)
                show(InteractiveModel(entity, isRealityFile: false, bounds: BoundingBox(min: -extents / 2, max: extents / 2)))
                #if !targetEnvironment(simulator)
                splatExposure = PLYPointCloud.SplatExposure(in: entity)
                splatCounts = (min(cloud.count, Self.splatBudget), cloud.count)
                if cloud.count > Self.splatBudget {
                    let shown = Self.splatBudget.formatted(.number.notation(.compactName))
                    let total = cloud.count.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
                    renderingNote = "Showing the \(shown) most visible of \(total) splats, as many as visionOS draws at once."
                }
                #endif
            }
            await applyExposure()
        } catch is CancellationError {
            return
        } catch {
            Self.log.error("Couldn’t load \(env.title, privacy: .public): \(error, privacy: .public)")
            loadError = error.localizedDescription
        }
    }

    private func show(_ model: InteractiveModel) {
        root.addChild(model.pivot)
        self.model = model
        reset(animated: false)
    }

    private func showSkybox(_ texture: TextureResource) {
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        let sphere = ModelEntity(mesh: .generateSphere(radius: 1000), materials: [material])
        // Flip the sphere inside out so the panorama faces the viewer.
        sphere.scale = [-1, 1, 1]
        root.addChild(sphere)
        skybox = sphere
        orientSkybox(animated: false)
    }

    /// Parses off the main thread; splat captures run to hundreds of MB.
    @concurrent
    private nonisolated static func readPointCloud(_ url: URL) async throws -> PLYPointCloud {
        try PLYPointCloud(contentsOf: url)
    }

    /// Grounds a model in the room with soft contact shadows.
    private static func addGroundingShadows(to entity: Entity) {
        if entity.components.has(ModelComponent.self) {
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        }
        for child in entity.children { addGroundingShadows(to: child) }
    }

    /// Puts the toolbar 0.75 m in front of the viewer, a little below their
    /// eyes, whether they sit or stand.
    private func placeToolbarAtViewer() async {
        guard let (eye, yaw) = await Self.viewerPose() else { return }
        let facing = simd_quatf(angle: yaw, axis: [0, 1, 0])
        toolbarAnchor.position = SIMD3(eye.x, eye.y - 0.4, eye.z) + facing.act([0, 0, -0.75])
        toolbarAnchor.orientation = facing
    }

    /// Where the viewer's head is and which way they face, or nil without
    /// world tracking (such as in the simulator).
    private static func viewerPose() async -> (SIMD3<Float>, Float)? {
        guard WorldTrackingProvider.isSupported else { return nil }
        let session = ARKitSession()
        let world = WorldTrackingProvider()
        do {
            try await session.run([world])
        } catch {
            log.error("World tracking unavailable: \(error, privacy: .public)")
            return nil
        }
        defer { session.stop() }
        // The provider takes a moment to start, and the first pose after that.
        for _ in 0..<40 {
            if world.state == .running, let device = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()), device.isTracked {
                let m = device.originFromAnchorTransform
                let forward = -SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)
                return (SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z), atan2(-forward.x, -forward.z))
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    // MARK: - Toolbar actions

    /// The model's starting scale: its largest side at `modelSize`.
    private var fittedScale: Float {
        guard let model, model.extent > 0 else { return 1 }
        return Self.modelSize / model.extent
    }

    private func reset(animated: Bool = true) {
        isFlipped = false
        skyboxYaw = 0
        orientSkybox(animated: animated)
        guard let model else { return }
        let home = Transform(scale: .init(repeating: fittedScale), rotation: simd_quatf(angle: 0, axis: [0, 1, 0]), translation: Self.modelHome)
        move(model.pivot, to: home, animated: animated)
        applyFlip(animated: animated)
    }

    /// Turns the content an eighth of a turn to the right.
    private func turn() {
        let step = -Float.pi / 4
        if let model {
            var target = model.pivot.transform
            target.rotation = simd_quatf(angle: step, axis: [0, 1, 0]) * target.rotation
            move(model.pivot, to: target, animated: true)
        } else {
            skyboxYaw += step
            orientSkybox(animated: true)
        }
    }

    private func toggleFlip() {
        isFlipped.toggle()
        if model != nil {
            applyFlip(animated: true)
        } else {
            orientSkybox(animated: true)
        }
    }

    /// Flips a model upside down about its own center, inside the pivot so
    /// the drag and pinch gestures still apply as before.
    private func applyFlip(animated: Bool) {
        guard let content = model?.pivot.children.first else { return }
        var target = content.transform
        target.rotation = isFlipped ? simd_quatf(angle: .pi, axis: [0, 0, 1]) : simd_quatf(angle: 0, axis: [0, 0, 1])
        move(content, to: target, animated: animated)
    }

    private func orientSkybox(animated: Bool) {
        guard let skybox else { return }
        // RealityKit puts the image's center column behind the viewer, so a
        // half turn (`forwardYaw`) brings it to straight ahead.
        var rotation = simd_quatf(angle: Panorama.forwardYaw + skyboxYaw, axis: [0, 1, 0])
        if isFlipped { rotation = simd_quatf(angle: .pi, axis: [0, 0, 1]) * rotation }
        var target = skybox.transform
        target.rotation = rotation
        move(skybox, to: target, animated: animated)
    }

    private func move(_ entity: Entity, to transform: Transform, animated: Bool) {
        if animated {
            entity.move(to: transform, relativeTo: entity.parent, duration: 0.4, timingFunction: .easeInOut)
        } else {
            entity.transform = transform
        }
    }

    /// Brightens or darkens whatever is showing by `exposure` stops.
    private func applyExposure() async {
        let gain = pow(2, exposure)
        if let skybox, var material = skybox.model?.materials.first as? UnlitMaterial {
            material.color.tint = UIColor(white: CGFloat(gain), alpha: 1)
            skybox.model?.materials = [material]
        }
        #if !targetEnvironment(simulator)
        if let splatExposure {
            splatExposure.apply(stops: exposure)
            return
        }
        #endif
        guard let pivot = model?.pivot else { return }
        if exposure == 0 {
            // Back to the room's own lighting.
            pivot.components.remove(ImageBasedLightComponent.self)
            Self.setLightReceiver(nil, on: pivot)
            return
        }
        guard let light = await neutralLightResource() else { return }
        pivot.components.set(ImageBasedLightComponent(source: .single(light), intensityExponent: exposure))
        Self.setLightReceiver(pivot, on: pivot)
    }

    private static func setLightReceiver(_ light: Entity?, on entity: Entity) {
        if entity.components.has(ModelComponent.self) {
            if let light {
                entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
            } else {
                entity.components.remove(ImageBasedLightReceiverComponent.self)
            }
        }
        for child in entity.children { setLightReceiver(light, on: child) }
    }

    /// Soft light from a pale sky over a darker floor, for lighting a model
    /// at a chosen exposure.
    private func neutralLightResource() async -> EnvironmentResource? {
        if let neutralLight { return neutralLight }
        let width = 64, height = 32
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let colors = [CGColor(gray: 0.85, alpha: 1), CGColor(gray: 0.35, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: .zero, options: [])
        }
        guard let image = ctx.makeImage() else { return nil }
        neutralLight = try? await EnvironmentResource(equirectangular: image)
        return neutralLight
    }

    // MARK: - Gestures

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

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 10) {
            if let openCard {
                card(openCard)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
            }
            if let status {
                EnvironmentToolbar.status(status.text, systemImage: status.symbol)
            }
            HStack(spacing: 4) {
                toolButton("Close", systemImage: "xmark") {
                    Task { await appModel.dismissOpenImmersiveSpace(using: dismissImmersiveSpace) }
                }
                .disabled(appModel.isImmersiveSpaceInTransition)
                divider
                toolButton("Previous", systemImage: "chevron.left") { step(-1) }
                    .disabled(appModel.steppableEnvironmentIDs.count < 2 || appModel.isImmersiveSpaceInTransition)
                toolButton("Next", systemImage: "chevron.right") { step(1) }
                    .disabled(appModel.steppableEnvironmentIDs.count < 2 || appModel.isImmersiveSpaceInTransition)
                divider
                toolButton("Reset", systemImage: "arrow.counterclockwise") { reset() }
                toolButton("Turn", systemImage: "rotate.right") { turn() }
                toolButton("Flip upside down", systemImage: "arrow.up.and.down", isOn: isFlipped) { toggleFlip() }
                divider
                toolButton("Exposure", systemImage: "sun.max", isOn: openCard == .exposure) { toggle(.exposure) }
                toolButton("Music", systemImage: "music.note", isOn: openCard == .music) { toggle(.music) }
                toolButton("Info", systemImage: "info.circle", isOn: openCard == .info) { toggle(.info) }
            }
            .padding(6)
            .glassBackgroundEffect(in: Capsule())
        }
        .frame(width: 600, alignment: .bottom)
        .animation(.easeInOut(duration: 0.2), value: openCard)
    }

    private var status: (text: String, symbol: String)? {
        if isLoading { return ("Loading…", "hourglass") }
        if let loadError { return (loadError, "exclamationmark.triangle") }
        return nil
    }

    private var divider: some View { EnvironmentToolbar.divider }

    /// Steps to the previous or next environment, which may open the splat
    /// space instead of this one.
    private func step(_ offset: Int) {
        Task {
            await appModel.showAdjacentEnvironment(offset, using: .init(openSpace: openImmersiveSpace, dismissSpace: dismissImmersiveSpace, openWindow: openWindow))
        }
    }

    private func toggle(_ card: ToolbarCard) {
        openCard = openCard == card ? nil : card
    }

    private func toolButton(_ title: String, systemImage: String, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        EnvironmentToolbar.button(title, systemImage: systemImage, isOn: isOn, action: action)
    }

    private func card(_ card: ToolbarCard) -> some View {
        EnvironmentToolbar.card {
            switch card {
            case .exposure:
                ExposureCard(exposure: $exposure)
                    .onChange(of: exposure) {
                        Task { await applyExposure() }
                    }
            case .music: BackgroundMusicCard()
            case .info: infoCard
            }
        }
    }

    @ViewBuilder
    private var infoCard: some View {
        if let env = appModel.activeEnvironment {
            VStack(alignment: .leading, spacing: 4) {
                Text(env.title).font(.title3.bold()).lineLimit(2)
                Text(env.subtitle).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(infoRows, id: \.0) { row in
                    LabeledContent(row.0, value: row.1)
                }
            }
            .font(.system(size: 15))
            if let renderingNote {
                Label(renderingNote, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Text(model != nil
                 ? "Drag to move · Pinch with both hands to resize or turn · Tap to interact"
                 : "Turn the Digital Crown to change how much of the room it covers.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private var infoRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let splatCounts {
            rows.append(("Splats shown", "\(splatCounts.shown.formatted()) of \(splatCounts.total.formatted())"))
        }
        if let model {
            let size = model.extent * model.pivot.scale.x
            rows.append(("Size", Measurement(value: Double(size), unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2))))))
        }
        if exposure != 0 {
            rows.append(("Exposure", exposure.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))))
        }
        if isFlipped { rows.append(("Orientation", "Upside down")) }
        return rows
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

    /// A texture for a 360° photo. One covering less than 180° vertically
    /// (wider than 2:1) is banded around the horizon, with its top and bottom
    /// rows stretched to the poles, rather than stretched over the sphere.
    static func texture(contentsOf url: URL) async throws -> TextureResource {
        guard let image = await equirectangularImage(contentsOf: url) else {
            return try await TextureResource(contentsOf: url)
        }
        return try await TextureResource(image: image, options: .init(semantic: .color))
    }

    /// The photo padded to 2:1, or nil when it already is (or can't be read).
    @concurrent
    private nonisolated static func equirectangularImage(contentsOf url: URL) async -> sending CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width, height = width / 2
        guard image.height < height - 1 else { return nil }
        return padToEquirectangular(image, height: height)
    }

    /// Centers `image` vertically on a canvas `height` tall, smearing its
    /// edge rows over the bands above and below.
    nonisolated static func padToEquirectangular(_ image: CGImage, height: Int) -> CGImage? {
        let width = image.width
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        // Core Graphics' origin is bottom-left, so the band below is drawn first.
        let band = CGFloat(height - image.height) / 2
        if let bottomRow = image.cropping(to: CGRect(x: 0, y: image.height - 1, width: width, height: 1)) {
            ctx.draw(bottomRow, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: band + 1))
        }
        if let topRow = image.cropping(to: CGRect(x: 0, y: 0, width: width, height: 1)) {
            ctx.draw(topRow, in: CGRect(x: 0, y: band + CGFloat(image.height) - 1, width: CGFloat(width), height: band + 1))
        }
        ctx.draw(image, in: CGRect(x: 0, y: band, width: CGFloat(width), height: CGFloat(image.height)))
        return ctx.makeImage()
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
