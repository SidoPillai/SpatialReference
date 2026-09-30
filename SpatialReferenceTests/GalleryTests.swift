//
//  GalleryTests.swift
//  SpatialReferenceTests
//

import Testing
import Foundation
@testable import SpatialReference

@MainActor
struct GalleryTests {

    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: ext))
        return try Data(contentsOf: url)
    }

    // MARK: - Parser

    @Test func parsesGalleryWithUSDZResourcesIntoCarouselItems() throws {
        let story = try StoryMapParser.parse(data: fixture("ar-quick-look-published_data", "json"), itemID: "d94ade9fa6024da1aa811fdc800d0ae3")

        #expect(story.title == "AR Quick Look")
        let chapter = try #require(story.chapters.first)
        #expect(story.chapters.count == 1)
        guard case .gallery(let items) = chapter.media else {
            Issue.record("Expected a gallery chapter, got \(String(describing: chapter.media))")
            return
        }

        // Gallery order is preserved: three models, then the plain image.
        #expect(items.map(\.kind) == [
            .model(resourceName: "cosmonaut.zip"),
            .model(resourceName: "hab.zip"),
            .model(resourceName: "rover.zip"),
            .image(resourceName: "831b841f-4694-4264-92f5-5a1057420d91.jpeg"),
        ])
        #expect(items.map(\.title) == ["Cosmonaut", "Hab", "Rover", "Image"])
        #expect(items[0].posterResourceName == "831b841f-4694-4264-92f5-5a1057420d91.jpeg")
    }

    @Test func galleryChapterSurvivesCacheRoundTrip() throws {
        let story = try StoryMapParser.parse(data: fixture("ar-quick-look-published_data", "json"), itemID: "x")
        let decoded = try JSONDecoder().decode(Story.self, from: JSONEncoder().encode(story))
        #expect(decoded == story)
    }

    // MARK: - ZIP

    @Test func extractsUSDZFromDeflatedZipSkippingMacOSResourceForks() throws {
        let archive = try ZipArchive(data: fixture("model-deflated", "zip"))
        let entry = try #require(archive.firstEntry(withExtensions: ["usdz", "reality"]))
        #expect(entry.path == "sample.usdz")
        #expect(try archive.extract(entry) == fixture("model-sample", "usdz"))
    }

    @Test func extractsStoredEntries() throws {
        let archive = try ZipArchive(data: fixture("model-stored", "zip"))
        let entry = try #require(archive.firstEntry(withExtensions: ["usdz", "reality"]))
        #expect(try archive.extract(entry) == fixture("model-sample", "usdz"))
    }

    @Test func extractsRealityFilesToo() throws {
        // Same archive layout, but the model inside is a .reality file.
        let archive = try ZipArchive(data: fixture("model-reality", "zip"))
        let entry = try #require(archive.firstEntry(withExtensions: ["usdz", "reality"]))
        #expect(entry.path == "scene.reality")
        #expect(try archive.extract(entry) == fixture("model-reality-sample", "reality"))
        #expect(archive.firstEntry(withExtensions: ["usdz"]) == nil)
    }

    @Test func parsesRealityResourceTypeAsModel() throws {
        var json = try #require(String(data: fixture("ar-quick-look-published_data", "json"), encoding: .utf8))
        json = json.replacingOccurrences(of: "\"resourceId\":\"cosmonaut.zip\"},\"type\":\"usdz\"", with: "\"resourceId\":\"cosmonaut.zip\"},\"type\":\"reality\"")
        let story = try StoryMapParser.parse(data: Data(json.utf8), itemID: "x")
        guard case .gallery(let items) = story.chapters.first?.media else { Issue.record("no gallery"); return }
        #expect(items[0].kind == .model(resourceName: "cosmonaut.zip"))
    }

    @Test func rejectsNonZipData() {
        #expect(throws: ZipArchive.ZipError.self) {
            _ = try ZipArchive(data: Data("{\"error\":{\"code\":404}}".utf8))
        }
    }
}

private final class BundleToken {}
