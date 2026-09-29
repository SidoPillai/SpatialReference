//
//  AssetViewerImmersiveView.swift
//  SpatialReference
//

import SwiftUI
import RealityKit

/// Mixed-immersion space showing the chapter's 3D object with floating
/// glass panels: a hint, object controls, hotspot info cards and a narration
/// panel with the current sentence highlighted.
///
/// Milestone-1 content is a procedurally built placeholder "Great Lens", since
/// the demo StoryMap doesn't embed a USDZ asset. The object gets pinch-move /
/// rotate gestures via RealityKit's Manipulation component, which a real
/// chapter asset would get too.
struct AssetViewerImmersiveView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var lens = LensController()
    @State private var info: LensInfo?
    @State private var volume = 0.7

    private var player: NarrationPlayer { appModel.narrationPlayer }

    var body: some View {
        RealityView { content, _ in
            lens.build()
            content.add(lens.root)
        } update: { content, attachments in
            place(attachments.entity(for: "hint"), at: [0, 1.85, -1.5], in: content)
            place(attachments.entity(for: "controls"), at: [-0.35, 0.98, -1.45], in: content)
            place(attachments.entity(for: "narration"), at: [0, 0.68, -1.3], in: content)
            place(attachments.entity(for: "info"), at: [0.3, 1.38, -1.5], in: content)
            place(attachments.entity(for: "rings"), at: [-0.18, 1.36, -1.42], in: content)
            place(attachments.entity(for: "frame"), at: [-0.5, 1.09, -1.42], in: content)
        } attachments: {
            Attachment(id: "hint") { hintPill }
            Attachment(id: "controls") { controls }
            Attachment(id: "narration") { narrationPanel }
            Attachment(id: "info") { infoCard }
            Attachment(id: "rings") { hotspot(.rings) }
            Attachment(id: "frame") { hotspot(.frame) }
        }
        .task {
            if !player.isSpeaking, let text = appModel.currentChapter?.narrationText, !text.isEmpty {
                player.speak(text)
            }
        }
    }

    private func place(_ entity: Entity?, at position: SIMD3<Float>, in content: RealityViewContent) {
        guard let entity, entity.parent == nil else { return }
        entity.position = position
        content.add(entity)
    }

    // MARK: - Panels

    private var hintPill: some View {
        Label("Pinch and drag the lens to turn it", systemImage: "hand.pinch")
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 20)
            .frame(height: 44)
            .glassBackgroundEffect(in: Capsule())
    }

    private var controls: some View {
        HStack(spacing: 6) {
            iconButton("Rotate left", systemImage: "arrow.counterclockwise") { lens.rotate(degrees: -30) }
            iconButton("Rotate right", systemImage: "arrow.clockwise") { lens.rotate(degrees: 30) }
            iconButton("Smaller", systemImage: "minus") { lens.zoom(by: -0.1) }
            iconButton("Larger", systemImage: "plus") { lens.zoom(by: 0.1) }
            Button {
                lens.reset()
                info = nil
            } label: {
                Text("Reset")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(.white.opacity(0.1), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .hoverEffect()
        }
        .padding(8)
        .glassBackgroundEffect(in: Capsule())
    }

    private func iconButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.1), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityLabel(label)
    }

    private func hotspot(_ kind: LensInfo) -> some View {
        Button {
            info = kind
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .heavy))
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.35), in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityLabel("About the \(kind.title.lowercased())")
    }

    @ViewBuilder
    private var infoCard: some View {
        if let info {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text(info.title).font(.system(size: 20, weight: .semibold))
                    Spacer()
                    iconButton("Close", systemImage: "xmark") { self.info = nil }
                        .scaleEffect(0.92)
                }
                Text(info.body)
                    .font(.system(size: 16))
                    .lineSpacing(4)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(24)
            .frame(width: 340)
            .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 32))
        }
    }

    private var narrationPanel: some View {
        let text = appModel.currentChapter?.narrationText ?? ""
        let sentence = Self.sentence(in: text, containing: player.highlightedRange)
        let isPlaying = player.isSpeaking && !player.isPaused

        return VStack(spacing: 10) {
            HStack(spacing: 16) {
                iconButton("Exit immersion", systemImage: "xmark") {
                    Task { await dismissImmersiveSpace() }
                }
                Text(chapterLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity)
                iconButton(isPlaying ? "Pause narration" : "Play narration", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                    if !player.isSpeaking {
                        player.speak(text)
                    } else if player.isPaused {
                        player.resume()
                    } else {
                        player.pause()
                    }
                }
            }

            HighlightedCaptionView(
                text: sentence.text,
                highlightedRange: sentence.range,
                isNarrating: player.isSpeaking,
                fontSize: 23,
                lineSpacing: 6,
                alignment: .center
            )
            .frame(maxWidth: .infinity, minHeight: 64)

            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                Slider(value: $volume, in: 0...1) { editing in
                    if !editing { player.setVolume(Float(volume)) }
                }
                Image(systemName: "speaker.wave.3.fill")
            }
            .font(.system(size: 18))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(width: 720)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 40))
    }

    private var chapterLabel: String {
        "Chapter \(appModel.currentChapterIndex + 1)" + (appModel.story.map { " of \($0.chapters.count)" } ?? "")
    }

    /// The sentence containing the highlighted word (or the first sentence
    /// when nothing is being spoken), with the highlight re-based to it.
    private static func sentence(in text: String, containing highlight: NSRange?) -> (text: String, range: NSRange?) {
        let ns = text as NSString
        var found: (String, NSRange?)?
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .bySentences) { substring, range, _, stop in
            guard let substring else { return }
            if let highlight {
                guard NSLocationInRange(highlight.location, range) else { return }
                let local = highlight.location - range.location
                found = (substring, NSRange(location: local, length: min(highlight.length, range.length - local)))
            } else {
                found = (substring, nil)
            }
            stop.pointee = true
        }
        return found ?? (text, nil)
    }
}

enum LensInfo {
    case rings, frame

    var title: String {
        switch self {
        case .rings: "Prism rings"
        case .frame: "Brass frame"
        }
    }

    var body: String {
        switch self {
        case .rings: "Each ridge of glass bends a sliver of the flame toward the horizon, so one small light can be seen miles out at sea."
        case .frame: "The cradle turns the lens on a bed of rollers. Maren wound its clockwork every four hours through the night."
        }
    }
}

/// Owns the placeholder lens entity and its rotate / zoom / reset actions.
@MainActor
final class LensController {
    let root = Entity()
    private let lens = Entity()
    private var scale: Float = 1

    private static let restingYaw: Float = -18 * .pi / 180
    private static let center: SIMD3<Float> = [-0.35, 1.3, -1.5]

    func build() {
        guard lens.children.isEmpty else { return }
        root.position = Self.center

        let brass = SimpleMaterial(color: UIColor(red: 0.74, green: 0.56, blue: 0.24, alpha: 1), roughness: 0.35, isMetallic: true)
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: UIColor(red: 0.72, green: 0.85, blue: 0.93, alpha: 1))
        glass.roughness = 0.05
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.28))
        let flame = UnlitMaterial(color: UIColor(red: 1, green: 0.91, blue: 0.72, alpha: 1))

        func part(_ mesh: MeshResource, _ material: some Material, at position: SIMD3<Float>) -> ModelEntity {
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = position
            return entity
        }

        let w: Float = 0.228, h: Float = 0.34, d: Float = 0.03, t: Float = 0.012

        // Glass slab and brass frame.
        lens.addChild(part(.generateBox(size: [w, h, d * 0.5], cornerRadius: 0.01), glass, at: .zero))
        lens.addChild(part(.generateBox(size: [w + t, t, d]), brass, at: [0, h / 2, 0]))
        lens.addChild(part(.generateBox(size: [w + t, t, d]), brass, at: [0, -h / 2, 0]))
        lens.addChild(part(.generateBox(size: [t, h, d]), brass, at: [-w / 2, 0, 0]))
        lens.addChild(part(.generateBox(size: [t, h, d]), brass, at: [w / 2, 0, 0]))
        lens.addChild(part(.generateBox(size: [0.004, h, 0.006]), brass, at: .zero))
        lens.addChild(part(.generateBox(size: [w, 0.004, 0.006]), brass, at: .zero))
        lens.addChild(part(.generateBox(size: [0.14, 0.018, 0.05]), brass, at: [0, -h / 2 - 0.02, 0]))

        // Stepped prism rings, largest at the back, facing the viewer.
        for (index, radius) in [Float(0.098), 0.076, 0.056, 0.036].enumerated() {
            let ring = part(.generateCylinder(height: 0.004, radius: radius), glass, at: [0, 0, 0.004 + Float(index) * 0.004])
            ring.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            lens.addChild(ring)
        }

        // The flame.
        lens.addChild(part(.generateSphere(radius: 0.016), flame, at: [0, 0, 0.012]))

        lens.generateCollisionShapes(recursive: true)
        lens.components.set(InputTargetComponent())
        ManipulationComponent.configureEntity(lens)
        root.addChild(lens)
        reset(animated: false)
    }

    func rotate(degrees: Float) {
        let turn = simd_quatf(angle: degrees * .pi / 180, axis: [0, 1, 0])
        apply(orientation: turn * lens.orientation, scale: scale, position: lens.position)
    }

    func zoom(by delta: Float) {
        scale = min(1.4, max(0.7, scale + delta))
        apply(orientation: lens.orientation, scale: scale, position: lens.position)
    }

    func reset(animated: Bool = true) {
        scale = 1
        let orientation = simd_quatf(angle: Self.restingYaw, axis: [0, 1, 0])
        if animated {
            apply(orientation: orientation, scale: 1, position: .zero)
        } else {
            lens.orientation = orientation
            lens.position = .zero
            lens.scale = [1, 1, 1]
        }
    }

    private func apply(orientation: simd_quatf, scale: Float, position: SIMD3<Float>) {
        let target = Transform(scale: [scale, scale, scale], rotation: orientation, translation: position)
        lens.move(to: target, relativeTo: root, duration: 0.4, timingFunction: .easeInOut)
    }
}

#Preview(immersionStyle: .mixed) {
    AssetViewerImmersiveView()
        .environment(AppModel())
}
