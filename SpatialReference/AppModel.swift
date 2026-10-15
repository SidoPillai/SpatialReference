//
//  AppModel.swift
//  SpatialReference
//
//  Created by Siddesh Pillai on 9/28/26.
//

import SwiftUI

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    let teleportPortalWindowID = "TeleportPortal"
    let tourModelWindowID = "TourModel"
    let environmentSpaceID = "EnvironmentSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    /// The asset viewer's immersive space.
    var immersiveSpaceState = ImmersiveSpaceState.closed
    /// The environment immersive space, showing `activeEnvironment`.
    var environmentSpaceState = ImmersiveSpaceState.closed
    var activeEnvironmentID: String?
    /// 360° images and 3D models the user added from Files.
    let importedEnvironments = ImportedEnvironmentStore()

    /// What the environment space shows: a catalog panorama, or an imported
    /// panorama or model.
    var activeEnvironment: ActiveEnvironment? {
        guard let id = activeEnvironmentID else { return nil }
        if let env = ImmersiveEnvironment.catalog.first(where: { $0.id == id }), let panorama = env.panorama {
            return ActiveEnvironment(title: env.title, subtitle: env.location, content: .bundledPanorama(panorama))
        }
        guard let item = importedEnvironments.items.first(where: { $0.id == id }) else { return nil }
        let url = importedEnvironments.url(for: item)
        let content: ActiveEnvironment.Content = switch item.kind {
        case .panorama: .panorama(url)
        case .model: .model(url, isRealityFile: item.isRealityFile)
        case .pointCloud: .pointCloud(url)
        }
        return ActiveEnvironment(title: item.title, subtitle: item.subtitle, content: content)
    }

    /// Every environment that can be entered, in the Environments tab's order.
    var enterableEnvironmentIDs: [String] {
        ImmersiveEnvironment.catalog.filter(\.isAvailable).map(\.id) + importedEnvironments.items.map(\.id)
    }

    /// Switches the open environment space to the previous (-1) or next (+1)
    /// environment, wrapping around.
    func showAdjacentEnvironment(_ offset: Int) {
        let ids = enterableEnvironmentIDs
        guard let current = activeEnvironmentID, let index = ids.firstIndex(of: current), ids.count > 1 else { return }
        activeEnvironmentID = ids[(index + offset + ids.count) % ids.count]
    }

    var isImmersiveSpaceInTransition: Bool {
        immersiveSpaceState == .inTransition || environmentSpaceState == .inTransition
    }

    /// visionOS shows one immersive space at a time, so opening one first
    /// closes whichever is up. Each space's onDisappear marks it closed.
    func dismissOpenImmersiveSpace(using dismiss: DismissImmersiveSpaceAction) async {
        if immersiveSpaceState == .open {
            immersiveSpaceState = .inTransition
        } else if environmentSpaceState == .open {
            environmentSpaceState = .inTransition
        } else {
            return
        }
        await dismiss()
    }

    let arcGISSession = ArcGISOnlineSession()
    let narrationPlayer = NarrationPlayer()
    let tourAudio = TourAudioPlayer()
    let backgroundMusic = BackgroundMusicPlayer()

    /// Milestone-1 demo story: Esri's public "Google photorealistic 3D
    /// basemap" StoryMap, picked for its real 3D scene camera viewpoints.
    let demoStoryItemID = "2f158b05b05644519fb4f5d51aa1c75f"
    enum Screen { case welcome, explore, browser }
    var screen = Screen.welcome
    var story: Story?
    var currentChapterIndex = 0
    /// The Explore window's selected tab and category, kept here so they
    /// survive opening and closing a story.
    var exploreSection = ExploreView.Section.explore
    var exploreCategory = ExploreCategory.featured

    // MARK: - Library (the signed-in user's StoryMaps)

    enum LibraryState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var libraryItems: [ArcGISOnlineSession.StoryMapItem] = []
    private(set) var libraryState = LibraryState.idle
    /// The library story currently being downloaded and parsed, if any.
    private(set) var openingStoryID: String?
    var openStoryError: String?

    /// False until the launch-time sign-in restore finishes, so the first
    /// screen isn't picked before we know whether the user is signed in.
    private(set) var hasRestoredSession = false

    /// Restores a saved ArcGIS sign-in on launch. Only a user who is already
    /// signed in skips the welcome screen; everyone else sees it.
    func restoreSession() async {
        await arcGISSession.restoreSession()
        if case .signedIn = arcGISSession.state, screen == .welcome {
            screen = .explore
        }
        hasRestoredSession = true
    }

    func signOut() async {
        await arcGISSession.signOut()
        libraryItems = []
        libraryState = .idle
    }

    func refreshLibrary() async {
        guard libraryState != .loading else { return }
        libraryState = .loading
        do {
            libraryItems = try await arcGISSession.listMyStoryMaps()
            libraryState = .loaded
        } catch {
            libraryState = .failed(error.localizedDescription)
        }
    }

    /// Downloads, parses and caches a story, then makes it the current one.
    /// Prefers the published JSON; a never-published story only has a draft.
    func loadStory(itemID: String) async throws {
        var lastError: Error?
        for resourceName in ["published_data.json", "draft.json"] {
            do {
                let json = try await arcGISSession.fetchResource(itemID: itemID, resourceName: resourceName)
                let story = try StoryMapParser.parse(data: Data(json.utf8), itemID: itemID)
                StoryCache.save(story)
                self.story = story
                currentChapterIndex = 0
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? CancellationError()
    }

    /// Opens a library story in the reader; returns whether it succeeded.
    func openLibraryStory(itemID: String) async -> Bool {
        guard openingStoryID == nil else { return false }
        openingStoryID = itemID
        openStoryError = nil
        defer { openingStoryID = nil }
        do {
            try await loadStory(itemID: itemID)
            return true
        } catch {
            openStoryError = error.localizedDescription
            return false
        }
    }

    var currentChapter: Chapter? {
        guard let story, story.chapters.indices.contains(currentChapterIndex) else { return nil }
        return story.chapters[currentChapterIndex]
    }
}
