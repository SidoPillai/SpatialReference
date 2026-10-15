//
//  EnvironmentsView.swift
//  SpatialReference
//

import SwiftUI
import UniformTypeIdentifiers

/// An immersive environment, shown as an orb (or a wide capsule for
/// panoramas). Those with a panorama can be entered; the rest are previews.
struct ImmersiveEnvironment: Identifiable {
    var id: String { title }
    let title: String
    let location: String
    let summary: String
    let art: AnyShapeStyle
    var glows: [CoverGlow] = []
    var stars = false
    /// Panoramic landscapes read better as a wide capsule than a sphere.
    var wide = false
    /// Planets and moons get sphere shading; landscapes stay flat.
    var sphere = false
    /// Equirectangular panorama surrounding the viewer; see `Panorama`.
    var panorama: String?

    var isAvailable: Bool { panorama.map(Panorama.hasContent(named:)) ?? false }

    static let catalog: [ImmersiveEnvironment] = [
        ImmersiveEnvironment(
            title: "Mars", location: "Jezero Crater",
            summary: "Stand beside the Perseverance rover on the floor of an ancient lake bed under a butterscotch sky.",
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0xE07A3C), Color(hex: 0xA8431C), Color(hex: 0x5A1F0C)],
                startPoint: .topLeading, endPoint: .bottomTrailing)),
            glows: [CoverGlow(center: UnitPoint(x: 0.35, y: 0.55), radius: 0.18, color: Color(hex: 0x6E2A10).opacity(0.7)),
                    CoverGlow(center: UnitPoint(x: 0.7, y: 0.3), radius: 0.14, color: Color(hex: 0x7A3214).opacity(0.6))],
            sphere: true
        ),
        ImmersiveEnvironment(
            title: "The Moon", location: "Sea of Tranquility",
            summary: "Look back at Earth from the Apollo 11 landing site, with the descent stage and bootprints at your feet.",
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0xE4E4E0), Color(hex: 0x9C9C98), Color(hex: 0x4A4A48)],
                startPoint: .topLeading, endPoint: .bottomTrailing)),
            glows: [CoverGlow(center: UnitPoint(x: 0.3, y: 0.35), radius: 0.12, color: Color(hex: 0x6A6A66).opacity(0.7)),
                    CoverGlow(center: UnitPoint(x: 0.62, y: 0.6), radius: 0.16, color: Color(hex: 0x70706C).opacity(0.6)),
                    CoverGlow(center: UnitPoint(x: 0.7, y: 0.28), radius: 0.07, color: Color(hex: 0x5E5E5A).opacity(0.7))],
            sphere: true,
            panorama: Panorama.moon
        ),
    ]
}

/// Environments tab: a field of orbs, one per environment, then the user's
/// imported 360° images and models and an Add orb that opens Files.
/// Selecting one shows its details in a glass bar along the bottom.
struct EnvironmentsView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var selected: String?
    @State private var isImporting = false
    @State private var isAdding = false
    @State private var importError: String?

    private static let orb: CGFloat = 170

    private var store: ImportedEnvironmentStore { appModel.importedEnvironments }

    private var selection: ImmersiveEnvironment? {
        ImmersiveEnvironment.catalog.first { $0.id == selected }
    }

    private var importedSelection: ImportedEnvironment? {
        store.items.first { $0.id == selected }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Environments")
                    .font(.system(size: 40, weight: .bold))
                Text("Places to surround yourself with while you read, or add your own 360° photos and 3D models.")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }

            ScrollView {
                FlowLayout(spacing: 44, lineSpacing: 32) {
                    ForEach(ImmersiveEnvironment.catalog) { orb($0) }
                    ForEach(store.items) { importedOrb($0) }
                    addOrb
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            if let env = selection {
                detailBar(env)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let item = importedSelection {
                importedDetailBar(item)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.top, 40)
        .padding([.horizontal, .bottom], 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(duration: 0.35), value: selected)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: ImportedEnvironmentStore.contentTypes) { result in
            Task { await add(result) }
        }
        .alert("Couldn’t add that file", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private func orb(_ env: ImmersiveEnvironment) -> some View {
        let on = env.id == selected
        let shape = RoundedRectangle(cornerRadius: Self.orb / 2)
        return Button { selected = on ? nil : env.id } label: {
            VStack(spacing: 14) {
                CoverArt(art: env.art, glows: env.glows, stars: env.stars)
                    .overlay {
                        if env.sphere {
                            // Lit from the upper left, falling into shadow.
                            RadialGradient(
                                colors: [.white.opacity(0.35), .clear, .black.opacity(0.65)],
                                center: UnitPoint(x: 0.3, y: 0.28), startRadius: 0, endRadius: Self.orb * 0.85)
                        }
                    }
                    .frame(width: env.wide ? Self.orb * 2.2 : Self.orb, height: Self.orb)
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(.white.opacity(on ? 0.95 : 0.12), lineWidth: on ? 3 : 1)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
                    .hoverEffect { effect, isActive, _ in
                        effect.animation(.easeOut(duration: 0.3)) {
                            $0.scaleEffect(isActive ? 1.06 : 1)
                        }
                    }
                Text(env.title)
                    .font(.system(size: 18, weight: .semibold))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(env.title), \(env.location)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Opens Files to pick a 360° image, `.usdz`, `.reality` or `.ply` file.
    private var addOrb: some View {
        Button { isImporting = true } label: {
            VStack(spacing: 14) {
                Circle()
                    .fill(.white.opacity(0.06))
                    .overlay { Circle().strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6, 6])) }
                    .overlay {
                        if isAdding {
                            ProgressView()
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 40, weight: .light))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .frame(width: Self.orb, height: Self.orb)
                    .hoverEffect { effect, isActive, _ in
                        effect.animation(.easeOut(duration: 0.3)) {
                            $0.scaleEffect(isActive ? 1.06 : 1)
                        }
                    }
                Text("Add")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAdding)
        .accessibilityLabel("Add a 360° image, 3D model or point cloud")
    }

    private func importedOrb(_ item: ImportedEnvironment) -> some View {
        let on = item.id == selected
        let wide = item.kind == .panorama
        let shape = RoundedRectangle(cornerRadius: Self.orb / 2)
        return Button { selected = on ? nil : item.id } label: {
            VStack(spacing: 14) {
                importedArt(item)
                    .frame(width: wide ? Self.orb * 2.2 : Self.orb, height: Self.orb)
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(.white.opacity(on ? 0.95 : 0.12), lineWidth: on ? 3 : 1)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
                    .hoverEffect { effect, isActive, _ in
                        effect.animation(.easeOut(duration: 0.3)) {
                            $0.scaleEffect(isActive ? 1.06 : 1)
                        }
                    }
                Text(item.title)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: wide ? Self.orb * 2.2 : Self.orb)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove", systemImage: "trash", role: .destructive) { Task { await remove(item) } }
        }
        .accessibilityLabel("\(item.title), \(item.subtitle)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A panorama's own thumbnail; a cube on a dark gradient for models.
    @ViewBuilder
    private func importedArt(_ item: ImportedEnvironment) -> some View {
        if item.kind == .panorama, let thumbnail = UIImage(contentsOfFile: store.thumbnailURL(for: item).path) {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(colors: [Color(hex: 0x3A4A6B), Color(hex: 0x141B2D)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay {
                    Image(systemName: Self.symbol(for: item))
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.white.opacity(0.85))
                }
        }
    }

    private static func symbol(for item: ImportedEnvironment) -> String {
        switch item.kind {
        case .panorama: "photo"
        case .model: item.isRealityFile ? "arkit" : "cube.transparent"
        case .pointCloud: "circle.dotted.and.circle"
        }
    }

    private func detailBar(_ env: ImmersiveEnvironment) -> some View {
        HStack(spacing: 20) {
            CoverArt(art: env.art, glows: env.glows, stars: env.stars)
                .frame(width: 64, height: 64)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(env.title).font(.system(size: 22, weight: .bold))
                    Text(env.location)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text(env.summary)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
            Spacer()
            if env.isAvailable {
                enterButton(id: env.id, title: env.title)
            } else {
                Label("Coming Soon", systemImage: "visionpro")
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                    .background(.white.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                    .accessibilityLabel("Environment coming soon")
            }
        }
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 28))
    }

    private func importedDetailBar(_ item: ImportedEnvironment) -> some View {
        HStack(spacing: 20) {
            importedArt(item)
                .frame(width: 64, height: 64)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Button {
                Task { await remove(item) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .hoverEffect()
            .disabled(appModel.isImmersiveSpaceInTransition)
            .accessibilityLabel("Remove \(item.title)")
            enterButton(id: item.id, title: item.title)
        }
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 28))
    }

    private func enterButton(id: String, title: String) -> some View {
        let inside = appModel.activeEnvironmentID == id
        return Button {
            Task { await toggle(id) }
        } label: {
            Label(inside ? "Exit" : "Enter", systemImage: inside ? "xmark" : "visionpro")
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 20)
                .frame(height: 48)
                .foregroundStyle(inside ? .white : .black)
                .background(inside ? AnyShapeStyle(.white.opacity(0.12)) : AnyShapeStyle(.white), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .disabled(appModel.isImmersiveSpaceInTransition)
        .accessibilityLabel(inside ? "Exit \(title)" : "Enter \(title)")
    }

    /// Copies the picked file into the app, selects it and opens it.
    private func add(_ result: Result<URL, Error>) async {
        isAdding = true
        defer { isAdding = false }
        do {
            let item = try await store.add(from: result.get())
            selected = item.id
            await toggle(item.id)
        } catch let error as CocoaError where error.code == .userCancelled {
            return
        } catch {
            importError = error.localizedDescription
        }
    }

    private func remove(_ item: ImportedEnvironment) async {
        if appModel.activeEnvironmentID == item.id {
            await appModel.dismissOpenImmersiveSpace(using: dismissImmersiveSpace)
        }
        if selected == item.id { selected = nil }
        store.remove(item)
    }

    private func toggle(_ id: String) async {
        if appModel.activeEnvironmentID == id {
            await appModel.dismissOpenImmersiveSpace(using: dismissImmersiveSpace)
            return
        }
        // Closes the asset viewer or another environment first.
        await appModel.dismissOpenImmersiveSpace(using: dismissImmersiveSpace)
        appModel.activeEnvironmentID = id
        appModel.environmentSpaceState = .inTransition
        switch await openImmersiveSpace(id: appModel.environmentSpaceID) {
        case .opened:
            // The space's onAppear marks it open.
            break
        case .userCancelled, .error:
            fallthrough
        @unknown default:
            appModel.environmentSpaceState = .closed
            appModel.activeEnvironmentID = nil
        }
    }
}
