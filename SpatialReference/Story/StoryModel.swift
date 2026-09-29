//
//  StoryModel.swift
//  SpatialReference
//

import Foundation

/// Our own domain model for a mixed-reality-ready story, decoupled from
/// ArcGIS StoryMaps' internal JSON node graph. `StoryMapParser` produces
/// this from the raw `published_data.json` resource of a StoryMap item.
struct Story: Codable, Equatable {
    var itemID: String
    var title: String
    var summary: String
    var chapters: [Chapter]
}

struct Chapter: Codable, Equatable, Identifiable {
    var id: String
    var narrationText: String
    var media: ChapterMedia?
}

enum ChapterMedia: Codable, Equatable {
    /// A web scene/map to fly the teleport portal's camera to.
    case scene(itemID: String, caption: String?, camera: SceneCamera?)
    /// A story image, referenced by its item-resource filename.
    case image(resourceName: String, caption: String?)
    /// An embedded external link (e.g. another story, an experience app).
    case embed(url: URL, title: String?)
}

/// A 3D camera viewpoint captured from a StoryMap's immersive web scene,
/// used to fly the ArcGIS SceneView portal to the right spot.
///
/// `x`/`y`/`z` are in the units of `wkid` as published by the story, which
/// may be geographic (WGS84, degrees) or Web Mercator (meters) depending on
/// the story's spatial reference — never assume degrees without checking.
struct SceneCamera: Codable, Equatable {
    var wkid: Int
    var x: Double
    var y: Double
    var z: Double
    var heading: Double
    var tilt: Double
}
