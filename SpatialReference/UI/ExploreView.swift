//
//  ExploreView.swift
//  SpatialReference
//

import SwiftUI

/// Placeholder catalog entry for the Explore grid. Cover art is drawn from
/// gradients until stories carry real thumbnails.
struct ExploreStory: Identifiable {
    let id = UUID()
    let title: String
    let genre: String
    let minutes: Int
    let art: AnyShapeStyle

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
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x1F6B6A), Color(hex: 0x0C3A40), Color(hex: 0x061D22)],
                startPoint: .top, endPoint: .bottom))
        ),
        ExploreStory(
            title: "Letters from the Rose City", genre: "History", minutes: 14,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0xE9B88A), Color(hex: 0xC7774B), Color(hex: 0x8A3F26), Color(hex: 0x4E2216)],
                startPoint: .top, endPoint: .bottom))
        ),
        ExploreStory(
            title: "The Quiet Orbit", genre: "Space", minutes: 11,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x05070F), Color(hex: 0x0B1533), Color(hex: 0x1A2D6B)],
                startPoint: .top, endPoint: .bottom))
        ),
        ExploreStory(
            title: "The Clockwork Orchard", genre: "Fiction", minutes: 10,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x56642F), Color(hex: 0x2C3A1E), Color(hex: 0x1A2412)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        ),
        ExploreStory(
            title: "Monsoon Market", genre: "Travel", minutes: 8,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x3D5A66), Color(hex: 0x2A3F4A), Color(hex: 0x1E2A30)],
                startPoint: .top, endPoint: .bottom))
        ),
    ]
}

/// Explore screen: section rail, search, genre chips and a featured story
/// beside a grid of story cards.
struct ExploreView: View {

    var onOpenStory: () -> Void

    @Environment(AppModel.self) private var appModel

    enum Section { case explore, library, profile }
    @State private var section = Section.explore

    private var session: ArcGISOnlineSession { appModel.arcGISSession }

    private let genres = ["All", "Fiction", "Nature", "History", "Space", "Travel"]

    @State private var genre = "All"
    @State private var query = ""

    private var cards: [ExploreStory] {
        ExploreStory.catalog
            .filter { genre == "All" || $0.genre == genre }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.genre.localizedCaseInsensitiveContains(query) }
            .prefix(4)
            .map { $0 }
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
                    genreChips
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
    }

    private var header: some View {
        HStack(spacing: 20) {
            Text("Explore")
                .font(.system(size: 44, weight: .regular, design: .serif))
            Spacer()

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.85))
                TextField("Search stories, places, voices", text: $query, prompt: Text("Search stories, places, voices").foregroundStyle(.white.opacity(0.7)))
                    .font(.system(size: 17))
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 20)
            .frame(width: 360, height: 52)
            .background(.black.opacity(0.18), in: Capsule())

            Button {} label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.14), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .hoverEffect()
            .accessibilityLabel("More")
        }
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
                Rectangle().fill(story.art)
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
        .hoverEffect()
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
                Rectangle().fill(story.art)
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
        .hoverEffect()
        .accessibilityLabel("\(story.title), \(story.genre), \(story.minutes) minutes")
    }

    // MARK: - Style

    private var panelFill: Color {
        Color(red: 104 / 255, green: 90 / 255, blue: 77 / 255).opacity(0.62)
    }

    private var darkInk: Color { Color(red: 0.169, green: 0.141, blue: 0.118) }
}

/// Lighthouse silhouette for the featured card, drawn in the design's
/// 600×520 coordinate space and scaled to fit.
struct LighthouseArt: View {
    var body: some View {
        Canvas { context, size in
            let s = max(size.width / 600, size.height / 520)
            var ctx = context
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
