//
//  StoryBrowserView.swift
//  SpatialReference
//

import SwiftUI

/// The main window: chapter navigator + narration reader for the loaded
/// story, with the ArcGIS Online sign-in/story-loading tools tucked into a
/// developer-tools disclosure group.
struct StoryBrowserView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow

    @State private var storyItemID = ""
    @State private var resourceOutput = ""
    @State private var isFetching = false
    @State private var parseError: String?
    @State private var showDevTools = false

    var body: some View {
        @Bindable var appModel = appModel

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button {
                    appModel.narrationPlayer.stop()
                    appModel.screen = .explore
                } label: {
                    Label("Explore", systemImage: "chevron.left")
                }

                if let story = appModel.story {
                    Text(story.title).font(.largeTitle.bold())

                    ChapterNavigatorView(chapters: story.chapters, currentIndex: $appModel.currentChapterIndex)

                    if let chapter = appModel.currentChapter {
                        readerPane(for: chapter)
                    }
                } else {
                    ContentUnavailableView(
                        "No story loaded",
                        systemImage: "book.closed",
                        description: Text("Sign in and load the demo story in Developer Tools below.")
                    )
                }

                ToggleImmersiveSpaceButton()

                DisclosureGroup("Developer Tools", isExpanded: $showDevTools) {
                    devToolsSection
                }
            }
            .padding()
        }
        .onAppear {
            if storyItemID.isEmpty {
                storyItemID = appModel.demoStoryItemID
            }
            if appModel.story == nil {
                appModel.story = StoryCache.load(itemID: appModel.demoStoryItemID)
            }
        }
        .onChange(of: appModel.currentChapterIndex) {
            appModel.narrationPlayer.stop()
        }
    }

    private func readerPane(for chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HighlightedCaptionView(
                text: chapter.narrationText,
                highlightedRange: appModel.narrationPlayer.highlightedRange
            )

            if let media = chapter.media {
                mediaCaption(media)

                if case .scene = media {
                    Button {
                        openWindow(id: appModel.teleportPortalWindowID)
                    } label: {
                        Label("Teleport to this location", systemImage: "location.viewfinder")
                    }
                }
            }

            HStack {
                Button {
                    if appModel.narrationPlayer.isSpeaking {
                        appModel.narrationPlayer.stop()
                    } else {
                        appModel.narrationPlayer.speak(chapter.narrationText)
                    }
                } label: {
                    Label(
                        appModel.narrationPlayer.isSpeaking ? "Stop" : "Narrate",
                        systemImage: appModel.narrationPlayer.isSpeaking ? "stop.fill" : "play.fill"
                    )
                }
                .disabled(chapter.narrationText.isEmpty)

                Spacer()

                Button("Previous") { appModel.currentChapterIndex -= 1 }
                    .disabled(appModel.currentChapterIndex == 0)
                Button("Next") { appModel.currentChapterIndex += 1 }
                    .disabled(appModel.currentChapterIndex >= (appModel.story?.chapters.count ?? 1) - 1)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 28))
    }

    @ViewBuilder
    private func mediaCaption(_ media: ChapterMedia) -> some View {
        switch media {
        case .scene(let itemID, let caption, let camera):
            Label(caption ?? "Scene \(itemID)", systemImage: camera != nil ? "view.3d" : "map")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .image(let resourceName, let caption):
            Label(caption ?? resourceName, systemImage: "photo")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .embed(let url, let title):
            Label(title ?? url.absoluteString, systemImage: "link")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Developer tools (ArcGIS Online spike UI)

    private var devToolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            signInSection

            if case .signedIn = appModel.arcGISSession.state {
                storyMapFetchSection
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var signInSection: some View {
        switch appModel.arcGISSession.state {
        case .signedOut:
            Button("Sign in to ArcGIS Online") {
                Task { await appModel.arcGISSession.signIn() }
            }
        case .signingIn:
            ProgressView("Signing in…")
        case .signedIn(let username):
            Label("Signed in as \(username)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            VStack(alignment: .leading) {
                Label("Sign-in failed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message).font(.caption)
                Button("Retry") {
                    Task { await appModel.arcGISSession.signIn() }
                }
            }
        }
    }

    private var storyMapFetchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("StoryMap item ID", text: $storyItemID)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Load story") {
                    loadStory()
                }
                Button("List resources (debug)") {
                    fetch { try await appModel.arcGISSession.listResources(itemID: storyItemID) }
                }
            }
            .disabled(storyItemID.isEmpty || isFetching)

            if isFetching {
                ProgressView()
            }

            if let parseError {
                Text(parseError).foregroundStyle(.red).font(.caption)
            }

            if !resourceOutput.isEmpty {
                Text(resourceOutput)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func loadStory() {
        isFetching = true
        parseError = nil
        Task {
            defer { isFetching = false }
            do {
                let json = try await appModel.arcGISSession.fetchResource(itemID: storyItemID, resourceName: "published_data.json")
                guard let data = json.data(using: .utf8) else { return }
                let story = try StoryMapParser.parse(data: data, itemID: storyItemID)
                StoryCache.save(story)
                appModel.story = story
                appModel.currentChapterIndex = 0
                resourceOutput = ""
            } catch {
                parseError = "Error: \(error.localizedDescription)"
            }
        }
    }

    private func fetch(_ operation: @escaping () async throws -> String) {
        isFetching = true
        resourceOutput = ""
        Task {
            defer { isFetching = false }
            do {
                resourceOutput = try await operation()
            } catch {
                resourceOutput = "Error: \(error.localizedDescription)"
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    StoryBrowserView()
        .environment(AppModel())
}
