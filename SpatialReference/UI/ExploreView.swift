//
//  ExploreView.swift
//  SpatialReference
//

import AVFoundation
import SwiftUI

/// Soft radial highlight layered over a cover gradient. Center and radius
/// are fractions of the card (radius relative to the card's width).
struct CoverGlow {
    let center: UnitPoint
    let radius: CGFloat
    let color: Color
    var solid = false   // hard-edged disc instead of a fading glow
}

/// Cover art: gradient + glows (+ stars for the space story). Glows and stars
/// are drawn in a Canvas so they never influence layout.
struct CoverArt: View {
    let art: AnyShapeStyle
    var glows: [CoverGlow] = []
    var stars = false

    init(art: AnyShapeStyle, glows: [CoverGlow] = [], stars: Bool = false) {
        self.art = art
        self.glows = glows
        self.stars = stars
    }

    init(story: ExploreStory) {
        self.init(art: story.art, glows: story.glows, stars: story.stars)
    }

    var body: some View {
        Rectangle().fill(art)
            .overlay {
                Canvas { ctx, size in
                    for g in glows {
                        let center = CGPoint(x: size.width * g.center.x, y: size.height * g.center.y)
                        let r = g.radius * size.width
                        if g.solid {
                            ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(g.color))
                            continue
                        }
                        ctx.fill(
                            Path(CGRect(origin: .zero, size: size)),
                            with: .radialGradient(
                                Gradient(colors: [g.color, g.color.opacity(0)]),
                                center: center, startRadius: 0, endRadius: r))
                    }
                    if stars {
                        for (x, y, d) in [(0.20, 0.30, 3.2), (0.70, 0.58, 2.4), (0.42, 0.78, 2.8), (0.86, 0.20, 2.4), (0.56, 0.14, 2.4), (0.12, 0.62, 2.0)] {
                            ctx.fill(Path(ellipseIn: CGRect(x: size.width * x - d / 2, y: size.height * y - d / 2, width: d, height: d)), with: .color(.white))
                        }
                    }
                }
                .allowsHitTesting(false)
            }
    }
}

/// Placeholder catalog entry for the Explore screen. Cover art is drawn from
/// gradients until stories carry real thumbnails.
struct ExploreStory: Identifiable {
    let id = UUID()
    let title: String
    let genre: String
    let minutes: Int
    var summary = ""
    var author = "Esri StoryMaps"
    var popularity = 0
    var added = 0
    var has3D = false
    var immersive = false
    var narrated = false
    var images = 0
    var access = StoryAccess.public
    var tag: CardTag?
    let art: AnyShapeStyle
    var glows: [CoverGlow] = []
    var stars = false

    /// What the story offers, shown as the icon list on its card.
    var features: [CardFeature] {
        var features: [CardFeature] = []
        if immersive { features.append(CardFeature(systemImage: "visionpro", label: "Immersive")) }
        if has3D { features.append(CardFeature(systemImage: "cube", label: "3D Model")) }
        if images > 0 {
            features.append(CardFeature(systemImage: "photo.on.rectangle", label: "Gallery"))
            features.append(CardFeature(systemImage: "photo.stack", label: "\(images) Images"))
        }
        if narrated { features.append(CardFeature(systemImage: "waveform", label: "Audio Guide")) }
        features.append(CardFeature(systemImage: "clock", label: "\(minutes) min"))
        return features
    }

    static let featured = ExploreStory(
        title: "The Lighthouse Keeper’s Last Night",
        genre: "Fiction",
        minutes: 12,
        summary: "On the final night before the lamp goes automatic, the keeper climbs the tower one last time and the coastline tells its own story.",
        has3D: true,
        immersive: true,
        narrated: true,
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
            popularity: 88, added: 3, has3D: true, immersive: true, narrated: true, images: 12, tag: .new,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x1F6B6A), Color(hex: 0x0C3A40), Color(hex: 0x061D22)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.5, y: -0.1), radius: 0.9, color: Color(hex: 0xBEF5E8).opacity(0.6))]
        ),
        ExploreStory(
            title: "Letters from the Rose City", genre: "History", minutes: 14,
            popularity: 64, added: 1, immersive: true, narrated: true, images: 8, access: .organization, tag: .updated,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0xE9B88A), Color(hex: 0xC7774B), Color(hex: 0x8A3F26), Color(hex: 0x4E2216)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.75, y: 0.22), radius: 0.07, color: Color(hex: 0xFFE2B0), solid: true)]
        ),
        ExploreStory(
            title: "The Quiet Orbit", genre: "Space", minutes: 11,
            popularity: 92, added: 5, has3D: true, immersive: true, narrated: true, tag: .new,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x05070F), Color(hex: 0x05070F)],
                startPoint: .top, endPoint: .bottom)),
            glows: [
                CoverGlow(center: UnitPoint(x: 0.7, y: 0.7), radius: 0.8, color: Color(red: 0.27, green: 0.43, blue: 1).opacity(0.5)),
                CoverGlow(center: UnitPoint(x: 0.3, y: 0.6), radius: 0.6, color: Color(red: 0.24, green: 0.78, blue: 0.67).opacity(0.28)),
            ],
            stars: true
        ),
        ExploreStory(
            title: "The Clockwork Orchard", genre: "Fiction", minutes: 10,
            popularity: 71, added: 2, has3D: true, access: .organization,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x56642F), Color(hex: 0x2C3A1E), Color(hex: 0x1A2412)],
                startPoint: .topLeading, endPoint: .bottomTrailing)),
            glows: [CoverGlow(center: UnitPoint(x: 0.3, y: 0.3), radius: 0.8, color: Color(hex: 0xFFD68C).opacity(0.65))]
        ),
        ExploreStory(
            title: "Monsoon Market", genre: "Travel", minutes: 8,
            popularity: 57, added: 4, immersive: true, narrated: true, images: 20, tag: .updated,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x3D5A66), Color(hex: 0x2A3F4A), Color(hex: 0x1E2A30)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.5, y: 1), radius: 1.0, color: Color(hex: 0xFFAA50).opacity(0.6))]
        ),
        ExploreStory(
            title: "Glacier Lines", genre: "Nature", minutes: 7,
            popularity: 49, added: 6, immersive: true, images: 14, tag: .new,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0xCFE3EA), Color(hex: 0x7FA6B8), Color(hex: 0x2E4A5C)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.2, y: 0.1), radius: 0.7, color: .white.opacity(0.5))]
        ),
        ExploreStory(
            title: "Night Shift at the Observatory", genre: "Space", minutes: 13,
            popularity: 76, added: 0, has3D: true, narrated: true, images: 4, access: .organization,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x1B1033), Color(hex: 0x0B0716)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.5, y: 1.1), radius: 0.9, color: Color(hex: 0xB070FF).opacity(0.45))],
            stars: true
        ),
    ]
}

enum ExploreSort: String, CaseIterable {
    case popular = "Popular", newest = "Newest", oldest = "Oldest"
}

/// Top-bar categories. Each is a kind of experience a story offers rather
/// than a subject, so membership comes straight from the story's features.
enum ExploreCategory: String, CaseIterable, Identifiable {
    case featured, immersive, scenes, narrated, galleries, new

    var id: Self { self }

    var title: String {
        switch self {
        case .featured: "Featured"
        case .immersive: "Immersive"
        case .scenes: "3D Scenes"
        case .narrated: "Narrated"
        case .galleries: "Galleries"
        case .new: "New"
        }
    }

    var systemImage: String {
        switch self {
        case .featured: "star.fill"
        case .immersive: "visionpro"
        case .scenes: "cube"
        case .narrated: "waveform"
        case .galleries: "photo.on.rectangle"
        case .new: "sparkles"
        }
    }

    /// Categories shown as rows beneath the Featured hero.
    static var rows: [ExploreCategory] { allCases.filter { $0 != .featured } }

    func includes(_ story: ExploreStory) -> Bool {
        switch self {
        case .featured: true
        case .immersive: story.immersive
        case .scenes: story.has3D
        case .narrated: story.narrated
        case .galleries: story.images > 0
        case .new: story.tag != nil
        }
    }
}

/// Explore screen: a top category bar ornament (Featured, Immersive, 3D
/// Scenes, …), a Featured page with a hero story above a row per category,
/// and a card grid for every other category.
struct ExploreView: View {

    var onOpenStory: () -> Void

    @Environment(AppModel.self) private var appModel

    enum Section { case explore, exhibitions, environments, library, search, settings }
    // Kept on the app model so returning from a story lands on the tab
    // (and category) it was opened from, not back on Explore.
    private var section: Section { appModel.exploreSection }
    private var category: ExploreCategory {
        get { appModel.exploreCategory }
        nonmutating set { appModel.exploreCategory = newValue }
    }

    private var session: ArcGISOnlineSession { appModel.arcGISSession }

    @State private var query = ""
    @State private var showingDetails = false
    @State private var sort = ExploreSort.popular
    @State private var hovered: String?

    private func stories(in category: ExploreCategory) -> [ExploreStory] {
        ExploreStory.catalog
            .filter(category.includes)
            .sorted {
                switch sort {
                case .popular: $0.popularity > $1.popularity
                case .newest: $0.added > $1.added
                case .oldest: $0.added < $1.added
                }
            }
    }

    var body: some View {
        // On visionOS a TabView renders as a leading ornament that expands to
        // show tab names while the user looks at it and collapses when they
        // look away. The system drives this, as apps never receive gaze data.
        TabView(selection: Bindable(appModel).exploreSection) {
            Tab("Explore", systemImage: "safari", value: Section.explore) {
                sectionPage(.explore)
            }
            Tab("Exhibitions", systemImage: "building.columns", value: Section.exhibitions) {
                sectionPage(.exhibitions)
            }
            Tab("Environments", systemImage: "mountain.2", value: Section.environments) {
                sectionPage(.environments)
            }
            Tab("Library", systemImage: "books.vertical", value: Section.library) {
                sectionPage(.library)
            }
            Tab("Search", systemImage: "magnifyingglass", value: Section.search) {
                sectionPage(.search)
            }
            Tab("Settings", systemImage: "gearshape", value: Section.settings) {
                sectionPage(.settings)
            }
        }
        .background { WarmBackdrop() }
        .ornament(
            visibility: section == .explore ? .visible : .hidden,
            attachmentAnchor: .scene(.top),
            contentAlignment: .bottom
        ) {
            categoryBar
        }
        // Click sound for any tap; simultaneous so buttons still receive it.
        .simultaneousGesture(TapGesture().onEnded { UISounds.shared.tap() })
        .onAppear { UISounds.shared.warmUp() }
        // Load the user's own (including private) StoryMaps once signed in.
        .task(id: signedInUsername) {
            if signedInUsername != nil { await appModel.refreshLibrary() }
        }
    }

    private func sectionPage(_ section: Section) -> some View {
        mainPanel(for: section)
            .foregroundStyle(.white)
    }

    // MARK: - Category bar

    private var categoryBar: some View {
        HStack(spacing: 8) {
            ForEach(ExploreCategory.allCases) { item in
                let on = item == category
                Button { category = item } label: {
                    Label(item.title, systemImage: item.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(on ? .black : .white)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(on ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.08)), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .hoverEffect()
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .foregroundStyle(.white)
        .padding(8)
        .glassBackgroundEffect(in: Capsule())
        .simultaneousGesture(TapGesture().onEnded { UISounds.shared.tap() })
        .padding(.bottom, 24)
    }

    // MARK: - Main panel

    @ViewBuilder
    private func mainPanel(for section: Section) -> some View {
        switch section {
        case .explore:
            Group {
                if category == .featured {
                    featuredPage
                } else {
                    categoryPage(category)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .exhibitions:
            ExhibitionsView(hovered: $hovered)
        case .environments:
            EnvironmentsView()
        case .search:
            searchPage
        case .settings:
            SettingsView()
        case .library where signedInUsername != nil:
            padded(libraryPanel)
        case .library:
            padded(accountPanel(
                title: "Library",
                icon: "books.vertical",
                signedOutHeadline: "Your stories live here",
                signedOutDetail: "Sign in to open the story maps you’ve authored and the private stories your organization has shared with you.",
                signedInHeadline: "Nothing here yet",
                signedInDetail: "Your stories and your organization’s stories will appear here."
            ))
        }
    }

    // Content sits directly on the window's own surface, with no inset card,
    // so the window doesn't read as a second window nested inside the first.
    private func padded(_ content: some View) -> some View {
        content
            .padding(.top, 48)
            .padding([.horizontal, .bottom], 56)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Featured

    private var featuredPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                hero(.featured)

                ForEach(ExploreCategory.rows) { row in
                    let items = stories(in: row)
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Button { category = row } label: {
                                HStack(spacing: 8) {
                                    Label(row.title.uppercased(), systemImage: row.systemImage)
                                        .tracking(1.6)
                                    Image(systemName: "chevron.right")
                                }
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color(hex: 0xF0A050))
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .hoverEffect()
                            .padding(.horizontal, 56)
                            .accessibilityHint("Shows all \(row.title) stories")

                            // Vertical padding leaves room for the hover lift
                            // and glow, which the scroll view would clip.
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 24) {
                                    ForEach(items) { exploreCard($0).frame(width: 290) }
                                }
                                .padding(.horizontal, 56)
                                .padding(.vertical, 16)
                            }
                            .scrollIndicators(.hidden)
                        }
                    }
                }
            }
            .padding(.bottom, 40)
        }
    }

    /// Full-bleed banner for the featured story: cover art fading into a
    /// dark scrim, title with a format pill, summary, then actions and
    /// metadata on one line.
    private func hero(_ story: ExploreStory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Text(story.title)
                    .font(.system(size: 44, weight: .bold))
                Text("Full immersion")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 2))
            }
            Text(story.summary)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .frame(maxWidth: 760, alignment: .leading)

            HStack(spacing: 14) {
                Button(action: onOpenStory) {
                    Label("Begin", systemImage: "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(darkInk)
                        .padding(.horizontal, 26)
                        .frame(height: 50)
                        .background(.white, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .hoverEffect()

                Button { showingDetails = true } label: {
                    Label("Details", systemImage: "info.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .padding(.horizontal, 22)
                        .frame(height: 50)
                        .background(.white.opacity(0.18), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .hoverEffect()
                .popover(isPresented: $showingDetails) { details(story) }

                Text("\(story.minutes) min  •  \(story.genre)  •  \(story.author)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.leading, 8)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 56)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .frame(height: 440)
        // Art layers sit in the background so their size can't change the
        // banner's height and push the action row out of view.
        .background {
            ZStack {
                CoverArt(story: story)
                LighthouseArt()
                    .frame(width: 760, height: 620)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                LinearGradient(colors: [.black.opacity(0.8), .black.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            }
        }
        .clipped()
    }

    private func details(_ story: ExploreStory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(story.title).font(.system(size: 24, weight: .bold))
            Text(story.summary)
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 14, lineSpacing: 8) {
                ForEach(story.features, id: \.self) { feature in
                    Label(feature.label, systemImage: feature.systemImage)
                }
            }
            .font(.system(size: 15, weight: .medium))
        }
        .padding(28)
        .frame(width: 420)
    }

    // MARK: - Category pages

    private func categoryPage(_ category: ExploreCategory) -> some View {
        let items = stories(in: category)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(category.title)
                        .font(.system(size: 40, weight: .bold))
                    Text(items.count == 1 ? "1 story" : "\(items.count) stories")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Menu {
                        Picker("Sort by", selection: $sort) {
                            ForEach(ExploreSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Label("Sort: \(sort.rawValue)", systemImage: "arrow.up.arrow.down")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .padding(.horizontal, 16)

                if items.isEmpty {
                    Text("No stories in \(category.title) yet.")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 28, alignment: .top)],
                        spacing: 28
                    ) {
                        ForEach(items) { exploreCard($0) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .padding(.top, 40)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Search

    private var searchWords: [Substring] { query.split(whereSeparator: \.isWhitespace) }

    private func matches(_ fields: String...) -> Bool {
        let text = fields.joined(separator: " ")
        return searchWords.allSatisfy { text.localizedCaseInsensitiveContains($0) }
    }

    /// Every catalog story whose title, genre, summary or author contains
    /// each word of the query.
    private var searchResults: [ExploreStory] {
        guard !searchWords.isEmpty else { return [] }
        return ([ExploreStory.featured] + ExploreStory.catalog).filter {
            matches($0.title, $0.genre, $0.summary, $0.author)
        }
    }

    /// The signed-in user's own StoryMaps whose title or summary match.
    private var libraryResults: [ArcGISOnlineSession.StoryMapItem] {
        guard !searchWords.isEmpty, signedInUsername != nil else { return [] }
        return appModel.libraryItems.filter { matches($0.title, $0.summary) }
    }

    private var searchPage: some View {
        let results = searchResults
        let library = libraryResults
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Search")
                    .font(.system(size: 40, weight: .bold))
                    .padding(.horizontal, 16)

                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.7))
                        .accessibilityHidden(true)
                    TextField("Stories, genres, authors", text: $query)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .font(.system(size: 19))
                .padding(.horizontal, 22)
                .frame(height: 56)
                .background(.white.opacity(0.08), in: Capsule())
                .padding(.horizontal, 16)

                if searchWords.isEmpty {
                    Text(signedInUsername == nil
                         ? "Find stories by title, genre or author."
                         : "Find stories by title, genre or author, including your own library.")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if results.isEmpty && library.isEmpty {
                    Text("No stories match “\(query)”.")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    if !library.isEmpty {
                        if let error = appModel.openStoryError {
                            Text(error)
                                .font(.system(size: 15))
                                .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.72))
                                .padding(.horizontal, 16)
                        }
                        searchSection("Your Library", count: library.count) {
                            ForEach(library) { libraryCard($0) }
                        }
                    }
                    if !results.isEmpty {
                        searchSection("Explore", count: results.count) {
                            ForEach(results) { exploreCard($0) }
                        }
                    }
                }
            }
            .padding(.top, 40)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    private func searchSection(_ title: String, count: Int, @ViewBuilder cards: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title.uppercased())
                    .tracking(1.6)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0xF0A050))
                Text(count == 1 ? "1 story" : "\(count) stories")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 28, alignment: .top)],
                spacing: 28
            ) {
                cards()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    private func exploreCard(_ story: ExploreStory) -> some View {
        Button(action: onOpenStory) {
            StoryCard(title: story.title, tag: story.tag, badge: story.access.badge, features: story.features) {
                CoverArt(story: story)
            }
        }
        .buttonStyle(.plain)
        .modifier(CardHover(id: story.title, radius: StoryCardMetrics.radius, hovered: $hovered, enabled: true))
        .accessibilityLabel("\(story.title), \(story.genre), \(story.minutes) minutes")
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

    // MARK: - Library

    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Library")
                    .font(.system(size: 44, weight: .regular, design: .serif))
                Spacer()
                Button {
                    Task { await appModel.refreshLibrary() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.14), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .hoverEffect()
                .disabled(appModel.libraryState == .loading)
                .accessibilityLabel("Refresh library")
            }

            if let error = appModel.openStoryError {
                Text(error)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.72))
            }

            Group {
                if case .failed(let message) = appModel.libraryState {
                    VStack(spacing: 12) {
                        Label("Couldn’t load your stories", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 22, weight: .semibold))
                        Text(message)
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.84))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 480)
                    }
                } else if appModel.libraryItems.isEmpty && appModel.libraryState != .loaded {
                    ProgressView("Loading your stories…")
                } else if appModel.libraryItems.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 48, weight: .light))
                        Text("Nothing here yet").font(.system(size: 32, design: .serif))
                        Text("Story maps you author in ArcGIS StoryMaps will appear here.")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.84))
                    }
                } else {
                    ScrollView {
                        // Generous gaps and edge padding leave room for the
                        // hover lift and glow, which the scroll view would
                        // otherwise clip or crowd into neighbouring tiles.
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 32, alignment: .top)],
                            spacing: 32
                        ) {
                            ForEach(appModel.libraryItems) { libraryCard($0) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func libraryCard(_ item: ArcGISOnlineSession.StoryMapItem) -> some View {
        let opening = appModel.openingStoryID == item.id
        return Button {
            Task {
                if await appModel.openLibraryStory(itemID: item.id) { onOpenStory() }
            }
        } label: {
            StoryCard(
                title: item.title,
                tag: isRecent(item.modified) ? .updated : nil,
                badge: StoryAccess(arcGIS: item.access).badge,
                features: libraryFeatures(item)
            ) {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x3D5A66), Color(hex: 0x1E2A30)], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        if let url = item.thumbnailURL {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "map")
                                    .font(.system(size: 40, weight: .light))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        } else {
                            Image(systemName: "map")
                                .font(.system(size: 40, weight: .light))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
            }
            .overlay {
                if opening {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: StoryCardMetrics.radius))
                }
            }
        }
        .buttonStyle(.plain)
        .modifier(CardHover(id: item.id, radius: StoryCardMetrics.radius, hovered: $hovered, enabled: true))
        .disabled(appModel.openingStoryID != nil)
        .accessibilityLabel("\(item.title), \(item.access) story map")
    }

    private func libraryFeatures(_ item: ArcGISOnlineSession.StoryMapItem) -> [CardFeature] {
        var features = [CardFeature(systemImage: "map", label: "Story map")]
        if let modified = item.modified {
            features.append(CardFeature(systemImage: "calendar", label: modified.formatted(date: .abbreviated, time: .omitted)))
        }
        return features
    }

    /// Edited within the last week, which earns the card an "Updated" tag.
    private func isRecent(_ date: Date?) -> Bool {
        guard let date else { return false }
        return date > Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
    }

    // MARK: - Style

    private var darkInk: Color { Color(red: 0.169, green: 0.141, blue: 0.118) }
}

/// Hover treatment for cards: lift, warm glow ring with a rotating highlight
/// and sparks, and dimming when a card is excluded by the active filters.
///
/// The visuals use system hover effects (grouped), so they respond to eye
/// gaze on device — `onHover` isn't delivered for gaze on visionOS. `onHover`
/// is kept only to trigger the chime when a pointer hovers.
struct CardHover: ViewModifier {
    let id: String
    let radius: CGFloat
    @Binding var hovered: String?
    let enabled: Bool

    func body(content: Content) -> some View {
        content
            .hoverEffect(isEnabled: enabled) { effect, isActive, _ in
                effect.animation(.easeOut(duration: 0.35)) {
                    $0.scaleEffect(isActive ? 1.015 : 1)
                        .offset(y: isActive ? -6 : 0)
                }
            }
            .overlay {
                HoverEffectOverlay(radius: radius)
                    .hoverEffect(isEnabled: enabled) { effect, isActive, _ in
                        effect.animation(.easeOut(duration: 0.35)) {
                            $0.opacity(isActive ? 1 : 0)
                                .scaleEffect(isActive ? 1.015 : 1)
                                .offset(y: isActive ? -6 : 0)
                        }
                    }
            }
            .hoverEffectGroup()
            .opacity(enabled ? 1 : 0.32)
            .saturation(enabled ? 1 : 0.3)
            .shadow(color: .black.opacity(0.18), radius: 12, y: 10)
            .onHover { inside in
                if inside {
                    if enabled && hovered != id {
                        UISounds.shared.chime()
                        hovered = id
                    }
                } else if hovered == id { hovered = nil }
            }
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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius + 4)
        ZStack {
            // Inset warm haze along the card's inner edge.
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(Color(red: 1, green: 0.824, blue: 0.588).opacity(0.25), lineWidth: 18)
                .blur(radius: 9)
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .padding(5)
            shape
                .strokeBorder(Color(red: 1, green: 0.941, blue: 0.839).opacity(0.9), lineWidth: 2)
                .shadow(color: Color(red: 1, green: 0.769, blue: 0.47).opacity(0.45), radius: 14)
            // Paused off-screen: submitting GPU work while backgrounded (e.g. during
            // the sign-in web sheet) makes Metal log "Insufficient Permission".
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
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
///
/// AVAudioPlayer's prepare/play can activate the audio session synchronously,
/// so all player work happens on a private serial queue, off the main thread.
final class UISounds: @unchecked Sendable {
    static let shared = UISounds()

    private let queue = DispatchQueue(label: "UISounds", qos: .userInteractive)
    private var chimePlayer: AVAudioPlayer?
    private var clickPlayer: AVAudioPlayer?

    private init() {
        queue.async { [self] in
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
    }

    /// Touch the singleton early so players are ready before the first hover.
    func warmUp() {}

    func chime() {
        if UserDefaults.standard.object(forKey: SettingsKey.hoverChime) as? Bool ?? true { play(\.chimePlayer) }
    }

    func tap() {
        if UserDefaults.standard.object(forKey: SettingsKey.tapSounds) as? Bool ?? true { play(\.clickPlayer) }
    }

    private func play(_ player: KeyPath<UISounds, AVAudioPlayer?>) {
        queue.async { [self] in
            guard let p = self[keyPath: player] else { return }
            p.currentTime = 0
            p.play()
        }
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
            var ctx = context
            // The design's featured card is ~628pt wide with this 600×520 SVG at
            // its top-left; scale by width so the tower stays ~70% across.
            let s = size.width / 628

            // Sun glow behind the lamp: 72%/36% of the card, radius 16% of the diagonal.
            let glowCenter = CGPoint(x: size.width * 0.72, y: size.height * 0.36)
            let glowR = 0.16 * hypot(size.width, size.height)
            ctx.fill(
                Path(ellipseIn: CGRect(x: glowCenter.x - glowR, y: glowCenter.y - glowR, width: glowR * 2, height: glowR * 2)),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 1, green: 0.925, blue: 0.745).opacity(0.6), Color(red: 1, green: 0.925, blue: 0.745).opacity(0)]),
                    center: glowCenter, startRadius: 0, endRadius: glowR)
            )
            ctx.scaleBy(x: s, y: s)

            // Light beam
            var beam = Path()
            beam.addLines([CGPoint(x: 440, y: 190), CGPoint(x: 900, y: -241), CGPoint(x: 900, y: 247)])
            beam.closeSubpath()
            ctx.fill(beam, with: .color(Color(red: 1, green: 0.933, blue: 0.784).opacity(0.18)))

            // Headland
            var land = Path()
            land.move(to: CGPoint(x: 300, y: 300))
            land.addCurve(to: CGPoint(x: 470, y: 262), control1: CGPoint(x: 360, y: 260), control2: CGPoint(x: 420, y: 250))
            land.addLine(to: CGPoint(x: 900, y: 301))
            // Runs past the SVG's 520pt height so taller cards don't show its bottom edge.
            land.addLine(to: CGPoint(x: 900, y: 1200))
            land.addLine(to: CGPoint(x: 250, y: 1200))
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
