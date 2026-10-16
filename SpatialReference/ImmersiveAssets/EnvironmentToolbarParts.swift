//
//  EnvironmentToolbarParts.swift
//  SpatialReference
//

import SwiftUI

/// Pieces of the floating environment toolbar, shared by the RealityKit
/// environment space and the splat space's toolbar window.
enum EnvironmentToolbar {

    static let exposureRange: ClosedRange<Float> = -2...2

    static func button(_ title: String, systemImage: String, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(isOn ? AnyShapeStyle(.white.opacity(0.25)) : AnyShapeStyle(.clear), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    static var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 4)
    }

    static func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(22)
            .frame(width: 420, alignment: .leading)
            .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 28))
    }

    static func status(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 14, weight: .medium))
            .lineLimit(2)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glassBackgroundEffect(in: Capsule())
    }
}

/// Exposure slider in stops.
struct ExposureCard: View {
    @Binding var exposure: Float

    var body: some View {
        HStack {
            Text("Exposure").font(.headline)
            Spacer()
            Text(exposure, format: .number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
            Button("Reset") { exposure = 0 }
                .disabled(exposure == 0)
        }
        Slider(value: $exposure, in: EnvironmentToolbar.exposureRange, step: 0.1) {
            Text("Exposure")
        } minimumValueLabel: {
            Image(systemName: "sun.min")
        } maximumValueLabel: {
            Image(systemName: "sun.max.fill")
        }
    }
}

/// Background music on or off, and which track.
struct BackgroundMusicCard: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(SettingsKey.backgroundMusic) private var backgroundMusic = true
    @AppStorage(SettingsKey.backgroundMusicTrack) private var backgroundMusicTrack = MusicTrack.defaultID

    var body: some View {
        Toggle("Background Music", isOn: $backgroundMusic)
            .font(.headline)
            .onChange(of: backgroundMusic) { appModel.backgroundMusic.refresh() }
        VStack(spacing: 2) {
            ForEach(MusicTrack.catalog) { track in
                Button {
                    backgroundMusicTrack = track.id
                    backgroundMusic = true
                    appModel.backgroundMusic.refresh()
                } label: {
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                        Text(track.title)
                        Spacer()
                        if backgroundMusic, track.id == backgroundMusicTrack {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .hoverEffect()
            }
        }
    }
}
