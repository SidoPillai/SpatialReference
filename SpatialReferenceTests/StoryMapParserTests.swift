//
//  StoryMapParserTests.swift
//  SpatialReferenceTests
//

import Testing
import Foundation
@testable import SpatialReference

struct StoryMapParserTests {

    private func loadFixtureData() throws -> Data {
        let url = try #require(
            Bundle(for: BundleToken.self).url(forResource: "photorealistic-3d-basemap-published_data", withExtension: "json")
        )
        return try Data(contentsOf: url)
    }

    @Test func parsesRealStoryIntoChaptersWithNarrationAndScenes() throws {
        let data = try loadFixtureData()
        let story = try StoryMapParser.parse(data: data, itemID: "2f158b05b05644519fb4f5d51aa1c75f")

        #expect(story.title == "Google photorealistic 3D basemap (now in preview)")
        #expect(!story.chapters.isEmpty)

        // Every chapter should have some narration text.
        for chapter in story.chapters {
            #expect(!chapter.narrationText.isEmpty, "Chapter \(chapter.id) has no narration text")
        }

        // At least one chapter should carry a scene with a real 3D camera
        // viewpoint (the whole point of the teleport feature).
        let scenesWithCamera = story.chapters.compactMap { chapter -> SceneCamera? in
            if case .scene(_, _, let camera) = chapter.media {
                return camera
            }
            return nil
        }
        #expect(!scenesWithCamera.isEmpty)
    }

    @Test func decodesHTMLEntitiesInNarrationText() throws {
        let data = try loadFixtureData()
        let story = try StoryMapParser.parse(data: data, itemID: "2f158b05b05644519fb4f5d51aa1c75f")
        let allText = story.chapters.map(\.narrationText).joined()
        #expect(!allText.contains("&apos;"))
    }
}

private final class BundleToken {}
