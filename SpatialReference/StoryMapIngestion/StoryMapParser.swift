//
//  StoryMapParser.swift
//  SpatialReference
//

import Foundation

/// Parses a StoryMap's `published_data.json` (an internal, undocumented
/// ArcGIS StoryMaps format) into our own `Story` model.
///
/// The format is a flat graph: a `nodes` dictionary keyed by node id, each
/// node has a `type`, a `data` payload whose shape depends on `type`, and
/// sometimes ordered `children` node ids. A top-level `resources`
/// dictionary holds shared media/web-map references. This parser only
/// understands the node types confirmed by inspecting a real published
/// story (see plan step 1 spike) and skips anything else rather than
/// failing, since the schema has many more node types than we need.
enum StoryMapParser {
    enum ParseError: LocalizedError {
        case invalidJSON
        case missingRootNode
        case noStoryNode

        var errorDescription: String? {
            switch self {
            case .invalidJSON: return "Not a valid StoryMap JSON document."
            case .missingRootNode: return "StoryMap JSON has no root node."
            case .noStoryNode: return "StoryMap JSON has no top-level story node."
            }
        }
    }

    static func parse(data: Data, itemID: String) throws -> Story {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidJSON
        }
        guard let nodes = root["nodes"] as? [String: [String: Any]] else {
            throw ParseError.missingRootNode
        }
        let resources = root["resources"] as? [String: [String: Any]] ?? [:]

        guard let storyNode = nodes.values.first(where: { $0["type"] as? String == "story" }) else {
            throw ParseError.noStoryNode
        }

        let cover = nodes.values.first { $0["type"] as? String == "storycover" }
        let coverData = cover?["data"] as? [String: Any]
        let title = coverData?["title"] as? String ?? "Untitled Story"
        let summary = coverData?["summary"] as? String ?? ""

        // Walk the story's top-level children in order. "immersive" (sidecar)
        // sections contribute one chapter per slide; gallery blocks
        // contribute one carousel chapter each.
        let topLevelChildren = storyNode["children"] as? [String] ?? []
        var chapters: [Chapter] = []
        for childID in topLevelChildren {
            guard let node = nodes[childID], let type = node["type"] as? String else { continue }
            switch type {
            case "immersive":
                let slideIDs = node["children"] as? [String] ?? []
                for slideID in slideIDs {
                    guard let slideNode = nodes[slideID] else { continue }
                    chapters.append(makeChapter(id: slideID, slideNode: slideNode, nodes: nodes, resources: resources))
                }
            case "gallery":
                let items = makeGalleryItems(galleryNode: node, nodes: nodes, resources: resources)
                if !items.isEmpty {
                    chapters.append(Chapter(id: childID, narrationText: "", media: .gallery(items: items)))
                }
            case "tour":
                if let media = makeTour(tourNode: node, nodes: nodes, resources: resources) {
                    chapters.append(Chapter(id: childID, narrationText: "", media: media))
                }
            default:
                continue
            }
        }

        return Story(itemID: itemID, title: title, summary: decodeHTMLEntities(summary), chapters: chapters)
    }

    private static func makeChapter(
        id: String,
        slideNode: [String: Any],
        nodes: [String: [String: Any]],
        resources: [String: [String: Any]]
    ) -> Chapter {
        let childIDs = slideNode["children"] as? [String] ?? []

        var narrationParts: [String] = []
        var media: ChapterMedia?

        for childID in childIDs {
            guard let child = nodes[childID], let type = child["type"] as? String else { continue }
            if type == "immersive-narrative-panel" {
                narrationParts.append(contentsOf: extractText(from: child, nodes: nodes))
            } else if media == nil, let parsed = makeMedia(type: type, node: child, resources: resources) {
                media = parsed
            }
        }

        let narrationText = decodeHTMLEntities(narrationParts.joined(separator: " "))
        return Chapter(id: id, narrationText: narrationText, media: media)
    }

    /// Builds carousel items from a gallery block's image children.
    ///
    /// A gallery child is an `image` node whose `data.image` points at a
    /// still-image resource. When the child also has `config.resourceId`
    /// pointing at a `usdz` resource, the child is really a 3D model and the
    /// still image is just its poster.
    private static func makeGalleryItems(
        galleryNode: [String: Any],
        nodes: [String: [String: Any]],
        resources: [String: [String: Any]]
    ) -> [GalleryItem] {
        var items: [GalleryItem] = []
        for childID in galleryNode["children"] as? [String] ?? [] {
            guard let child = nodes[childID], child["type"] as? String == "image" else { continue }
            let data = child["data"] as? [String: Any]
            let caption = (data?["caption"] as? String).map(decodeHTMLEntities).flatMap { $0.isEmpty ? nil : $0 }
            let posterName = itemResourceName(resources[data?["image"] as? String ?? ""], ofTypes: ["image"])

            let config = child["config"] as? [String: Any]
            if let modelResourceID = config?["resourceId"] as? String,
               let modelName = itemResourceName(resources[modelResourceID], ofTypes: ["usdz", "reality"]) {
                items.append(GalleryItem(
                    id: childID,
                    kind: .model(resourceName: modelName),
                    posterResourceName: posterName,
                    title: caption ?? displayName(forResource: modelName)
                ))
            } else if let posterName {
                items.append(GalleryItem(
                    id: childID,
                    kind: .image(resourceName: posterName),
                    posterResourceName: nil,
                    title: caption ?? "Image"
                ))
            }
        }
        return items
    }

    /// Builds a guided tour from a `tour` node.
    ///
    /// The tour's `data.places` list the stops in order. Each place names a
    /// `featureId` whose point lives in the `tour-map` node's `geometries`, a
    /// `title` text node, `contents` (paragraph text and `audio` nodes) and a
    /// `media` carousel whose first image is the stop's picture. That image's
    /// `config.resource` points at the zip holding the stop's 3D model.
    /// Places without a point are skipped, since they can't go on the map.
    private static func makeTour(
        tourNode: [String: Any],
        nodes: [String: [String: Any]],
        resources: [String: [String: Any]]
    ) -> ChapterMedia? {
        guard let data = tourNode["data"] as? [String: Any],
              let places = data["places"] as? [[String: Any]] else { return nil }
        let mapData = (data["map"] as? String).flatMap { nodes[$0] }?["data"] as? [String: Any]
        let geometries = mapData?["geometries"] as? [String: [String: Any]] ?? [:]

        var stops: [TourStop] = []
        for (index, place) in places.enumerated() {
            guard let featureID = place["featureId"] as? String,
                  let point = (geometries[featureID]?["nodes"] as? [[String: Any]])?.first,
                  let latitude = (point["lat"] as? NSNumber)?.doubleValue,
                  let longitude = (point["long"] as? NSNumber)?.doubleValue else { continue }

            let titleNode = (place["title"] as? String).flatMap { nodes[$0] }
            let title = titleNode.flatMap { extractText(from: $0, nodes: nodes).first }.map(plainText) ?? ""

            var paragraphs: [String] = []
            var audioName: String?
            for contentID in place["contents"] as? [String] ?? [] {
                guard let content = nodes[contentID] else { continue }
                if content["type"] as? String == "audio" {
                    let audioResourceID = (content["data"] as? [String: Any])?["audio"] as? String ?? ""
                    audioName = audioName ?? itemResourceName(resources[audioResourceID], ofTypes: ["audio"])
                } else {
                    paragraphs.append(contentsOf: extractText(from: content, nodes: nodes).map(plainText))
                }
            }

            // The first image of the stop's media carousel (or the media
            // node itself when it's a bare image).
            var imageNode = (place["media"] as? String).flatMap { nodes[$0] }
            if imageNode?["type"] as? String != "image" {
                imageNode = (imageNode?["children"] as? [String] ?? [])
                    .lazy.compactMap { nodes[$0] }
                    .first { $0["type"] as? String == "image" }
            }
            let imageData = imageNode?["data"] as? [String: Any]
            let posterName = itemResourceName(resources[imageData?["image"] as? String ?? ""], ofTypes: ["image"])
            let imageConfig = imageNode?["config"] as? [String: Any]
            let modelResourceID = imageConfig?["resource"] as? String ?? imageConfig?["resourceId"] as? String
            let modelName = modelResourceID.flatMap { modelResourceName(resources[$0]) }

            stops.append(TourStop(
                id: place["id"] as? String ?? featureID,
                title: title.isEmpty ? "Stop \(index + 1)" : title,
                narrationText: paragraphs.filter { !$0.isEmpty }.joined(separator: " "),
                latitude: latitude,
                longitude: longitude,
                audioResourceName: audioName,
                posterResourceName: posterName,
                modelResourceName: modelName
            ))
        }
        guard !stops.isEmpty else { return nil }
        return .tour(stops: stops, isThreeD: mapData?["mode"] as? String == "3d")
    }

    /// The filename of a resource holding a 3D model. Gallery models are typed
    /// `usdz`/`reality` item resources; tour image nodes reference untyped
    /// `file-resource` zips. Either way the file is fetched as an item resource.
    private static func modelResourceName(_ resource: [String: Any]?) -> String? {
        guard let resource, let data = resource["data"] as? [String: Any],
              let name = data["resourceId"] as? String else { return nil }
        if let type = resource["type"] as? String {
            return ["usdz", "reality"].contains(type) ? name : nil
        }
        let fileExtension = (name as NSString).pathExtension.lowercased()
        return (["zip"] + StoryAssetStore.modelExtensions).contains(fileExtension) ? name : nil
    }

    /// The item-resource filename of an `item-resource`-provider resource of
    /// one of the given types, or nil when it's some other kind of resource.
    private static func itemResourceName(_ resource: [String: Any]?, ofTypes types: [String]) -> String? {
        guard let resource, let type = resource["type"] as? String, types.contains(type),
              let data = resource["data"] as? [String: Any],
              data["provider"] as? String ?? "item-resource" == "item-resource" else { return nil }
        return data["resourceId"] as? String
    }

    /// "space-cosmonaut_v2.zip" -> "Space Cosmonaut V2".
    private static func displayName(forResource name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        return base
            .replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
            .capitalized
    }

    /// Recursively collects `text` node contents beneath a narrative panel.
    private static func extractText(from node: [String: Any], nodes: [String: [String: Any]]) -> [String] {
        var results: [String] = []
        if node["type"] as? String == "text", let data = node["data"] as? [String: Any], let text = data["text"] as? String, !text.isEmpty {
            results.append(text)
        }
        for childID in (node["children"] as? [String] ?? []) {
            if let child = nodes[childID] {
                results.append(contentsOf: extractText(from: child, nodes: nodes))
            }
        }
        return results
    }

    private static func makeMedia(
        type: String,
        node: [String: Any],
        resources: [String: [String: Any]]
    ) -> ChapterMedia? {
        guard let data = node["data"] as? [String: Any] else { return nil }
        let caption = data["caption"] as? String

        switch type {
        case "webmap":
            guard let resourceID = data["map"] as? String,
                  let resource = resources[resourceID],
                  let resourceData = resource["data"] as? [String: Any],
                  let itemID = resourceData["itemId"] as? String else {
                return nil
            }
            return .scene(itemID: itemID, caption: caption.map(decodeHTMLEntities), camera: extractCamera(from: resourceData))

        case "image":
            guard let resourceID = data["image"] as? String,
                  let resource = resources[resourceID],
                  let resourceData = resource["data"] as? [String: Any],
                  let resourceName = resourceData["resourceId"] as? String else {
                return nil
            }
            return .image(resourceName: resourceName, caption: caption.map(decodeHTMLEntities))

        case "embed":
            guard let urlString = data["url"] as? String, let url = URL(string: urlString) else { return nil }
            return .embed(url: url, title: (data["title"] as? String).map(decodeHTMLEntities))

        default:
            return nil
        }
    }

    private static func extractCamera(from webmapResourceData: [String: Any]) -> SceneCamera? {
        guard let viewpoint = webmapResourceData["viewpoint"] as? [String: Any],
              let camera = viewpoint["camera"] as? [String: Any],
              let position = camera["position"] as? [String: Any],
              let spatialReference = position["spatialReference"] as? [String: Any],
              let wkid = (spatialReference["wkid"] as? Int) ?? (spatialReference["latestWkid"] as? Int),
              let x = position["x"] as? Double,
              let y = position["y"] as? Double else {
            return nil
        }
        let z = position["z"] as? Double ?? 0
        let heading = camera["heading"] as? Double ?? 0
        let tilt = camera["tilt"] as? Double ?? 0
        return SceneCamera(wkid: wkid, x: x, y: y, z: z, heading: heading, tilt: tilt)
    }

    /// Rich text as plain, speakable text: tags dropped, entities decoded,
    /// whitespace collapsed.
    private nonisolated static func plainText(_ html: String) -> String {
        let stripped = html
            .replacingOccurrences(of: "<br\\s*/?>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeHTMLEntities(stripped)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static let namedHTMLEntities: [String: String] = [
        "&amp;": "&", "&apos;": "'", "&quot;": "\"", "&lt;": "<", "&gt;": ">", "&nbsp;": "\u{00A0}"
    ]

    /// Decodes the small set of HTML entities StoryMaps text nodes use
    /// (named entities plus numeric character references), without pulling
    /// in a full HTML parser for what is plain text with a few escapes.
    /// Pure string processing, so it's `nonisolated` to allow passing it as a
    /// function reference (e.g. to `Optional.map`) without actor hops.
    private nonisolated static func decodeHTMLEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }

        var result = string
        for (entity, replacement) in namedHTMLEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        while let range = result.range(of: #"&#x?[0-9A-Fa-f]+;"#, options: .regularExpression) {
            let match = result[range]
            let digitsStart = match.index(match.startIndex, offsetBy: match.hasPrefix("&#x") ? 3 : 2)
            let digitsEnd = match.index(before: match.endIndex)
            let digits = match[digitsStart..<digitsEnd]
            let isHex = match.hasPrefix("&#x")
            guard let scalarValue = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(scalarValue) else {
                break
            }
            result.replaceSubrange(range, with: String(Character(scalar)))
        }

        return result
    }
}
