//
//  Image360SequenceView.swift
//  SpatialReference
//

import ImageIO
import SwiftUI

/// A run of StoryMaps 360° image blocks, shown one after the other: a paged
/// carousel of flat previews, and a button to step inside the current one.
///
/// Inside, the panorama surrounds the viewer in the environment space, whose
/// toolbar steps to the story's previous and next 360° images; the carousel
/// follows along, and paging the carousel swaps the panorama.
struct Image360SequenceView: View {

    let itemID: String
    let images: [Image360]

    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    @State private var selection: String?

    private var currentIndex: Int {
        images.firstIndex { $0.id == selection } ?? 0
    }

    private var current: Image360 { images[currentIndex] }

    /// The image of this sequence the environment space is showing, if any.
    private var insideImageID: String? {
        images.first { AppModel.environmentID(for: $0) == appModel.activeEnvironmentID }?.id
    }

    /// Height of the thumbnail strip and the caption row below the pages.
    private static let filmstripHeight: CGFloat = 52
    private static let footerHeight: CGFloat = 52
    private static let spacing: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            // Pages are 2:1, like the panoramas, as wide as fits.
            let chrome = Self.filmstripHeight + Self.footerHeight + 2 * Self.spacing
            let pageWidth = max(320, min(geo.size.width * 0.84, (geo.size.height - chrome) * 2))
            let pageHeight = pageWidth / 2

            VStack(spacing: Self.spacing) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 24) {
                        ForEach(images) { image in
                            Image360Page(itemID: itemID, image: image, isInside: image.id == insideImageID)
                                .frame(width: pageWidth, height: pageHeight)
                                .scrollTransition(axis: .horizontal) { content, phase in
                                    content
                                        .opacity(phase.isIdentity ? 1 : 0.4)
                                        .scaleEffect(phase.isIdentity ? 1 : 0.88)
                                }
                                .id(image.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, (geo.size.width - pageWidth) / 2, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selection)
                .scrollIndicators(.hidden)
                .frame(height: pageHeight)
                .overlay(alignment: .leading) { arrow("chevron.left", label: "Previous image", step: -1) }
                .overlay(alignment: .trailing) { arrow("chevron.right", label: "Next image", step: 1) }

                filmstrip(width: pageWidth)

                footer
                    .frame(width: pageWidth, height: Self.footerHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { followEnvironment(appModel.activeEnvironmentID) }
        .onChange(of: appModel.activeEnvironmentID) { _, id in followEnvironment(id) }
        .onChange(of: selection) {
            // Already inside one of these: show the newly paged-to one instead.
            if insideImageID != nil, insideImageID != current.id {
                Task { await enter(current) }
            }
        }
        .task(id: currentIndex) { await prefetchNeighbors() }
    }

    /// Every image as a small thumbnail; tapping one pages to it.
    private func filmstrip(width: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                        Button {
                            withAnimation { selection = image.id }
                        } label: {
                            Image360Thumbnail(itemID: itemID, image: image, isSelected: index == currentIndex)
                                .frame(width: Self.filmstripHeight * 2, height: Self.filmstripHeight)
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                        .accessibilityLabel(image.caption ?? "360° image \(index + 1)")
                        .id(image.id)
                    }
                }
                .padding(.horizontal, 4)
                // Centred when the thumbnails don't fill the strip.
                .frame(minWidth: width)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: width, height: Self.filmstripHeight)
            .onChange(of: currentIndex) {
                withAnimation { proxy.scrollTo(current.id, anchor: .center) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(current.caption ?? "360° image")
                    .font(.system(size: 26, design: .serif))
                    .lineLimit(1)
                Text("\(currentIndex + 1) of \(images.count)")
                    .font(.system(size: 15, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
            enterButton
        }
    }

    private var enterButton: some View {
        let inside = insideImageID == current.id
        return Button {
            Task {
                if inside {
                    await appModel.dismissOpenImmersiveSpace(using: dismissImmersiveSpace)
                } else {
                    await enter(current)
                }
            }
        } label: {
            Label(inside ? "Leave 360°" : "Step inside", systemImage: inside ? "xmark" : "visionpro")
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 22)
                .frame(height: 52)
                .foregroundStyle(inside ? .white : .black)
                .background(inside ? AnyShapeStyle(.white.opacity(0.12)) : AnyShapeStyle(.white), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .disabled(appModel.isImmersiveSpaceInTransition)
        .accessibilityLabel(inside ? "Leave this 360° image" : "Step inside this 360° image")
    }

    @ViewBuilder
    private func arrow(_ systemImage: String, label: String, step: Int) -> some View {
        let target = currentIndex + step
        if images.indices.contains(target) {
            Button {
                withAnimation { selection = images[target].id }
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

    private func enter(_ image: Image360) async {
        await appModel.enterEnvironment(
            AppModel.environmentID(for: image),
            using: .init(openSpace: openImmersiveSpace, dismissSpace: dismissImmersiveSpace, openWindow: openWindow)
        )
    }

    /// Pages to the image the environment space moved to, when it's one of these.
    private func followEnvironment(_ id: String?) {
        guard let image = images.first(where: { AppModel.environmentID(for: $0) == id }), image.id != selection else { return }
        withAnimation { selection = image.id }
    }

    /// Downloads the images either side of the current one, so stepping to
    /// them, in the window or inside, doesn't wait on the network.
    private func prefetchNeighbors() async {
        for index in [currentIndex + 1, currentIndex - 1] where images.indices.contains(index) {
            _ = try? await StoryAssetStore.fileURL(itemID: itemID, resourceName: images[index].resourceName, session: appModel.arcGISSession)
        }
    }
}

/// One 360° image, previewed flat (the whole equirectangular photo).
private struct Image360Page: View {

    let itemID: String
    let image: Image360
    let isInside: Bool

    @Environment(AppModel.self) private var appModel

    @State private var preview: UIImage?
    @State private var failed = false

    var body: some View {
        // The photo fills an overlay rather than sizing the page, so a
        // panorama wider than 2:1 is cropped to the page, not spread over
        // its neighbours.
        Color.black.opacity(0.3)
            .overlay {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                } else if failed {
                    Label("Couldn’t load this image", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 18, weight: .semibold))
                } else {
                    ProgressView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 32))
            .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(.white.opacity(isInside ? 0.9 : 0.3), lineWidth: isInside ? 3 : 1))
            .overlay(alignment: .topLeading) {
                Label(isInside ? "You’re inside" : "360°", systemImage: isInside ? "visionpro" : "pano")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(18)
            }
            .task(id: image.id) {
                do {
                    guard let image = try await Image360Preview.load(itemID: itemID, image: image, maxPixelSize: 2048, session: appModel.arcGISSession) else {
                        failed = true
                        return
                    }
                    preview = image
                } catch is CancellationError {
                    return
                } catch {
                    failed = true
                }
            }
    }
}

/// One image in the thumbnail strip.
private struct Image360Thumbnail: View {

    let itemID: String
    let image: Image360
    let isSelected: Bool

    @Environment(AppModel.self) private var appModel

    @State private var thumbnail: UIImage?

    var body: some View {
        Color.white.opacity(0.08)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(isSelected ? 0.95 : 0), lineWidth: 2.5))
            .opacity(isSelected ? 1 : 0.6)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .task(id: image.id) {
                thumbnail = try? await Image360Preview.load(itemID: itemID, image: image, maxPixelSize: 256, session: appModel.arcGISSession)
            }
    }
}

/// Downsampled previews of a story's 360° images: the panoramas run to 5000
/// pixels wide, far more than a card needs to hold decoded in memory.
private enum Image360Preview {
    static func load(itemID: String, image: Image360, maxPixelSize: Int, session: ArcGISOnlineSession) async throws -> UIImage? {
        let url = try await StoryAssetStore.fileURL(itemID: itemID, resourceName: image.resourceName, session: session)
        return await downsample(url, maxPixelSize: maxPixelSize).map { UIImage(cgImage: $0) }
    }

    @concurrent
    private nonisolated static func downsample(_ url: URL, maxPixelSize: Int) async -> sending CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
