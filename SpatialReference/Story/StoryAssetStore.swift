//
//  StoryAssetStore.swift
//  SpatialReference
//

import Foundation

/// Downloads a story's media from its portal item and keeps it on disk, so a
/// carousel page only hits the network the first time it's shown.
///
/// Files live in the Caches directory (the system may purge them; they're
/// simply re-downloaded), one folder per story item.
enum StoryAssetStore {
    enum AssetError: LocalizedError {
        case noModelInArchive(String)

        var errorDescription: String? {
            switch self {
            case .noModelInArchive(let name): return "\(name) doesn't contain a .usdz or .reality model."
            }
        }
    }

    /// File extensions of the 3D model formats StoryMaps items can carry.
    nonisolated static let modelExtensions = ["usdz", "reality"]

    /// A local `.usdz` or `.reality` file for a 3D model resource. StoryMaps
    /// stores these as a `.zip` wrapping the model: the archive is downloaded
    /// and the model extracted. A bare model resource is used as-is.
    static func modelURL(itemID: String, resourceName: String, session: ArcGISOnlineSession) async throws -> URL {
        let folder = try directory(for: itemID)
        // The format is only known once the archive is opened, so check the
        // cache for each possible extension.
        for fileExtension in modelExtensions {
            let cached = folder.appendingPathComponent(cacheName(for: resourceName, extension: fileExtension))
            if isCached(cached) { return cached }
        }

        let downloaded = try await session.fetchResourceData(itemID: itemID, resourceName: resourceName)
        let (model, fileExtension) = try await Task.detached { () -> (Data, String) in
            let bareExtension = (resourceName as NSString).pathExtension.lowercased()
            if modelExtensions.contains(bareExtension) { return (downloaded, bareExtension) }

            let archive = try ZipArchive(data: downloaded)
            guard let entry = archive.firstEntry(withExtensions: modelExtensions) else {
                throw AssetError.noModelInArchive(resourceName)
            }
            return (try archive.extract(entry), (entry.path as NSString).pathExtension.lowercased())
        }.value

        let target = folder.appendingPathComponent(cacheName(for: resourceName, extension: fileExtension))
        try model.write(to: target, options: .atomic)
        return target
    }

    /// The bytes of an image resource, from disk when already downloaded.
    static func imageData(itemID: String, resourceName: String, session: ArcGISOnlineSession) async throws -> Data {
        let target = try directory(for: itemID).appendingPathComponent(cacheName(for: resourceName, extension: nil))
        if isCached(target), let data = try? Data(contentsOf: target) { return data }

        let data = try await session.fetchResourceData(itemID: itemID, resourceName: resourceName)
        try? data.write(to: target, options: .atomic)
        return data
    }

    private static func isCached(_ url: URL) -> Bool {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return size > 0
    }

    private static func directory(for itemID: String) throws -> URL {
        let directory = try FileManager.default
            .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("StoryAssets", isDirectory: true)
            .appendingPathComponent(itemID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A flat, filesystem-safe filename derived from a resource name (which
    /// can contain path separators). `extension` replaces the original one.
    private static func cacheName(for resourceName: String, extension newExtension: String?) -> String {
        let flat = resourceName.replacingOccurrences(of: "/", with: "_")
        guard let newExtension else { return flat }
        return (flat as NSString).deletingPathExtension + "." + newExtension
    }
}
