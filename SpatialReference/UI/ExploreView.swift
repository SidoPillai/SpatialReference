//
//  ExploreView.swift
//  SpatialReference
//

import AVFoundation
import SwiftUI

/// Placeholder catalog entry for the Explore grid. Cover art is drawn from
/// gradients until stories carry real thumbnails.
/// Soft radial highlight layered over a cover gradient. Center and radius
/// are fractions of the card (radius relative to the card's width).
struct CoverGlow {
    let center: UnitPoint
    let radius: CGFloat
    let color: Color
}

/// Cover art: gradient + glows (+ stars for the space story). Glows and stars
/// are drawn in a Canvas so they never influence layout.
struct CoverArt: View {
    let story: ExploreStory
    var body: some View {
        Rectangle().fill(story.art)
            .overlay {
                Canvas { ctx, size in
                    for g in story.glows {
                        let center = CGPoint(x: size.width * g.center.x, y: size.height * g.center.y)
                        let r = g.radius * size.width
                        ctx.fill(
                            Path(CGRect(origin: .zero, size: size)),
                            with: .radialGradient(
                                Gradient(colors: [g.color, g.color.opacity(0)]),
                                center: center, startRadius: 0, endRadius: r))
                    }
                    if story.stars {
                        for (x, y, d) in [(0.20, 0.30, 3.2), (0.70, 0.58, 2.4), (0.42, 0.78, 2.8), (0.86, 0.20, 2.4), (0.56, 0.14, 2.4), (0.12, 0.62, 2.0)] {
                            ctx.fill(Path(ellipseIn: CGRect(x: size.width * x - d / 2, y: size.height * y - d / 2, width: d, height: d)), with: .color(.white))
                        }
                    }
                }
                .allowsHitTesting(false)
            }
    }
}

struct ExploreStory: Identifiable {
    let id = UUID()
    let title: String
    let genre: String
    let minutes: Int
    var popularity = 0
    var added = 0
    var has3D = false
    var immersive = false
    let art: AnyShapeStyle
    var glows: [CoverGlow] = []
    var stars = false

    static let featured = ExploreStory(
        title: "The Lighthouse Keeper’s Last Night",
        genre: "Fiction",
        minutes: 12,
        art: AnyShapeStyle(LinearGradient(
            stops: [
                .init(color: Color(hex: 0x39434F), location: 0),
                .init(color: Color(hex: 0x5A6672), location: 0.5),
                .init(color: Color(hex: 0x1F2A33), location: 0.51),
                .init(color: Color(hex: 0x0E161D), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        ))
    )

    static let catalog: [ExploreStory] = [
        ExploreStory(
            title: "Beneath the Kelp Forest", genre: "Nature", minutes: 9,
            popularity: 88, added: 3, has3D: true, immersive: true,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x1F6B6A), Color(hex: 0x0C3A40), Color(hex: 0x061D22)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.5, y: -0.1), radius: 0.9, color: Color(hex: 0xBEF5E8).opacity(0.6))]
        ),
        ExploreStory(
            title: "Letters from the Rose City", genre: "History", minutes: 14,
            popularity: 64, added: 1, has3D: false, immersive: true,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0xE9B88A), Color(hex: 0xC7774B), Color(hex: 0x8A3F26), Color(hex: 0x4E2216)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.75, y: 0.22), radius: 0.12, color: Color(hex: 0xFFE2B0))]
        ),
        ExploreStory(
            title: "The Quiet Orbit", genre: "Space", minutes: 11,
            popularity: 92, added: 5, has3D: true, immersive: true,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x05070F), Color(hex: 0x0B1533), Color(hex: 0x1A2D6B)],
                startPoint: .top, endPoint: .bottom)),
            glows: [
                CoverGlow(center: UnitPoint(x: 0.7, y: 0.7), radius: 0.9, color: Color(red: 0.27, green: 0.43, blue: 1).opacity(0.5)),
                CoverGlow(center: UnitPoint(x: 0.3, y: 0.6), radius: 0.8, color: Color(red: 0.24, green: 0.78, blue: 0.67).opacity(0.28)),
            ],
            stars: true
        ),
        ExploreStory(
            title: "The Clockwork Orchard", genre: "Fiction", minutes: 10,
            popularity: 71, added: 2, has3D: true, immersive: false,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x56642F), Color(hex: 0x2C3A1E), Color(hex: 0x1A2412)],
                startPoint: .topLeading, endPoint: .bottomTrailing)),
            glows: [CoverGlow(center: UnitPoint(x: 0.3, y: 0.3), radius: 0.8, color: Color(hex: 0xFFD68C).opacity(0.65))]
        ),
        ExploreStory(
            title: "Monsoon Market", genre: "Travel", minutes: 8,
            popularity: 57, added: 4, has3D: false, immersive: true,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x3D5A66), Color(hex: 0x2A3F4A), Color(hex: 0x1E2A30)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.5, y: 1), radius: 1.0, color: Color(hex: 0xFFAA50).opacity(0.6))]
        ),
    ]
}

enum ExploreSort: String, CaseIterable {
    case popular = "Popular", newest = "Newest", oldest = "Oldest"
}

/// Explore screen: section rail, voice search, sort/filter menu, genre chips
/// and a featured story beside a grid of story cards.
struct ExploreView: View {

    var onOpenStory: () -> Void

    @Environment(AppModel.self) private var appModel

    enum Section { case explore, library, profile }
    @State private var section = Section.explore

    private var session: ArcGISOnlineSession { appModel.arcGISSession }

    private let genres = ["All", "Fiction", "Nature", "History", "Space", "Travel"]

    @State private var genre = "All"
    @State private var listening = false
    @State private var menuOpen = false
    @State private var sort = ExploreSort.popular
    @State private var only3D = false
    @State private var onlyImmersive = false
    @State private var hovered: String?

    private var hasActiveFilters: Bool { sort != .popular || only3D || onlyImmersive }

    private func matches(_ story: ExploreStory) -> Bool {
        (!only3D || story.has3D) && (!onlyImmersive || story.immersive)
    }

    private var cards: [ExploreStory] {
        ExploreStory.catalog
            .filter { genre == "All" || $0.genre == genre }
            .sorted {
                switch sort {
                case .popular: $0.popularity > $1.popularity
                case .newest: $0.added > $1.added
                case .oldest: $0.added < $1.added
                }
            }
            .prefix(4)
            .map { $0 }
    }

    private func resetFilters() {
        sort = .popular
        only3D = false
        onlyImmersive = false
    }

    var body: some View {
        ZStack {
            WarmBackdrop()

            HStack(alignment: .center, spacing: 24) {
                sectionRail
                mainPanel
            }
            .padding(.leading, 28)
            .padding(.trailing, 40)
            .padding(.vertical, 56)
        }
        .foregroundStyle(.white)
        // Click sound for any tap; simultaneous so buttons still receive it.
        .simultaneousGesture(TapGesture().onEnded { UISounds.shared.tap() })
    }

    // MARK: - Section rail

    private var sectionRail: some View {
        VStack(spacing: 10) {
            railButton("Explore", systemImage: "safari", target: .explore)
            railButton("Library", systemImage: "books.vertical", target: .library)
            railButton("Voices", systemImage: "waveform")
            railButton("Profile", systemImage: "person", target: .profile)
        }
        .padding(10)
        .frame(width: 72)
        .background(panelFill, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
    }

    private func railButton(_ label: String, systemImage: String, target: Section? = nil) -> some View {
        let selected = target != nil && target == section
        return Button {
            if let target { section = target }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
                .frame(width: 52, height: 52)
                .background(selected ? .white.opacity(0.22) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Main panel

    private var mainPanel: some View {
        Group {
            switch section {
            case .explore:
                VStack(alignment: .leading, spacing: 24) {
                    header
                    genreChips.padding(.bottom, 20)
                    grid
                }
            case .library:
                accountPanel(
                    title: "Library",
                    icon: "books.vertical",
                    signedOutHeadline: "Your stories live here",
                    signedOutDetail: "Sign in to open the story maps you’ve authored and the private stories your organization has shared with you.",
                    signedInHeadline: "Nothing here yet",
                    signedInDetail: "Your stories and your organization’s stories will appear here."
                )
            case .profile:
                accountPanel(
                    title: "Profile",
                    icon: "person.crop.circle",
                    signedOutHeadline: "You’re browsing as a guest",
                    signedOutDetail: "Sign in to sync bookmarks and narration progress, and to unlock your organization’s private stories.",
                    signedInHeadline: signedInUsername ?? "Signed in",
                    signedInDetail: "Bookmarks and narration progress sync to your ArcGIS account."
                )
            }
        }
        .padding(.top, 36)
        .padding([.horizontal, .bottom], 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelFill, in: RoundedRectangle(cornerRadius: 48))
        .overlay(RoundedRectangle(cornerRadius: 48).strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 45, y: 40)
        .overlay(alignment: .topTrailing) {
            if menuOpen {
                ZStack(alignment: .topTrailing) {
                    Color.black.opacity(0.001)
                        .onTapGesture { menuOpen = false }
                    filterMenu
                        .padding(.trailing, 44)
                        .padding(.top, 100)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
                }
            }
        }
        .animation(.easeOut(duration: 0.22), value: menuOpen)
    }

    private var header: some View {
        HStack(spacing: 20) {
            Text("Explore")
                .font(.system(size: 44, weight: .regular, design: .serif))
            Spacer()

            Button { listening.toggle() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mic")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.18), in: Circle())
                    if listening {
                        HStack(spacing: 3) {
                            ForEach(0..<5, id: \.self) { i in
                                Capsule().fill(.white).frame(width: 3, height: 22)
                                    .phaseAnimator([0.3, 1.0]) { view, scale in
                                        view.scaleEffect(y: scale)
                                    } animation: { _ in .easeInOut(duration: 0.45).delay(Double(i) * 0.15) }
                            }
                        }
                    }
                    Text(listening ? "Listening…" : "Search by voice")
                        .font(.system(size: 17, weight: .semibold))
                }
                .padding(.leading, 8)
                .padding(.trailing, 22)
                .frame(minWidth: 240, minHeight: 52)
                .background(listening ? .white.opacity(0.26) : .black.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(listening ? 0.85 : 0), lineWidth: 2))
                .shadow(color: Color(red: 1, green: 0.78, blue: 0.55).opacity(listening ? 0.35 : 0), radius: 12)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .hoverEffect()
            .accessibilityLabel("Search by voice")
            .accessibilityAddTraits(listening ? .isSelected : [])

            Button { menuOpen.toggle() } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(menuOpen ? 0.3 : 0.14), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(menuOpen ? 0.85 : 0), lineWidth: 2))
                    .overlay(alignment: .topTrailing) {
                        if hasActiveFilters {
                            Circle()
                                .fill(Color(red: 1, green: 0.773, blue: 0.431))
                                .frame(width: 10, height: 10)
                                .padding(6)
                        }
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .hoverEffect()
            .accessibilityLabel("Sort and filter")
        }
    }

    // MARK: - Sort / filter menu

    private var filterMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            menuHeading("Sort by")
            ForEach(ExploreSort.allCases, id: \.self) { option in
                Button { sort = option } label: {
                    HStack {
                        Text(option.rawValue).font(.system(size: 17, weight: .medium))
                        Spacer()
                        if sort == option { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)) }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(.white.opacity(sort == option ? 0.16 : 0), in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .hoverEffect()
                .accessibilityAddTraits(sort == option ? .isSelected : [])
            }

            Divider().overlay(.white.opacity(0.18)).padding(.horizontal, 12).padding(.vertical, 8)

            menuHeading("Show only")
            toggleRow("Has a 3D object", systemImage: "cube", isOn: $only3D)
            toggleRow("Full immersion", systemImage: "arrow.up.left.and.arrow.down.right", isOn: $onlyImmersive)

            if hasActiveFilters {
                Divider().overlay(.white.opacity(0.18)).padding(.horizontal, 12).padding(.vertical, 8)
                Button(action: resetFilters) {
                    Text("Reset sort and filters")
                        .font(.system(size: 16, weight: .semibold))
                        .underline()
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect()
            }
        }
        .padding(14)
        .frame(width: 340)
        .background {
            RoundedRectangle(cornerRadius: 30)
                .fill(Color(red: 78 / 255, green: 67 / 255, blue: 57 / 255).opacity(0.94))
                .overlay(
                    LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 30))
                )
        }
        .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.white.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 35, y: 30)
    }

    private func menuHeading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    private func toggleRow(_ label: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.12), in: Circle())
                Text(label).font(.system(size: 17, weight: .medium))
                Spacer()
                Capsule()
                    .fill(isOn.wrappedValue ? Color(red: 0.949, green: 0.784, blue: 0.475) : .white.opacity(0.22))
                    .frame(width: 44, height: 26)
                    .overlay(alignment: isOn.wrappedValue ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 20, height: 20)
                            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                            .padding(3)
                    }
                    .animation(.easeOut(duration: 0.2), value: isOn.wrappedValue)
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    private var genreChips: some View {
        HStack(spacing: 12) {
            ForEach(genres, id: \.self) { label in
                let on = label == genre
                Button { genre = label } label: {
                    Text(label)
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 24)
                        .frame(height: 48)
                        .background(.white.opacity(on ? 0.24 : 0.1), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(on ? 0.9 : 0), lineWidth: 2))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .hoverEffect()
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var grid: some View {
        HStack(spacing: 20) {
            featuredCard

            // 2×2 grid of story cards; empty slots keep the layout stable.
            Grid(horizontalSpacing: 20, verticalSpacing: 20) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(0..<2, id: \.self) { col in
                            let index = row * 2 + col
                            if cards.indices.contains(index) {
                                storyCard(cards[index])
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Account panels

    private var signedInUsername: String? {
        if case .signedIn(let name) = session.state { return name }
        return nil
    }

    private func accountPanel(
        title: String, icon: String,
        signedOutHeadline: String, signedOutDetail: String,
        signedInHeadline: String, signedInDetail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 44, weight: .regular, design: .serif))

            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityHidden(true)

                if signedInUsername == nil {
                    Text(signedOutHeadline)
                        .font(.system(size: 32, design: .serif))
                    Text(signedOutDetail)
                        .font(.system(size: 18))
                        .lineSpacing(4)
                        .foregroundStyle(.white.opacity(0.84))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)

                    Button {
                        Task { await session.signIn() }
                    } label: {
                        HStack(spacing: 12) {
                            if session.state == .signingIn {
                                ProgressView().tint(darkInk)
                            } else {
                                Image(systemName: "globe").font(.system(size: 20))
                            }
                            Text(session.state == .signingIn ? "Signing in…" : "Sign in with ArcGIS")
                                .font(.system(size: 19, weight: .semibold))
                        }
                        .foregroundStyle(darkInk)
                        .frame(width: 360, height: 60)
                        .background(Color(red: 0.965, green: 0.945, blue: 0.918), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                    .disabled(session.state == .signingIn)
                    .padding(.top, 14)

                    if case .failed(let message) = session.state {
                        Text(message)
                            .font(.system(size: 15))
                            .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.72))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 480)
                    }
                } else {
                    Text(signedInHeadline)
                        .font(.system(size: 32, design: .serif))
                    Text(signedInDetail)
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.84))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Cards

    private var featuredCard: some View {
        let story = ExploreStory.featured
        return Button(action: onOpenStory) {
            ZStack(alignment: .bottomLeading) {
                CoverArt(story: story)
                LighthouseArt()
                LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 260)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                VStack(alignment: .leading, spacing: 10) {
                    Text("\(story.genre) · \(story.minutes) min".uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.9))
                    Text(story.title)
                        .font(.system(size: 44, design: .serif))
                        .lineSpacing(0)
                        .frame(maxWidth: 460, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill").font(.system(size: 16))
                        Text("Begin story").font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundStyle(darkInk)
                    .padding(.horizontal, 26)
                    .frame(height: 52)
                    .background(Color(red: 0.965, green: 0.945, blue: 0.918), in: Capsule())
                    .padding(.top, 8)
                }
                .padding(32)

                HStack(spacing: 8) {
                    badge("Featured")
                    badge("Full immersion · 3D object")
                }
                .padding(24)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 32))
            .contentShape(RoundedRectangle(cornerRadius: 32))
        }
        .buttonStyle(.plain)
        .modifier(CardHover(id: "featured", radius: 32, hovered: $hovered, enabled: true))
        .accessibilityLabel("Featured: \(story.title). Begin story")
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.38), in: Capsule())
    }

    private func storyCard(_ story: ExploreStory) -> some View {
        Button(action: onOpenStory) {
            ZStack(alignment: .bottomLeading) {
                CoverArt(story: story)
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(story.genre) · \(story.minutes) min".uppercased())
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.92))
                    Text(story.title)
                        .font(.system(size: 26, design: .serif))
                        .multilineTextAlignment(.leading)
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .contentShape(RoundedRectangle(cornerRadius: 28))
        }
        .buttonStyle(.plain)
        .modifier(CardHover(id: story.title, radius: 28, hovered: $hovered, enabled: matches(story)))
        .accessibilityLabel("\(story.title), \(story.genre), \(story.minutes) minutes")
    }

    // MARK: - Style

    private var panelFill: Color {
        Color(red: 104 / 255, green: 90 / 255, blue: 77 / 255).opacity(0.62)
    }

    private var darkInk: Color { Color(red: 0.169, green: 0.141, blue: 0.118) }
}

/// Hover state for cards: lift, warm glow ring, and dimming when a card is
/// excluded by the active filters.
struct CardHover: ViewModifier {
    let id: String
    let radius: CGFloat
    @Binding var hovered: String?
    let enabled: Bool

    private var on: Bool { enabled && hovered == id }

    func body(content: Content) -> some View {
        content
            .overlay {
                if on { HoverEffectOverlay(radius: radius) }
            }
            .scaleEffect(on ? 1.015 : 1)
            .offset(y: on ? -6 : 0)
            .opacity(enabled ? 1 : 0.32)
            .saturation(enabled ? 1 : 0.3)
            .hoverEffect()
            .onHover { inside in
                if inside {
                    if enabled && hovered != id {
                        UISounds.shared.chime()
                        hovered = id
                    }
                } else if hovered == id { hovered = nil }
            }
            .animation(.easeOut(duration: 0.3), value: on)
            .animation(.easeOut(duration: 0.3), value: enabled)
    }
}

/// Warm glow ring, a rotating amber highlight that sweeps the border, and
/// sparks drifting off the card edges — shown while a card is hovered.
struct HoverEffectOverlay: View {
    let radius: CGFloat

    private struct Spark { let x, y, degrees, size, delay: Double }

    // Edge anchors as fractions of the card, matching the design.
    private static let sparks: [Spark] = [
        .init(x: 0.18, y: 0, degrees: -6, size: 5, delay: 0.0), .init(x: 0.47, y: 0, degrees: 8, size: 4, delay: 0.9),
        .init(x: 0.79, y: 0, degrees: -10, size: 6, delay: 1.6), .init(x: 1, y: 0, degrees: 45, size: 5, delay: 0.4),
        .init(x: 1, y: 0.28, degrees: 88, size: 4, delay: 1.2), .init(x: 1, y: 0.67, degrees: 96, size: 6, delay: 2.1),
        .init(x: 0.72, y: 1, degrees: 176, size: 5, delay: 0.6), .init(x: 0.33, y: 1, degrees: 188, size: 4, delay: 1.8),
        .init(x: 0, y: 1, degrees: -135, size: 5, delay: 1.0), .init(x: 0, y: 0.62, degrees: -92, size: 6, delay: 0.2),
        .init(x: 0, y: 0.24, degrees: -84, size: 4, delay: 1.4),
    ]
    private static let sparkDuration = 2.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius + 4)
        ZStack {
            shape
                .strokeBorder(Color(red: 1, green: 0.941, blue: 0.839).opacity(0.9), lineWidth: 2)
                .shadow(color: Color(red: 1, green: 0.769, blue: 0.47).opacity(0.45), radius: 14)
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                shape
                    .strokeBorder(
                        AngularGradient(
                            stops: [
                                .init(color: Color(red: 1, green: 0.667, blue: 0.314).opacity(0), location: 0),
                                .init(color: Color(red: 1, green: 0.667, blue: 0.314).opacity(0), location: 0.583),
                                .init(color: Color(red: 1, green: 0.706, blue: 0.361), location: 0.806),
                                .init(color: Color(red: 1, green: 0.953, blue: 0.839), location: 0.93),
                                .init(color: Color(red: 1, green: 0.667, blue: 0.314).opacity(0), location: 1),
                            ],
                            center: .center,
                            angle: .degrees((t.truncatingRemainder(dividingBy: 3.6) / 3.6) * 360)
                        ),
                        lineWidth: 4)
                sparkLayer(t)
            }
        }
        .padding(-5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func sparkLayer(_ t: TimeInterval) -> some View {
        GeometryReader { geo in
            ForEach(Self.sparks.indices, id: \.self) { i in
                let p = Self.sparks[i]
                let phase = ((t - p.delay).truncatingRemainder(dividingBy: Self.sparkDuration) + Self.sparkDuration)
                    .truncatingRemainder(dividingBy: Self.sparkDuration) / Self.sparkDuration
                // 0→18% fade/grow in, then fade/shrink out while drifting outward.
                let opacity = phase < 0.18 ? phase / 0.18 : 1 - (phase - 0.18) / 0.82
                let scale = phase < 0.18 ? 0.4 + 0.6 * phase / 0.18 : 1 - 0.8 * (phase - 0.18) / 0.82
                let drift = phase < 0.18 ? 4 * phase / 0.18 : 4 + 22 * (phase - 0.18) / 0.82
                let angle = Angle.degrees(p.degrees).radians
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 1, green: 0.969, blue: 0.894), Color(red: 1, green: 0.773, blue: 0.431), Color(red: 1, green: 0.588, blue: 0.196).opacity(0)],
                        center: .center, startRadius: 0, endRadius: p.size * 0.72))
                    .frame(width: p.size * 2, height: p.size * 2)
                    .scaleEffect(scale)
                    .opacity(reduceMotion ? 0 : opacity)
                    .position(
                        x: geo.size.width * p.x + 5 + sin(angle) * drift,
                        y: geo.size.height * p.y + 5 - cos(angle) * drift)
            }
        }
        .padding(5)
    }
}

/// Hover chime and click sounds. The chime is bundled; the click is
/// synthesized (a short filtered noise burst over a falling sine).
@MainActor
final class UISounds {
    static let shared = UISounds()

    private var chimePlayer: AVAudioPlayer?
    private var clickPlayer: AVAudioPlayer?

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        if let url = Bundle.main.url(forResource: "hover-chime", withExtension: "mp3") {
            chimePlayer = try? AVAudioPlayer(contentsOf: url)
            chimePlayer?.volume = 0.1
            chimePlayer?.prepareToPlay()
        }
        clickPlayer = try? AVAudioPlayer(data: Self.clickWAV())
        clickPlayer?.volume = 0.5
        clickPlayer?.prepareToPlay()
    }

    func chime() {
        guard let chimePlayer else { return }
        chimePlayer.currentTime = 0
        chimePlayer.play()
    }

    func tap() {
        guard let clickPlayer else { return }
        clickPlayer.currentTime = 0
        clickPlayer.play()
    }

    private static func clickWAV() -> Data {
        let rate = 44100.0
        let count = Int(rate * 0.1)
        var samples = [Int16](repeating: 0, count: count)
        var phase = 0.0
        var lp = 0.0
        for i in 0..<count {
            let t = Double(i) / rate
            // Falling sine 420 → 180 Hz over 60 ms with a quick attack.
            let f = 420 * pow(180.0 / 420.0, min(t / 0.06, 1))
            phase += 2 * .pi * f / rate
            let env = t < 0.004 ? t / 0.004 : exp(-(t - 0.004) * 45)
            var v = sin(phase) * 0.08 * env
            // Noise burst (30 ms, cubic decay), roughly band-limited.
            if i < Int(rate * 0.03) {
                let n = Double.random(in: -1...1) * pow(1 - Double(i) / (rate * 0.03), 3)
                lp += 0.6 * (n - lp)
                v += (n - lp) * 0.09
            }
            samples[i] = Int16(max(-1, min(1, v * 0.5)) * Double(Int16.max))
        }
        var data = Data()
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append("RIFF".data(using: .ascii)!); put(UInt32(36 + count * 2))
        data.append("WAVEfmt ".data(using: .ascii)!); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(rate)); put(UInt32(rate) * 2); put(UInt16(2)); put(UInt16(16))
        data.append("data".data(using: .ascii)!); put(UInt32(count * 2))
        for s in samples { put(s) }
        return data
    }
}

/// Lighthouse silhouette for the featured card, drawn in the design's
/// 600×520 coordinate space and scaled to fit.
struct LighthouseArt: View {
    var body: some View {
        Canvas { context, size in
            let s = max(size.width / 600, size.height / 520)
            var ctx = context
            ctx.translateBy(x: min(0, size.width - 600 * s), y: 0)
            ctx.scaleBy(x: s, y: s)

            // Sun glow
            ctx.fill(
                Path(ellipseIn: CGRect(x: 432 - 96 + 0, y: 190 - 96 - 36, width: 192, height: 192)),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 1, green: 0.925, blue: 0.745).opacity(0.6), .clear]),
                    center: CGPoint(x: 432, y: 106), startRadius: 0, endRadius: 96)
            )

            // Light beam
            var beam = Path()
            beam.addLines([CGPoint(x: 440, y: 190), CGPoint(x: 600, y: 40), CGPoint(x: 600, y: 210)])
            beam.closeSubpath()
            ctx.fill(beam, with: .color(Color(red: 1, green: 0.933, blue: 0.784).opacity(0.18)))

            // Headland
            var land = Path()
            land.move(to: CGPoint(x: 300, y: 300))
            land.addCurve(to: CGPoint(x: 470, y: 262), control1: CGPoint(x: 360, y: 260), control2: CGPoint(x: 420, y: 250))
            land.addLine(to: CGPoint(x: 600, y: 272))
            land.addLine(to: CGPoint(x: 600, y: 520))
            land.addLine(to: CGPoint(x: 250, y: 520))
            land.closeSubpath()
            ctx.fill(land, with: .color(Color(red: 0.078, green: 0.106, blue: 0.129)))

            // Tower
            let red = Color(red: 0.643, green: 0.208, blue: 0.173)
            ctx.fill(Path(CGRect(x: 422, y: 190, width: 30, height: 80)), with: .color(Color(red: 0.914, green: 0.890, blue: 0.847)))
            ctx.fill(Path(CGRect(x: 422, y: 214, width: 30, height: 12)), with: .color(red))
            ctx.fill(Path(CGRect(x: 422, y: 244, width: 30, height: 12)), with: .color(red))
            let dark = Color(red: 0.165, green: 0.184, blue: 0.208)
            ctx.fill(Path(roundedRect: CGRect(x: 418, y: 178, width: 38, height: 14), cornerRadius: 3), with: .color(dark))
            ctx.fill(Path(ellipseIn: CGRect(x: 428, y: 161, width: 18, height: 18)), with: .color(Color(red: 1, green: 0.914, blue: 0.722)))
            var cap = Path()
            cap.addLines([CGPoint(x: 425, y: 164), CGPoint(x: 437, y: 150), CGPoint(x: 449, y: 164)])
            cap.closeSubpath()
            ctx.fill(cap, with: .color(dark))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension Color {
    /// 0xRRGGBB convenience.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

#Preview(windowStyle: .automatic) {
    ExploreView(onOpenStory: {})
        .environment(AppModel())
}
