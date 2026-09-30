//
//  GalleryCarouselView.swift
//  SpatialReference
//

import RealityKit
import SwiftUI

/// A StoryMaps gallery block as a paged carousel: plain images are shown as
/// pictures and `usdz` items as live 3D models (downloaded on demand from the
/// story item and unzipped by `StoryAssetStore`).
struct GalleryCarouselView: View {

    let itemID: String
    let items: [GalleryItem]

    @State private var selection: String?

    private var currentIndex: Int {
        items.firstIndex { $0.id == selection } ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let pageWidth = geo.size.width * 0.6
            let pageHeight = max(240, geo.size.height - 104)

            VStack(spacing: 18) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 28) {
                        ForEach(items) { item in
                            GalleryPage(itemID: itemID, item: item, isSelected: item.id == (selection ?? items.first?.id))
                                .frame(width: pageWidth, height: pageHeight)
                                .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, (geo.size.width - pageWidth) / 2, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selection)
                .scrollIndicators(.hidden)
                .overlay(alignment: .leading) { arrow("chevron.left", label: "Previous", step: -1) }
                .overlay(alignment: .trailing) { arrow("chevron.right", label: "Next", step: 1) }

                footer
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Text(items[currentIndex].title)
                .font(.system(size: 26, design: .serif))
                .lineLimit(1)
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, _ in
                    Circle()
                        .fill(.white.opacity(index == currentIndex ? 0.95 : 0.3))
                        .frame(width: 9, height: 9)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Item \(currentIndex + 1) of \(items.count)")
        }
    }

    @ViewBuilder
    private func arrow(_ systemImage: String, label: String, step: Int) -> some View {
        let target = currentIndex + step
        if items.indices.contains(target) {
            Button {
                withAnimation { selection = items[target].id }
            } label: {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 56, height: 56)
                    .background(.black.opacity(0.45), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .hoverEffect()
            .accessibilityLabel(label)
            .padding(.horizontal, 16)
        }
    }
}

private struct GalleryPage: View {

    let itemID: String
    let item: GalleryItem
    /// Only the centred page hosts a live 3D model (and downloads it): 3D
    /// content isn't clipped by the card, so a neighbouring page's model would
    /// spill outside the window.
    let isSelected: Bool

    @Environment(AppModel.self) private var appModel

    private enum ModelState {
        case loading
        case ready(Model3DAsset)
        case failed(String)
    }

    @State private var picture: UIImage?
    @State private var modelState = ModelState.loading
    @State private var attempt = 0

    // Model orientation and scale: committed values plus the in-flight gesture.
    @State private var yaw = 0.0
    @State private var pitch = 0.0
    @State private var zoom = 1.0
    @State private var dragTranslation = CGSize.zero
    @State private var pinch = 1.0

    private var isModel: Bool {
        if case .model = item.kind { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)

            if let picture, !showsLiveModel {
                Image(uiImage: picture)
                    .resizable()
                    .scaledToFit()
                    .opacity(isModel ? 0.5 : 1)
            } else if isModel, !showsLiveModel {
                Image(systemName: "cube")
                    .font(.system(size: 88, weight: .ultraLight))
                    .opacity(0.5)
            }

            if isModel && isSelected {
                modelContent
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(.white.opacity(0.4), lineWidth: 1.5))
        .overlay(alignment: .topLeading) {
            Label(isModel ? "3D model" : "Image", systemImage: isModel ? "cube" : "photo")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.4), in: Capsule())
                .padding(20)
        }
        .task(id: item.id) { await loadPicture() }
        .task(id: "\(attempt)-\(isSelected)") {
            if isModel && isSelected && !isReady { await loadModel() }
        }
    }

    private var showsLiveModel: Bool { isModel && isSelected && isReady }

    private var isReady: Bool {
        if case .ready = modelState { return true }
        return false
    }

    @ViewBuilder
    private var modelContent: some View {
        switch modelState {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Downloading 3D model…").font(.system(size: 16, weight: .medium))
            }
            .padding(20)
            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 20))
        case .ready(let asset):
            Model3D(asset: asset) { model in
                model.resizable().aspectRatio(contentMode: .fit)
            }
            .rotation3DEffect(.degrees(pitch + dragTranslation.height * 0.4), axis: .x)
            .rotation3DEffect(.degrees(yaw + dragTranslation.width * 0.4), axis: .y)
            .scaleEffect(x: zoom * pinch, y: zoom * pinch, z: zoom * pinch)
            .padding(56)
            // Model3D is display-only, so interaction is added here. The
            // gestures cover the whole card (a child gesture wins over the
            // carousel's scrolling; the arrows and dots still page).
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { dragTranslation = $0.translation }
                    .onEnded { value in
                        yaw += value.translation.width * 0.4
                        pitch = min(80, max(-80, pitch + value.translation.height * 0.4))
                        dragTranslation = .zero
                    }
                    .simultaneously(with: MagnifyGesture()
                        .onChanged { pinch = $0.magnification }
                        .onEnded { value in
                            zoom = min(2, max(0.5, zoom * value.magnification))
                            pinch = 1
                        })
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeOut(duration: 0.3)) { yaw = 0; pitch = 0; zoom = 1 }
            }
            .overlay(alignment: .bottom) {
                Text("Drag to rotate · Pinch to zoom · Double-tap to reset")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.4), in: Capsule())
                    .padding(16)
                    .allowsHitTesting(false)
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Label("Couldn’t load this model", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 18, weight: .semibold))
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                Button("Try again") { modelState = .loading; attempt += 1 }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func loadPicture() async {
        let resourceName: String
        switch item.kind {
        case .image(let name): resourceName = name
        case .model: guard let poster = item.posterResourceName else { return }; resourceName = poster
        }
        guard let data = try? await StoryAssetStore.imageData(
            itemID: itemID, resourceName: resourceName, session: appModel.arcGISSession
        ) else { return }
        picture = UIImage(data: data)
    }

    private func loadModel() async {
        guard case .model(let resourceName) = item.kind else { return }
        modelState = .loading
        do {
            let url = try await StoryAssetStore.modelURL(
                itemID: itemID, resourceName: resourceName, session: appModel.arcGISSession
            )
            let asset = try await Model3DAsset(url: url)
            // Quick Look-style models often carry an animation; start it.
            asset.selectedAnimation = asset.availableAnimations.first
            asset.animationPlaybackController?.resume()
            modelState = .ready(asset)
        } catch is CancellationError {
            return
        } catch {
            modelState = .failed(error.localizedDescription)
        }
    }
}
