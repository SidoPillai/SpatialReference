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
    /// A StoryMaps gallery block, shown as a carousel of images and 3D models.
    case gallery(items: [GalleryItem])
    /// A StoryMaps guided tour: numbered stops projected on a (usually 3D)
    /// map, each with its own narration audio and media.
    case tour(stops: [TourStop], isThreeD: Bool)
    /// A run of consecutive StoryMaps 360° image blocks, shown one after the
    /// other and entered as panoramas around the viewer.
    case image360(images: [Image360])
}

/// One StoryMaps 360° image block: an equirectangular photo spanning the full
/// 360° horizontally. Some cover less than 180° vertically (`width` is more
/// than twice `height`); those are banded around the horizon.
struct Image360: Codable, Equatable, Identifiable {
    /// The image360 node's id.
    var id: String
    /// Item-resource filename of the panorama.
    var resourceName: String
    var caption: String?
    /// The panorama's size in pixels, as published by the story.
    var width: Int?
    var height: Int?
}

/// One numbered stop of a guided tour.
struct TourStop: Codable, Equatable, Identifiable {
    /// The tour place's id.
    var id: String
    var title: String
    /// Plain text of the stop's paragraphs (HTML tags removed). Spoken with
    /// text-to-speech when the stop has no recorded audio.
    var narrationText: String
    /// WGS84 position of the stop's point on the tour map.
    var latitude: Double
    var longitude: Double
    /// Item-resource filename of the stop's narration recording (an mp3).
    var audioResourceName: String?
    /// Item-resource filename of the stop's image, shown as the model's
    /// poster (or on its own when there's no model).
    var posterResourceName: String?
    /// Resource holding the stop's interactive 3D model: a `.zip` wrapping a
    /// `.usdz` or `.reality` file, attached to the stop's image node.
    var modelResourceName: String?
}

/// One page of a gallery carousel.
struct GalleryItem: Codable, Equatable, Identifiable {
    enum Kind: Codable, Equatable {
        /// A plain picture, referenced by its item-resource filename.
        case image(resourceName: String)
        /// A 3D model. `resourceName` is the item resource holding the
        /// model: StoryMaps stores these as a `.zip` wrapping the `.usdz`
        /// (or occasionally the bare `.usdz`).
        case model(resourceName: String)
    }

    /// The gallery child's node id.
    var id: String
    var kind: Kind
    /// Item-resource filename of a still image to show while a model
    /// downloads (and as its thumbnail).
    var posterResourceName: String?
    var title: String
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
