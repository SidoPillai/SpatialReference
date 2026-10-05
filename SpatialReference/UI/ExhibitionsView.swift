//
//  ExhibitionsView.swift
//  SpatialReference
//

import SwiftUI

/// How a visitor gets into an exhibition, shown as the pill under its title.
enum Admission {
    case free, price(Double), ticketed

    var badge: CardBadge {
        switch self {
        case .free: CardBadge(text: "Admission: Free", systemImage: "qrcode", filled: true)
        case .price(let amount):
            CardBadge(text: "Admission: \(amount.formatted(.currency(code: "USD")))", systemImage: "qrcode", filled: true)
        case .ticketed: CardBadge(text: "Ticketed", systemImage: "checkmark.seal")
        }
    }
}

enum ExhibitionKind: String, CaseIterable, Identifiable {
    case all = "All", ancient = "Ancient World", art = "Art", science = "Science", music = "Music & Culture"
    var id: Self { self }
}

/// Large graphic laid over an exhibition's cover gradient.
enum ExhibitionMotif {
    case symbol(String)
    case pyramids
}

/// Placeholder museum or heritage-site exhibition. Covers are drawn from
/// gradients and a motif until exhibitions carry real imagery.
struct Exhibition: Identifiable {
    var id: String { title }
    let title: String
    let venue: String
    let location: String
    let kind: ExhibitionKind
    let summary: String
    var admission = Admission.ticketed
    var tag: CardTag?
    var immersive = false
    var has3D = false
    var images = 0
    var narrated = false
    let art: AnyShapeStyle
    var glows: [CoverGlow] = []
    let motif: ExhibitionMotif

    var features: [CardFeature] {
        var features: [CardFeature] = []
        if immersive { features.append(CardFeature(systemImage: "visionpro", label: "Immersive")) }
        if has3D { features.append(CardFeature(systemImage: "cube", label: "3D Model")) }
        if images > 0 {
            features.append(CardFeature(systemImage: "photo.on.rectangle", label: "Gallery"))
            features.append(CardFeature(systemImage: "photo.stack", label: "\(images) Images"))
        }
        if narrated { features.append(CardFeature(systemImage: "waveform", label: "Audio Guide")) }
        return features
    }

    static let catalog: [Exhibition] = [
        Exhibition(
            title: "Pyramids of Giza", venue: "Giza Necropolis", location: "Giza, Egypt", kind: .ancient,
            summary: "Walk the causeway to the Great Pyramid of Khufu, then climb inside to the King’s Chamber as it stood 4,500 years ago.",
            admission: .price(5.99), tag: .new, immersive: true, has3D: true, narrated: true,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0xF4C98A), Color(hex: 0xE09A55), Color(hex: 0xA8602C)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.14, y: 0.22), radius: 0.07, color: Color(hex: 0xFFF2D6), solid: true)],
            motif: .pyramids
        ),
        Exhibition(
            title: "Smithsonian: Flight", venue: "National Air and Space Museum", location: "Washington, DC", kind: .science,
            summary: "From the Wright Flyer to the Apollo 11 command module, see the machines that carried us off the ground and into orbit.",
            admission: .free, tag: .updated, immersive: true, has3D: true, images: 24, narrated: true,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x8EC3F0), Color(hex: 0x3D7DC4), Color(hex: 0x173A6B)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.2, y: 0.1), radius: 0.8, color: .white.opacity(0.45))],
            motif: .symbol("airplane")
        ),
        Exhibition(
            title: "The Met: Temple of Dendur", venue: "The Metropolitan Museum of Art", location: "New York, NY", kind: .art,
            summary: "Stand in the Sackler Wing beside a Roman-era Egyptian temple, rebuilt stone by stone on the banks of Central Park.",
            admission: .ticketed, tag: .new, immersive: true, images: 18, narrated: true,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0xD9CBB4), Color(hex: 0x9C8668), Color(hex: 0x4F4232)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.5, y: 0), radius: 0.9, color: Color(hex: 0xFFF4DE).opacity(0.5))],
            motif: .symbol("building.columns.fill")
        ),
        Exhibition(
            title: "MoPOP: Guitar Gallery", venue: "Museum of Pop Culture", location: "Seattle, WA", kind: .music,
            summary: "Circle the 500-instrument sculpture at the heart of Frank Gehry’s building and hear the riffs that shaped rock ’n’ roll.",
            admission: .price(4.99), tag: .updated, immersive: true, has3D: true, narrated: true,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0xE0457B), Color(hex: 0x7B2FBF), Color(hex: 0x23145A)],
                startPoint: .topLeading, endPoint: .bottomTrailing)),
            glows: [CoverGlow(center: UnitPoint(x: 0.8, y: 0.85), radius: 0.8, color: Color(hex: 0xFFB347).opacity(0.5))],
            motif: .symbol("guitars.fill")
        ),
        Exhibition(
            title: "The Louvre: Grand Gallery", venue: "Musée du Louvre", location: "Paris, France", kind: .art,
            summary: "Stroll the Grande Galerie at closing time, with the Renaissance masters to yourself and a curator in your ear.",
            admission: .ticketed, immersive: true, images: 32, narrated: true,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x6B4A2E), Color(hex: 0x3A2717), Color(hex: 0x1C130B)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.5, y: 0.45), radius: 0.7, color: Color(hex: 0xFFC978).opacity(0.55))],
            motif: .symbol("photo.artframe")
        ),
        Exhibition(
            title: "Natural History: Fossils", venue: "Smithsonian National Museum of Natural History", location: "Washington, DC", kind: .science,
            summary: "Meet a full-scale T. rex in the Hall of Fossils and turn 3D-scanned specimens over in your own hands.",
            admission: .free, tag: .new, has3D: true, images: 12, narrated: true,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x6E7F5A), Color(hex: 0x3E4A30), Color(hex: 0x1F2618)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.3, y: 0.25), radius: 0.8, color: Color(hex: 0xE9F2C8).opacity(0.4))],
            motif: .symbol("fossil.shell.fill")
        ),
        Exhibition(
            title: "Terracotta Army", venue: "Mausoleum of the First Qin Emperor", location: "Xi’an, China", kind: .ancient,
            summary: "Descend into Pit 1 and walk the ranks of 8,000 clay soldiers, each with a face of its own.",
            admission: .price(3.99), immersive: true, has3D: true, images: 9,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0xC48A62), Color(hex: 0x8C5636), Color(hex: 0x4A2A18)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.5, y: 1), radius: 0.9, color: Color(hex: 0xFFB26B).opacity(0.45))],
            motif: .symbol("shield.lefthalf.filled")
        ),
        Exhibition(
            title: "Abbey Road Sessions", venue: "Abbey Road Studios", location: "London, UK", kind: .music,
            summary: "Sit at the console in Studio Two and pull the faders on the multitrack recordings that defined a decade.",
            admission: .ticketed, tag: .updated, immersive: true, images: 15, narrated: true,
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x2F3B4C), Color(hex: 0x1A2230), Color(hex: 0x0D1118)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.7, y: 0.3), radius: 0.7, color: Color(hex: 0x6FB7FF).opacity(0.45))],
            motif: .symbol("music.mic")
        ),
    ]
}

/// Cover for an exhibition card: gradient art with its motif on top.
struct ExhibitionCover: View {
    let exhibition: Exhibition

    var body: some View {
        CoverArt(art: exhibition.art, glows: exhibition.glows)
            .overlay {
                switch exhibition.motif {
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: 92, weight: .light))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                case .pyramids:
                    PyramidsArt()
                }
            }
    }
}

/// Three pyramids on a dune line, scaled to fill the cover.
struct PyramidsArt: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let ground = h * 0.82
            for (x, half, height) in [(0.30, 0.22, 0.48), (0.62, 0.19, 0.40), (0.84, 0.10, 0.22)] {
                let apex = CGPoint(x: w * x, y: ground - h * height)
                var lit = Path()
                lit.addLines([apex, CGPoint(x: w * (x - half), y: ground), CGPoint(x: w * x, y: ground)])
                lit.closeSubpath()
                ctx.fill(lit, with: .color(Color(hex: 0xE8B57A)))
                var shade = Path()
                shade.addLines([apex, CGPoint(x: w * x, y: ground), CGPoint(x: w * (x + half), y: ground)])
                shade.closeSubpath()
                ctx.fill(shade, with: .color(Color(hex: 0x9A5E2E)))
            }
            ctx.fill(Path(CGRect(x: 0, y: ground, width: w, height: h - ground)), with: .color(Color(hex: 0xC98B4D)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Exhibitions tab: a filter row of exhibition kinds over a grid of
/// admission cards. Tapping a card opens its details.
struct ExhibitionsView: View {

    @Binding var hovered: String?
    @State private var kind = ExhibitionKind.all
    @State private var selected: String?

    private var items: [Exhibition] {
        Exhibition.catalog.filter { kind == .all || $0.kind == kind }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("Exhibitions")
                        .font(.system(size: 40, weight: .bold))
                    Text(items.count == 1 ? "1 exhibition" : "\(items.count) exhibitions")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 16)

                HStack(spacing: 8) {
                    ForEach(ExhibitionKind.allCases) { item in
                        let on = item == kind
                        Button { kind = item } label: {
                            Text(item.rawValue)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(on ? .black : .white)
                                .padding(.horizontal, 16)
                                .frame(height: 40)
                                .background(on ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.08)), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 28, alignment: .top)],
                    spacing: 28
                ) {
                    ForEach(items) { card($0) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .padding(.top, 40)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .animation(.easeOut(duration: 0.25), value: kind)
    }

    private func card(_ exhibition: Exhibition) -> some View {
        Button { selected = exhibition.id } label: {
            StoryCard(
                title: exhibition.title,
                tag: exhibition.tag,
                badge: exhibition.admission.badge,
                features: [CardFeature(systemImage: "mappin.and.ellipse", label: exhibition.location)] + exhibition.features
            ) {
                ExhibitionCover(exhibition: exhibition)
            }
        }
        .buttonStyle(.plain)
        .modifier(CardHover(id: exhibition.id, radius: StoryCardMetrics.radius, hovered: $hovered, enabled: true))
        .popover(isPresented: Binding(
            get: { selected == exhibition.id },
            set: { if !$0 { selected = nil } }
        )) {
            details(exhibition)
        }
        .accessibilityLabel("\(exhibition.title), \(exhibition.venue), \(exhibition.admission.badge.text)")
    }

    private func details(_ exhibition: Exhibition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(exhibition.title).font(.system(size: 24, weight: .bold))
            Label("\(exhibition.venue) · \(exhibition.location)", systemImage: "mappin.and.ellipse")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text(exhibition.summary)
                .font(.system(size: 17))
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 14, lineSpacing: 8) {
                ForEach(exhibition.features, id: \.self) { feature in
                    Label(feature.label, systemImage: feature.systemImage)
                }
            }
            .font(.system(size: 15, weight: .medium))

            HStack(spacing: 12) {
                BadgePill(badge: exhibition.admission.badge)
                Spacer()
                Button {} label: {
                    Label("Coming Soon", systemImage: "ticket")
                }
                .disabled(true)
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 440)
    }
}
