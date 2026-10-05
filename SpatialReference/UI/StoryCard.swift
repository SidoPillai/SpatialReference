//
//  StoryCard.swift
//  SpatialReference
//

import SwiftUI

/// Corner badge on a card's cover, e.g. "New" or "Updated".
enum CardTag {
    case new, updated
}

/// Pill under a card's title: filled blue for public stories, an amber
/// outline for anything with restricted access.
struct CardBadge {
    let text: String
    let systemImage: String
    var filled = false
}

/// One icon + label entry in a card's feature list ("3D Model", "Audio Guide").
struct CardFeature: Hashable {
    let systemImage: String
    let label: String
}

/// Who can see a story, mirroring ArcGIS item access.
enum StoryAccess {
    case `public`, organization, shared, `private`

    /// Maps an ArcGIS item's `access` value ("public", "org", "shared", "private").
    init(arcGIS access: String) {
        switch access {
        case "public": self = .public
        case "org": self = .organization
        case "shared": self = .shared
        default: self = .private
        }
    }

    var badge: CardBadge {
        switch self {
        case .public: CardBadge(text: "Public", systemImage: "globe", filled: true)
        case .organization: CardBadge(text: "Organization", systemImage: "building.2")
        case .shared: CardBadge(text: "Shared", systemImage: "person.2")
        case .private: CardBadge(text: "Private", systemImage: "lock")
        }
    }
}

enum StoryCardMetrics {
    static let radius: CGFloat = 30
    static let height: CGFloat = 420
    static let coverHeight: CGFloat = 190
}

/// Catalog card: cover image on top, then a tinted info panel with the title,
/// an access badge and a wrapping list of features. The info panel is tinted
/// by a blurred copy of the cover so each card picks up its own colour.
struct StoryCard<Cover: View>: View {
    let title: String
    var tag: CardTag?
    let badge: CardBadge
    let features: [CardFeature]
    @ViewBuilder let cover: Cover

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The cover is an overlay so a wide image can't widen the card.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: StoryCardMetrics.coverHeight)
                .overlay { cover }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if let tag { TagPill(tag: tag).padding(14) }
                }

            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                BadgePill(badge: badge)
                FlowLayout(spacing: 14, lineSpacing: 8) {
                    ForEach(features, id: \.self) { feature in
                        HStack(spacing: 5) {
                            Image(systemName: feature.systemImage)
                            Text(feature.label)
                        }
                    }
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    Color(red: 0.40, green: 0.35, blue: 0.30).opacity(0.8)
                    cover.blur(radius: 40).opacity(0.55)
                }
                .clipped()
                .allowsHitTesting(false)
            }
        }
        .frame(height: StoryCardMetrics.height)
        .clipShape(RoundedRectangle(cornerRadius: StoryCardMetrics.radius))
        .overlay {
            RoundedRectangle(cornerRadius: StoryCardMetrics.radius)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: StoryCardMetrics.radius))
    }
}

struct TagPill: View {
    let tag: CardTag

    var body: some View {
        HStack(spacing: 5) {
            switch tag {
            case .new:
                Image(systemName: "sparkle")
                Text("New")
            case .updated:
                Circle()
                    .strokeBorder(Color(hex: 0xF0A050), lineWidth: 2)
                    .frame(width: 12, height: 12)
                Text("Updated")
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(tag == .new ? .black : .white)
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(tag == .new ? AnyShapeStyle(.white) : AnyShapeStyle(.black.opacity(0.8)), in: Capsule())
    }
}

struct BadgePill: View {
    let badge: CardBadge

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: badge.systemImage)
            Text(badge.text)
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(badge.filled ? .white : Color(hex: 0xFFE3C4))
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(badge.filled ? Color(hex: 0x1F7BFF) : .white.opacity(0.06), in: Capsule())
        .overlay {
            if !badge.filled {
                Capsule().strokeBorder(Color(hex: 0xF0A060), lineWidth: 2)
            }
        }
    }
}

/// Lays subviews out left to right, wrapping onto new lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(subviews, width: proposal.width ?? .infinity)
        let width = frames.map(\.maxX).max() ?? 0
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(subviews, width: bounds.width)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}
