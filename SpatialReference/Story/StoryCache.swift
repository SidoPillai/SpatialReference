//
//  StoryCache.swift
//  SpatialReference
//

import Foundation

/// Persists a parsed `Story` to disk so relaunching the app doesn't require
/// a live ArcGIS Online sign-in and re-parse every time (plan milestone-1,
/// step 2).
enum StoryCache {
    private static func url(for itemID: String) throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return directory.appendingPathComponent("story-\(itemID).json")
    }

    static func load(itemID: String) -> Story? {
        guard let url = try? url(for: itemID), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Story.self, from: data)
    }

    static func save(_ story: Story) {
        guard let url = try? url(for: story.itemID), let data = try? JSONEncoder().encode(story) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
