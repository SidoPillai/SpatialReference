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
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed

    let arcGISSession = ArcGISOnlineSession()
    let narrationPlayer = NarrationPlayer()

    /// Milestone-1 demo story: Esri's public "Google photorealistic 3D
    /// basemap" StoryMap, picked for its real 3D scene camera viewpoints.
    let demoStoryItemID = "2f158b05b05644519fb4f5d51aa1c75f"
    enum Screen { case welcome, explore, browser }
    var screen = Screen.welcome
    var story: Story?
    var currentChapterIndex = 0

    var currentChapter: Chapter? {
        guard let story, story.chapters.indices.contains(currentChapterIndex) else { return nil }
        return story.chapters[currentChapterIndex]
    }
}
