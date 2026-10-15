//
//  TourTests.swift
//  SpatialReferenceTests
//

import Testing
import Foundation
@testable import SpatialReference

@MainActor
struct TourTests {

    private func parseFixture() throws -> Story {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "pyramids-tour-draft", withExtension: "json"))
        return try StoryMapParser.parse(data: Data(contentsOf: url), itemID: "x")
    }

    @Test func parsesGuidedTourIntoOrderedStops() throws {
        let story = try parseFixture()

        #expect(story.title == "Discover the origins of Pyramids")
        #expect(story.chapters.count == 1)
        guard case .tour(let stops, let isThreeD) = story.chapters.first?.media else {
            Issue.record("Expected a tour chapter, got \(String(describing: story.chapters.first?.media))")
            return
        }

        #expect(isThreeD)
        #expect(stops.map(\.title) == ["Pyramid of Kufu", "Pyramid of Kafre", "Pyramid of Menkaure", "The Great Sphinx of Giza"])
        #expect(stops.map(\.audioResourceName) == [
            "hrN2q5CS0WJNp4qB3JBWy.mp3", "S0r0V9IXY0Nu-gTjG2CRU.mp3", "Mq-4Bb8ZGa6gJUBJqqPcp.mp3", "3hZLS7ebWwnkFAjvGRx7s.mp3",
        ])
        #expect(stops.map(\.modelResourceName) == ["1dpk5hd321y0cogo.zip", "7bl6f9guyjrd4bbt.zip", nil, "d45rfc8poj097vvw.zip"])
        #expect(stops.map(\.posterResourceName) == [
            "b5cb8b74-46e4-46ab-ba33-d691a9530945.jpeg", "z-PCqV8anou-wqKSGX_xT.jpg",
            "l8-ow9FNPDMuWQq1CNMYL.jpg", "c8ebda86-1f44-4418-98a5-f3706eb9cc2b.jpeg",
        ])

        let first = stops[0]
        #expect(abs(first.latitude - 30.0360892) < 1e-6)
        #expect(abs(first.longitude - 31.2421232) < 1e-6)
        // Narration is plain text: the paragraph's <strong> tags are dropped.
        #expect(first.narrationText.hasPrefix("The Great Pyramid was built for Pharaoh Khufu."))
        #expect(!first.narrationText.contains("<"))
    }

    @Test func tourChapterSurvivesCacheRoundTrip() throws {
        let story = try parseFixture()
        let decoded = try JSONDecoder().decode(Story.self, from: JSONEncoder().encode(story))
        #expect(decoded == story)
    }
}

private final class BundleToken {}
