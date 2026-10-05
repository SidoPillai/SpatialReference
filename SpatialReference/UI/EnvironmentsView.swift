//
//  EnvironmentsView.swift
//  SpatialReference
//

import SwiftUI

/// Placeholder immersive environment. Each is shown as an orb (or a wide
/// capsule for panoramas) until real environment scenes are bundled.
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
            sphere: true
        ),
        ImmersiveEnvironment(
            title: "Grand Canyon", location: "Grand Canyon National Park, AZ",
            summary: "Sunrise from Mather Point as light spills down two billion years of layered rock to the Colorado River.",
            art: AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: Color(hex: 0xF7C98B), location: 0),
                    .init(color: Color(hex: 0xE88A4E), location: 0.38),
                    .init(color: Color(hex: 0xB4532A), location: 0.4),
                    .init(color: Color(hex: 0x8A3A1E), location: 0.62),
                    .init(color: Color(hex: 0x6B2B18), location: 0.64),
                    .init(color: Color(hex: 0x3E1A10), location: 1),
                ],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.75, y: 0.15), radius: 0.06, color: Color(hex: 0xFFF1C8), solid: true)],
            wide: true
        ),
        ImmersiveEnvironment(
            title: "Saturn", location: "Cassini Division",
            summary: "Drift above the ring plane as ice and rock glitter in the sunlight a billion miles from home.",
            art: AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: Color(hex: 0xEAD7A8), location: 0),
                    .init(color: Color(hex: 0xC9A86E), location: 0.45),
                    .init(color: Color(hex: 0xA9864E), location: 0.55),
                    .init(color: Color(hex: 0x6B5432), location: 1),
                ],
                startPoint: .top, endPoint: .bottom)),
            sphere: true
        ),
        ImmersiveEnvironment(
            title: "Yosemite Valley", location: "Yosemite National Park, CA",
            summary: "Tunnel View at golden hour: El Capitan, Half Dome and Bridalveil Fall framed in one sweep.",
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x9CC6E8), Color(hex: 0x5E8A6E), Color(hex: 0x1F3A28)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.5, y: 0.3), radius: 0.6, color: Color(hex: 0xFFE6B0).opacity(0.4))]
        ),
        ImmersiveEnvironment(
            title: "Antarctica", location: "Lemaire Channel",
            summary: "Glide between sheer ice cliffs on still black water while penguins porpoise past the bow.",
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0xF2F8FB), Color(hex: 0xA9CFE0), Color(hex: 0x2E5C78)],
                startPoint: .top, endPoint: .bottom))
        ),
        ImmersiveEnvironment(
            title: "Great Barrier Reef", location: "Queensland, Australia",
            summary: "Hover over a coral garden as reef fish weave through shafts of sunlight.",
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x4FD1D9), Color(hex: 0x1B7FA6), Color(hex: 0x0B2F4A)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.5, y: -0.1), radius: 0.8, color: .white.opacity(0.45))]
        ),
        ImmersiveEnvironment(
            title: "Orion Nebula", location: "1,344 light-years away",
            summary: "Float inside a stellar nursery where new suns ignite in clouds of glowing gas.",
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x1A0B2E), Color(hex: 0x0A0614)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.35, y: 0.45), radius: 0.45, color: Color(hex: 0xC04CE0).opacity(0.7)),
                    CoverGlow(center: UnitPoint(x: 0.7, y: 0.55), radius: 0.4, color: Color(hex: 0x4C7BE0).opacity(0.55))],
            stars: true,
            wide: true
        ),
        ImmersiveEnvironment(
            title: "Mount Everest", location: "Summit, 8,849 m",
            summary: "Stand on the roof of the world as the sun rises over the Himalaya.",
            art: AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x2B4C8C), Color(hex: 0x8DA9D6), Color(hex: 0xF0F4FA)],
                startPoint: .top, endPoint: .bottom)),
            glows: [CoverGlow(center: UnitPoint(x: 0.8, y: 0.75), radius: 0.6, color: Color(hex: 0xFFB27A).opacity(0.45))]
        ),
    ]
}

/// Environments tab: a field of orbs, one per environment. Selecting one
/// shows its details in a glass bar along the bottom.
struct EnvironmentsView: View {

    @State private var selected: String?

    private static let orb: CGFloat = 170

    private var selection: ImmersiveEnvironment? {
        ImmersiveEnvironment.catalog.first { $0.id == selected }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Environments")
                    .font(.system(size: 40, weight: .bold))
                Text("Places to surround yourself with while you read. More are on the way.")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }

            ScrollView {
                FlowLayout(spacing: 44, lineSpacing: 32) {
                    ForEach(ImmersiveEnvironment.catalog) { orb($0) }
                    comingSoon
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            if let env = selection {
                detailBar(env)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.top, 40)
        .padding([.horizontal, .bottom], 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(duration: 0.35), value: selected)
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

    /// Faded, untappable orb hinting that the list will grow.
    private var comingSoon: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(.white.opacity(0.06))
                .overlay { Circle().strokeBorder(.white.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [6, 6])) }
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(width: Self.orb, height: Self.orb)
            Text("Coming Soon")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
        }
        .accessibilityElement(children: .combine)
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
            Label("Coming Soon", systemImage: "visionpro")
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 20)
                .frame(height: 48)
                .background(.white.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                .accessibilityLabel("Environment coming soon")
        }
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 28))
    }
}
