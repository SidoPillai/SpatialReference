//
//  StoryBrowserView.swift
//  SpatialReference
//

import SwiftUI

/// The story viewer: chapter header, the chapter's scene / immersive-space
/// cards, live-highlighted narration text and a floating narration bar.
/// ArcGIS sign-in and story-loading tools live in `DevToolsView`, opened from
/// the chapters menu.
struct StoryBrowserView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow

    @State private var isBookmarked = false
    @State private var showDevTools = false

    private var player: NarrationPlayer { appModel.narrationPlayer }

    var body: some View {
        ZStack {
            WarmBackdrop()

            VStack(spacing: 24) {
                panel
                narrationBar
            }
            .padding(.horizontal, 64)
            .padding(.top, 40)
            .padding(.bottom, 28)
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $showDevTools) {
            DevToolsView()
                .environment(appModel)
        }
        .onAppear {
            if appModel.story == nil {
                appModel.story = StoryCache.load(itemID: appModel.demoStoryItemID)
            }
        }
        .onChange(of: appModel.currentChapterIndex) {
            player.stop()
        }
        .onDisappear {
            player.stop()
        }
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            if let chapter = appModel.currentChapter {
                HStack(alignment: .top, spacing: 44) {
                    VStack(spacing: 16) {
                        if let media = chapter.media {
                            mediaCard(media)
                        }
                        immersiveSpaceCard
                        Spacer(minLength: 0)
                    }
                    .frame(width: 500)

                    ScrollView {
                        HighlightedCaptionView(
                            text: chapter.narrationText,
                            highlightedRange: player.highlightedRange,
                            isNarrating: player.isSpeaking
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No story loaded",
                    systemImage: "book.closed",
                    description: Text("Open Developer Tools from the chapters menu to load the demo story.")
                )
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.top, 32)
        .padding(.horizontal, 44)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color(red: 98 / 255, green: 85 / 255, blue: 73 / 255).opacity(0.66),
            in: RoundedRectangle(cornerRadius: 48)
        )
        .overlay(RoundedRectangle(cornerRadius: 48).strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 45, y: 40)
    }

    private var header: some View {
        HStack(spacing: 20) {
            circleButton("Back to Explore", systemImage: "chevron.left") {
                appModel.screen = .explore
            }

            VStack(alignment: .leading, spacing: 2) {
                if let story = appModel.story {
                    Text("Chapter \(appModel.currentChapterIndex + 1) of \(story.chapters.count)".uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.86))
                    Text(story.title)
                        .font(.system(size: 34, design: .serif))
                        .lineLimit(1)
                } else {
                    Text("No story loaded")
                        .font(.system(size: 34, design: .serif))
                }
            }
            Spacer()

            circleButton(isBookmarked ? "Remove bookmark" : "Bookmark", systemImage: isBookmarked ? "bookmark.fill" : "bookmark") {
                isBookmarked.toggle()
            }
            chaptersMenu
        }
    }

    private var chaptersMenu: some View {
        Menu {
            if let story = appModel.story {
                ForEach(Array(story.chapters.enumerated()), id: \.element.id) { index, _ in
                    Button {
                        appModel.currentChapterIndex = index
                    } label: {
                        if index == appModel.currentChapterIndex {
                            Label("Chapter \(index + 1)", systemImage: "checkmark")
                        } else {
                            Text("Chapter \(index + 1)")
                        }
                    }
                }
                Divider()
            }
            Button("Developer Tools…", systemImage: "wrench.and.screwdriver") {
                showDevTools = true
            }
        } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityLabel("Chapters")
    }

    // MARK: - Left column cards

    @ViewBuilder
    private func mediaCard(_ media: ChapterMedia) -> some View {
        switch media {
        case .scene(let itemID, let caption, let camera):
            Button {
                openWindow(id: appModel.teleportPortalWindowID)
            } label: {
                mediaCardBody(
                    badge: camera != nil ? "3D scene" : "Map scene",
                    title: caption ?? "Scene \(itemID)",
                    subtitle: "Teleport to this location",
                    actionTitle: "Teleport",
                    actionIcon: "location.viewfinder"
                )
            }
            .buttonStyle(.plain)
            .hoverEffect()
            .accessibilityLabel("Teleport to \(caption ?? "this location")")
        case .image(let resourceName, let caption):
            mediaCardBody(badge: "Image", title: caption ?? resourceName, subtitle: nil, actionTitle: nil, actionIcon: nil)
        case .embed(let url, let title):
            mediaCardBody(badge: "Link", title: title ?? url.absoluteString, subtitle: nil, actionTitle: nil, actionIcon: nil)
        }
    }

    private func mediaCardBody(badge: String, title: String, subtitle: String?, actionTitle: String?, actionIcon: String?) -> some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Color(hex: 0x2D3642), Color(hex: 0x65717C), Color(hex: 0x26323C), Color(hex: 0x0C141A)],
                startPoint: .top, endPoint: .bottom
            )
            GlobeView(gridOpacity: 0.3, gridLineWidth: 0.8, orbitOpacity: 0.5, orbitLineWidth: 1, dotRadius: 4)
                .frame(width: 260, height: 260)
                .frame(maxHeight: .infinity, alignment: .center)
                .padding(.bottom, 40)
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 170)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.88))
                    }
                }
                Spacer(minLength: 0)
                if let actionTitle, let actionIcon {
                    HStack(spacing: 8) {
                        Image(systemName: actionIcon)
                        Text(actionTitle).font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(darkInk)
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                    .background(cream, in: Capsule())
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
        }
        .overlay(alignment: .topLeading) {
            Text(badge)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.4), in: Capsule())
                .padding(20)
        }
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(.white.opacity(0.55), lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 32))
    }

    private var immersiveSpaceCard: some View {
        ToggleImmersiveSpaceButton { isOpen in
            HStack(spacing: 16) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 30, weight: .light))
                    .frame(width: 72, height: 72)
                    .background(.black.opacity(0.22), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(isOpen ? "Leave immersive space" : "Immersive space")
                        .font(.system(size: 19, weight: .semibold))
                    Text(isOpen ? "Return to the window" : "Place assets in your space")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.86))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .bold))
            }
            .padding(.leading, 14)
            .padding(.trailing, 20)
            .frame(height: 100)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 28))
            .contentShape(RoundedRectangle(cornerRadius: 28))
        }
        .buttonStyle(.plain)
        .hoverEffect()
    }

    // MARK: - Narration bar

    private var narrationText: String { appModel.currentChapter?.narrationText ?? "" }

    private var narrationBar: some View {
        let duration = player.isSpeaking ? player.estimatedDuration : NarrationPlayer.estimatedDuration(of: narrationText, speed: player.speed)
        let elapsed = duration * player.progress
        let isPlaying = player.isSpeaking && !player.isPaused

        return HStack(spacing: 14) {
            circleButton("Back 10 words", systemImage: "gobackward.10", fill: .white.opacity(0.1)) {
                if player.isSpeaking { player.skip(words: -10, in: narrationText) }
            }

            Button {
                if !player.isSpeaking {
                    player.speak(narrationText)
                } else if player.isPaused {
                    player.resume()
                } else {
                    player.pause()
                }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(darkInk)
                    .frame(width: 60, height: 60)
                    .background(cream, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .hoverEffect()
            .disabled(narrationText.isEmpty)
            .accessibilityLabel(isPlaying ? "Pause narration" : "Play narration")

            circleButton("Forward 10 words", systemImage: "goforward.10", fill: .white.opacity(0.1)) {
                if player.isSpeaking { player.skip(words: 10, in: narrationText) }
            }

            HStack(spacing: 12) {
                Text(Self.format(elapsed))
                ProgressBar(fraction: player.progress)
                Text("-" + Self.format(max(0, duration - elapsed)))
            }
            .font(.system(size: 15).monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))

            pillButton(String(format: "%g×", player.speed), label: "Playback speed") {
                player.cycleSpeed()
            }

            Button { player.cycleVoice() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "mic")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.25), in: Circle())
                    Text("Voice: \(player.voiceName)")
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.leading, 8)
                .padding(.trailing, 18)
                .frame(height: 52)
                .background(.white.opacity(0.1), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .hoverEffect()
            .accessibilityLabel("Narrator voice")
        }
        .padding(.horizontal, 16)
        .frame(width: 880, height: 88)
        .background(Color(red: 98 / 255, green: 85 / 255, blue: 73 / 255).opacity(0.72), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 25, y: 20)
    }

    // MARK: - Small pieces

    private func circleButton(_ label: String, systemImage: String, fill: Color = .white.opacity(0.12), action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 52, height: 52)
                .background(fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityLabel(label)
    }

    private func pillButton(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(.white.opacity(0.1), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityLabel(label)
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var cream: Color { Color(red: 0.965, green: 0.945, blue: 0.918) }
    private var darkInk: Color { Color(red: 0.169, green: 0.141, blue: 0.118) }
}

private struct ProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white)
                    .frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 8)
    }
}

#Preview(windowStyle: .automatic) {
    StoryBrowserView()
        .environment(AppModel())
}
