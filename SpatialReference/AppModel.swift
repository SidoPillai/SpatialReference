//
//  AppModel.swift
//  SpatialReference
//
//  Created by Siddesh Pillai on 9/28/26.
//

import CompositorServices
import SwiftUI

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    let teleportPortalWindowID = "TeleportPortal"
    let tourModelWindowID = "TourModel"
    let environmentSpaceID = "EnvironmentSpace"
    /// Shows `.ply` splat captures life size with `SplatRenderer`, on device.
    let splatSpaceID = "SplatSpace"
    /// The splat space's floating toolbar, which a Metal layer can't host.
    let splatControlsWindowID = "SplatControls"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    /// The asset viewer's immersive space.
    var immersiveSpaceState = ImmersiveSpaceState.closed
    /// The environment immersive space, showing `activeEnvironment`.
    var environmentSpaceState = ImmersiveSpaceState.closed
    /// The splat space, showing `activeEnvironment` when it's a `.ply`.
    var splatSpaceState = ImmersiveSpaceState.closed
    /// Bumped each time the splat space opens, so a late close from an
    /// earlier one is ignored.
    private var splatSpaceSession = 0
    let splatViewer = SplatViewer()
    var activeEnvironmentID: String?
    /// 360° images and 3D models the user added from Files.
    let importedEnvironments = ImportedEnvironmentStore()

    /// What the environment space shows: a catalog panorama, or an imported
    /// panorama or model.
    var activeEnvironment: ActiveEnvironment? {
        activeEnvironmentID.flatMap(environment(id:))
    }

    func environment(id: String) -> ActiveEnvironment? {
        let panoramas = storyPanoramas
        if let index = panoramas.firstIndex(where: { Self.environmentID(for: $0) == id }), let story {
            return ActiveEnvironment(
                title: panoramas[index].caption ?? story.title,
                subtitle: "360° image \(index + 1) of \(panoramas.count)",
                content: .storyPanorama(itemID: story.itemID, panoramas[index])
            )
        }
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

    /// What the environment toolbar's previous and next buttons step
    /// through: the open story's 360° images while one is showing, otherwise
    /// every enterable environment.
    var steppableEnvironmentIDs: [String] {
        if let activeEnvironmentID, activeEnvironmentID.hasPrefix(Self.storyPanoramaPrefix) {
            return storyPanoramas.map(Self.environmentID(for:))
        }
        return enterableEnvironmentIDs
    }

    /// The open story's 360° images, in story order across all its chapters.
    var storyPanoramas: [Image360] {
        story?.chapters.flatMap { chapter -> [Image360] in
            if case .image360(let images) = chapter.media { return images }
            return []
        } ?? []
    }

    private static let storyPanoramaPrefix = "story-360/"

    /// The environment id a story's 360° image is entered by.
    static func environmentID(for image: Image360) -> String {
        storyPanoramaPrefix + image.id
    }

    /// The index of the story chapter holding the 360° image an environment
    /// id names, or nil when it isn't one of the story's.
    func chapterIndex(ofEnvironment id: String) -> Int? {
        story?.chapters.firstIndex { chapter in
            guard case .image360(let images) = chapter.media else { return false }
            return images.contains { Self.environmentID(for: $0) == id }
        }
    }

    /// The immersive space that shows an environment: splat captures get the
    /// Metal splat space on device, everything else the RealityKit one.
    func spaceID(for environment: ActiveEnvironment) -> String {
        if case .pointCloud = environment.content, SplatViewer.isSupported { return splatSpaceID }
        return environmentSpaceID
    }

    /// What opening and closing spaces needs from the calling view.
    struct SpaceActions {
        let openSpace: OpenImmersiveSpaceAction
        let dismissSpace: DismissImmersiveSpaceAction
        let openWindow: OpenWindowAction
    }

    /// Shows an environment, opening the space it needs and closing any
    /// other; within the same space it just swaps the content.
    func enterEnvironment(_ id: String, using actions: SpaceActions) async {
        guard let target = environment(id: id) else { return }
        let space = spaceID(for: target)
        if let current = activeEnvironment, spaceID(for: current) == space, state(of: space) == .open {
            activeEnvironmentID = id
            return
        }
        // Closes the asset viewer or another environment first.
        await dismissOpenImmersiveSpace(using: actions.dismissSpace)
        activeEnvironmentID = id
        setState(.inTransition, of: space)
        if space == splatSpaceID { splatSpaceSession += 1 }
        switch await actions.openSpace(id: space) {
        case .opened:
            // The RealityKit space's onAppear marks it open; a Metal layer
            // has no such hook.
            if space == splatSpaceID {
                splatSpaceState = .open
                actions.openWindow(id: splatControlsWindowID)
            }
        case .userCancelled, .error:
            fallthrough
        @unknown default:
            setState(.closed, of: space)
            activeEnvironmentID = nil
        }
    }

    /// Steps the open environment to the previous (-1) or next (+1) one,
    /// wrapping around.
    func showAdjacentEnvironment(_ offset: Int, using actions: SpaceActions) async {
        let ids = steppableEnvironmentIDs
        guard let current = activeEnvironmentID, let index = ids.firstIndex(of: current), ids.count > 1 else { return }
        await enterEnvironment(ids[(index + offset + ids.count) % ids.count], using: actions)
    }

    /// Draws into a newly opened splat space's layer.
    func startSplatLayer(_ layerRenderer: LayerRenderer) {
        let session = splatSpaceSession
        splatViewer.start(layerRenderer) { [weak self] in
            // The system can close the space itself, such as from the Digital Crown.
            guard let self, session == splatSpaceSession, splatSpaceState != .closed else { return }
            splatSpaceClosed()
        }
    }

    private func splatSpaceClosed() {
        splatSpaceState = .closed
        activeEnvironmentID = nil
        splatViewer.unload()
    }

    private func state(of space: String) -> ImmersiveSpaceState {
        switch space {
        case splatSpaceID: splatSpaceState
        case environmentSpaceID: environmentSpaceState
        default: immersiveSpaceState
        }
    }

    private func setState(_ state: ImmersiveSpaceState, of space: String) {
        switch space {
        case splatSpaceID: splatSpaceState = state
        case environmentSpaceID: environmentSpaceState = state
        default: immersiveSpaceState = state
        }
    }

    var isImmersiveSpaceInTransition: Bool {
        immersiveSpaceState == .inTransition || environmentSpaceState == .inTransition || splatSpaceState == .inTransition
    }

    /// visionOS shows one immersive space at a time, so opening one first
    /// closes whichever is up. Each space's onDisappear marks it closed.
    func dismissOpenImmersiveSpace(using dismiss: DismissImmersiveSpaceAction) async {
        if immersiveSpaceState == .open {
            immersiveSpaceState = .inTransition
        } else if environmentSpaceState == .open {
            environmentSpaceState = .inTransition
        } else if splatSpaceState == .open {
            splatSpaceState = .inTransition
            await dismiss()
            splatSpaceClosed()
            return
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
