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
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed

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
