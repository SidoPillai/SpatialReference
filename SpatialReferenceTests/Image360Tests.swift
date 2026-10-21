//
//  Image360Tests.swift
//  SpatialReferenceTests
//

import Testing
import CoreGraphics
import Foundation
@testable import SpatialReference

@MainActor
struct Image360Tests {

    private func fixtureData() throws -> Data {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "image360-published_data", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func parseFixture() throws -> Story {
        try StoryMapParser.parse(data: fixtureData(), itemID: "x")
    }

    // MARK: - Parser

    @Test func groupsConsecutive360ImagesIntoOneChapterInOrder() throws {
        let story = try parseFixture()

        #expect(story.title == "360 Immersive")
        #expect(story.chapters.count == 1)
        guard case .image360(let images) = story.chapters.first?.media else {
            Issue.record("Expected a 360° chapter, got \(String(describing: story.chapters.first?.media))")
            return
        }

        #expect(images.count == 10)
        #expect(images.first?.id == "n-iZccut")
        #expect(images.last?.id == "n-XSG8GN")
        #expect(images.first?.resourceName == "b132aba1-b190-4200-9a76-81b6eab3a2a2.jpeg")
        #expect(images[5].resourceName == "PvZ2iPDb9HEUHYbWwQaTZ.jpg")
        #expect(images[5].width == 4000)
        #expect(images[5].height == 1358)
    }

    @Test func splitsRunsSeparatedByOtherBlocks() throws {
        // Swap the fifth 360° image for a gallery: the run breaks in two.
        var json = try #require(String(data: fixtureData(), encoding: .utf8))
        json = json.replacingOccurrences(
            of: "\"n-LDpXuj\": { \"type\": \"image360\"",
            with: "\"n-LDpXuj\": { \"type\": \"gallery\", \"children\": []"
        )
        let story = try StoryMapParser.parse(data: Data(json.utf8), itemID: "x")
        let counts = story.chapters.compactMap { chapter -> Int? in
            if case .image360(let images) = chapter.media { return images.count }
            return nil
        }
        #expect(counts == [4, 5])
    }

    @Test func image360ChapterSurvivesCacheRoundTrip() throws {
        let story = try parseFixture()
        let decoded = try JSONDecoder().decode(Story.self, from: JSONEncoder().encode(story))
        #expect(decoded == story)
    }

    // MARK: - Environments

    @Test func storyImagesAreEnvironmentsSteppedInStoryOrder() throws {
        let model = AppModel()
        model.story = try parseFixture()
        let images = model.storyPanoramas
        #expect(images.count == 10)

        let thirdID = AppModel.environmentID(for: images[2])
        let environment = try #require(model.environment(id: thirdID))
        #expect(environment.subtitle == "360° image 3 of 10")
        #expect(!environment.isModel)
        guard case .storyPanorama(let itemID, let image) = environment.content else {
            Issue.record("Expected a story panorama")
            return
        }
        #expect(itemID == "x")
        #expect(image == images[2])

        model.activeEnvironmentID = thirdID
        #expect(model.steppableEnvironmentIDs == images.map(AppModel.environmentID(for:)))
        #expect(model.chapterIndex(ofEnvironment: thirdID) == 0)

        // Anywhere else, the toolbar steps through the Environments tab.
        model.activeEnvironmentID = nil
        #expect(model.steppableEnvironmentIDs == model.enterableEnvironmentIDs)
    }

    @Test func narrowPanoramaIsBandedAroundTheHorizon() throws {
        let width = 400, height = 136
        let ctx = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(ctx.makeImage())

        let padded = try #require(Panorama.padToEquirectangular(image, height: width / 2))
        #expect(padded.width == 400)
        #expect(padded.height == 200)
    }
}

private final class BundleToken {}
