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

        // Walk the story's top-level children looking for "immersive"
        // (sidecar) sections, and flatten all of their slides in order.
        let topLevelChildren = storyNode["children"] as? [String] ?? []
        var chapters: [Chapter] = []
        for childID in topLevelChildren {
            guard let node = nodes[childID], node["type"] as? String == "immersive" else { continue }
            let slideIDs = node["children"] as? [String] ?? []
            for slideID in slideIDs {
                guard let slideNode = nodes[slideID] else { continue }
                chapters.append(makeChapter(id: slideID, slideNode: slideNode, nodes: nodes, resources: resources))
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

    private static let namedHTMLEntities: [String: String] = [
        "&amp;": "&", "&apos;": "'", "&quot;": "\"", "&lt;": "<", "&gt;": ">", "&nbsp;": "\u{00A0}"
    ]

    /// Decodes the small set of HTML entities StoryMaps text nodes use
    /// (named entities plus numeric character references), without pulling
    /// in a full HTML parser for what is plain text with a few escapes.
    private static func decodeHTMLEntities(_ string: String) -> String {
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
