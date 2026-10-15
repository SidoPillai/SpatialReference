//
//  EnvironmentTests.swift
//  SpatialReferenceTests
//

import Testing
import CoreGraphics
import Foundation
import RealityKit
@testable import SpatialReference

@MainActor
struct EnvironmentTests {

    @Test func moonIsTheEnterableEnvironment() throws {
        let moon = try #require(ImmersiveEnvironment.catalog.first { $0.title == "The Moon" })
        #expect(moon.panorama == Panorama.moon)
        #expect(moon.isAvailable)
        #expect(ImmersiveEnvironment.catalog.filter(\.isAvailable).map(\.title) == ["The Moon"])
    }

    @Test func everyPanoramaHasSomethingToShow() {
        for env in ImmersiveEnvironment.catalog {
            guard let panorama = env.panorama else { continue }
            #expect(Panorama.hasContent(named: panorama), "\(env.title) has no panorama or placeholder")
        }
    }

    @Test func moonPanoramaIsBundled() {
        #expect(Panorama.bundledURL(named: Panorama.moon, in: Bundle(for: AppModel.self)) != nil)
    }

    @Test func moonPanoramaLoadsAsATexture() async throws {
        let texture = try await Panorama.texture(named: Panorama.moon)
        #expect(texture.width == 2 * texture.height)
    }

    @Test func placeholderIsAnEquirectangularImage() throws {
        let image = try #require(LunarPanoramaPainter.paint(width: 1024))
        #expect(image.width == 1024)
        #expect(image.height == 512)
    }

    @Test func seededGeneratorRepeats() {
        var a = SeededGenerator(seed: 42), b = SeededGenerator(seed: 42)
        #expect((0..<5).map { _ in a.next() } == (0..<5).map { _ in b.next() })
    }
}
