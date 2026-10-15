//
//  ImportedEnvironmentStore.swift
//  SpatialReference
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A 360° image or 3D model the user picked from Files, copied into the app
/// so it's still there after a relaunch.
nonisolated struct ImportedEnvironment: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// An equirectangular image wrapped around the viewer.
        case panorama
        /// A `.usdz` or `.reality` file placed in the room.
        case model
        /// A `.ply` Gaussian splat capture or point cloud placed in the room.
        case pointCloud
    }

    let id: String
    var title: String
    let kind: Kind
    let fileName: String
    /// Width / height of a panorama; 2 for a true 360° image.
    var aspectRatio: Double?
    /// Number of points in a `.pointCloud`.
    var pointCount: Int?
    /// Whether a `.pointCloud` is a Gaussian splat capture rather than plain points.
    var isGaussianSplat: Bool?

    var isEquirectangular: Bool { abs((aspectRatio ?? 0) - 2) < 0.05 }
    var isRealityFile: Bool { (fileName as NSString).pathExtension.lowercased() == "reality" }

    var subtitle: String {
        switch kind {
        case .panorama: isEquirectangular ? "360° photo" : "Photo · not 2:1, so it may look stretched"
        case .model: isRealityFile ? "Reality scene" : "3D model"
        case .pointCloud:
            isGaussianSplat == true
                ? "Gaussian splat · \(Self.formatted(pointCount)) splats"
                : "Point cloud · \(Self.formatted(pointCount)) points"
        }
    }

    private static func formatted(_ count: Int?) -> String {
        (count ?? 0).formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
    }
}

/// The user's imported environments, kept in Application Support with a
/// JSON index.
@Observable
final class ImportedEnvironmentStore {

    enum ImportError: LocalizedError {
        case unsupportedType(String)
        case unreadableImage
        case unreadablePointCloud(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedType(let ext): "“.\(ext)” files can’t be opened as an environment. Pick a 360° image, .usdz, .reality or .ply file."
            case .unreadableImage: "This image couldn’t be read."
            case .unreadablePointCloud(let reason): reason
            }
        }
    }

    /// What the Files picker offers.
    nonisolated static let contentTypes: [UTType] = [.image, .usdz, .realityFile, PLYPointCloud.contentType]
    /// Larger panoramas are scaled down on import to keep the texture within
    /// what RealityKit loads comfortably.
    nonisolated static let maxPanoramaWidth = 8192

    private(set) var items: [ImportedEnvironment] = []
    @ObservationIgnored let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL) {
            items = (try? JSONDecoder().decode([ImportedEnvironment].self, from: data)) ?? []
        }
    }

    func url(for item: ImportedEnvironment) -> URL {
        directory.appendingPathComponent(item.fileName)
    }

    func thumbnailURL(for item: ImportedEnvironment) -> URL {
        Self.thumbnailURL(id: item.id, in: directory)
    }

    /// Copies a picked file into the store (scaling down an oversized
    /// panorama) and returns the new entry.
    func add(from source: URL) async throws -> ImportedEnvironment {
        let kind = try Self.kind(of: source)
        let item = try await Self.ingest(source, kind: kind, id: "imported-\(UUID().uuidString)", into: directory)
        items.append(item)
        save()
        return item
    }

    func remove(_ item: ImportedEnvironment) {
        try? FileManager.default.removeItem(at: url(for: item))
        try? FileManager.default.removeItem(at: thumbnailURL(for: item))
        items.removeAll { $0.id == item.id }
        save()
    }

    // MARK: - Private

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("ImportedEnvironments", isDirectory: true)
    }

    private nonisolated static func thumbnailURL(id: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id)-thumb.jpg")
    }

    nonisolated static func kind(of url: URL) throws -> ImportedEnvironment.Kind {
        let ext = url.pathExtension.lowercased()
        if ext == "ply" { return .pointCloud }
        guard let type = UTType(filenameExtension: ext) else { throw ImportError.unsupportedType(ext) }
        if type.conforms(to: .usdz) || type.conforms(to: .realityFile) { return .model }
        if type.conforms(to: .image) { return .panorama }
        throw ImportError.unsupportedType(ext)
    }

    /// File work happens off the main thread: picked files can be large, and
    /// may still be downloading from iCloud.
    @concurrent
    private nonisolated static func ingest(
        _ source: URL, kind: ImportedEnvironment.Kind, id: String, into directory: URL
    ) async throws -> ImportedEnvironment {
        // Files picked outside the app's container are security scoped.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let title = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension.lowercased()

        if kind == .pointCloud {
            // Read just the header up front; the points load when it opens.
            let header: PLYPointCloud.Header
            do {
                header = try PLYPointCloud.header(of: Data(contentsOf: source, options: .mappedIfSafe))
            } catch {
                throw ImportError.unreadablePointCloud(error.localizedDescription)
            }
            guard let vertex = header.elements.first(where: { $0.name == "vertex" }), vertex.count > 0 else {
                throw ImportError.unreadablePointCloud(PLYPointCloud.ParseError.missingVertices.localizedDescription)
            }
            let fileName = "\(id).ply"
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(fileName))
            return ImportedEnvironment(
                id: id, title: title, kind: .pointCloud, fileName: fileName,
                pointCount: vertex.count,
                isGaussianSplat: vertex.properties.contains { $0.name == "f_dc_0" }
            )
        }

        guard kind == .panorama else {
            let fileName = "\(id).\(ext)"
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(fileName))
            return ImportedEnvironment(id: id, title: title, kind: kind, fileName: fileName)
        }

        guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, height > 0 else {
            throw ImportError.unreadableImage
        }

        let fileName: String
        if max(width, height) > maxPanoramaWidth {
            fileName = "\(id).heic"
            guard let scaled = downsample(image, to: maxPanoramaWidth),
                  write(scaled, as: .heic, quality: 0.85, to: directory.appendingPathComponent(fileName)) else {
                throw ImportError.unreadableImage
            }
        } else {
            fileName = "\(id).\(ext)"
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(fileName))
        }
        if let thumbnail = downsample(image, to: 640) {
            _ = write(thumbnail, as: .jpeg, quality: 0.8, to: thumbnailURL(id: id, in: directory))
        }
        return ImportedEnvironment(
            id: id, title: title, kind: .panorama, fileName: fileName,
            aspectRatio: Double(width) / Double(height)
        )
    }

    private nonisolated static func downsample(_ source: CGImageSource, to maxPixelSize: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary)
    }

    private nonisolated static func write(_ image: CGImage, as type: UTType, quality: Double, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}
