//
//  ImportedEnvironmentTests.swift
//  SpatialReferenceTests
//

import Testing
import RealityKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import SpatialReference

@MainActor
struct ImportedEnvironmentTests {

    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ImportedEnvironmentTests-\(UUID().uuidString)", isDirectory: true)

    private var storeDirectory: URL { root.appendingPathComponent("store", isDirectory: true) }

    /// Writes a solid-gray PNG of the given size to pick from.
    private func makeImage(named name: String, width: Int, height: Int) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let ctx = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = root.appendingPathComponent(name)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(ctx.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private func makeFile(named name: String) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(name)
        try Data("model".utf8).write(to: url)
        return url
    }

    @Test func classifiesPickedFiles() throws {
        #expect(try ImportedEnvironmentStore.kind(of: URL(fileURLWithPath: "/a/pano.jpg")) == .panorama)
        #expect(try ImportedEnvironmentStore.kind(of: URL(fileURLWithPath: "/a/pano.HEIC")) == .panorama)
        #expect(try ImportedEnvironmentStore.kind(of: URL(fileURLWithPath: "/a/robot.usdz")) == .model)
        #expect(try ImportedEnvironmentStore.kind(of: URL(fileURLWithPath: "/a/scene.reality")) == .model)
        #expect(throws: ImportedEnvironmentStore.ImportError.self) {
            try ImportedEnvironmentStore.kind(of: URL(fileURLWithPath: "/a/notes.txt"))
        }
    }

    @Test func importsAPanoramaWithThumbnailAndPersistsIt() async throws {
        let store = ImportedEnvironmentStore(directory: storeDirectory)
        let item = try await store.add(from: makeImage(named: "Beach Sunset.png", width: 400, height: 200))

        #expect(item.kind == .panorama)
        #expect(item.title == "Beach Sunset")
        #expect(item.isEquirectangular)
        #expect(FileManager.default.fileExists(atPath: store.url(for: item).path))
        #expect(FileManager.default.fileExists(atPath: store.thumbnailURL(for: item).path))

        let reopened = ImportedEnvironmentStore(directory: storeDirectory)
        #expect(reopened.items == [item])
    }

    @Test func flagsPhotosThatAreNotTwoToOne() async throws {
        let store = ImportedEnvironmentStore(directory: storeDirectory)
        let item = try await store.add(from: makeImage(named: "square.png", width: 300, height: 300))
        #expect(!item.isEquirectangular)
    }

    @Test func scalesDownOversizedPanoramas() async throws {
        let store = ImportedEnvironmentStore(directory: storeDirectory)
        let width = ImportedEnvironmentStore.maxPanoramaWidth * 2
        let item = try await store.add(from: makeImage(named: "huge.png", width: width, height: width / 2))

        let source = try #require(CGImageSourceCreateWithURL(store.url(for: item) as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == ImportedEnvironmentStore.maxPanoramaWidth)
        #expect(item.isEquirectangular)
    }

    @Test func importsAndRemovesModels() async throws {
        let store = ImportedEnvironmentStore(directory: storeDirectory)
        let usdz = try await store.add(from: makeFile(named: "robot.usdz"))
        let reality = try await store.add(from: makeFile(named: "scene.reality"))

        #expect(usdz.kind == .model && !usdz.isRealityFile)
        #expect(reality.kind == .model && reality.isRealityFile)

        store.remove(usdz)
        #expect(store.items == [reality])
        #expect(!FileManager.default.fileExists(atPath: store.url(for: usdz).path))
        #expect(ImportedEnvironmentStore(directory: storeDirectory).items == [reality])
    }

    @Test func importsPLYPointCloudsWithoutReadingEveryPoint() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("Garden Scan.ply")
        try PLYPointCloudTests.splatPLY(count: 2).write(to: url)
        let store = ImportedEnvironmentStore(directory: storeDirectory)
        let item = try await store.add(from: url)

        #expect(item.kind == .pointCloud)
        #expect(item.title == "Garden Scan")
        #expect(item.pointCount == 2)
        #expect(item.isGaussianSplat == true)
        #expect(item.subtitle == "Gaussian splat · 2 splats")
        #expect(ImportedEnvironmentStore(directory: storeDirectory).items == [item])
    }

    @Test func rejectsFilesThatAreNotReallyPLY() async throws {
        let store = ImportedEnvironmentStore(directory: storeDirectory)
        await #expect(throws: ImportedEnvironmentStore.ImportError.self) {
            try await store.add(from: makeFile(named: "fake.ply"))
        }
        #expect(store.items.isEmpty)
    }
}

struct PLYPointCloudTests {

    /// A binary little-endian 3DGS file with `count` splats.
    static func splatPLY(count: Int) -> Data {
        let names = ["x", "y", "z", "nx", "ny", "nz", "f_dc_0", "f_dc_1", "f_dc_2", "opacity",
                     "scale_0", "scale_1", "scale_2", "rot_0", "rot_1", "rot_2", "rot_3"]
        var data = Data("""
        ply
        format binary_little_endian 1.0
        element vertex \(count)
        \(names.map { "property float \($0)" }.joined(separator: "\n"))
        end_header

        """.utf8)
        for i in 0..<count {
            // Position i, color dc 1, opacity 2, scale -3, rotation identity (w first).
            let values: [Float] = [Float(i), Float(i) * 2, -Float(i), 0, 0, 0, 1, 1, 1, 2, -3, -3, -3, 2, 0, 0, 0]
            for v in values { withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
        }
        return data
    }

    @Test func classifiesPLYAsPointCloud() throws {
        #expect(try ImportedEnvironmentStore.kind(of: URL(fileURLWithPath: "/a/scan.PLY")) == .pointCloud)
    }

    @Test func readsBinaryGaussianSplats() throws {
        let cloud = try PLYPointCloud(data: Self.splatPLY(count: 3))
        #expect(cloud.isGaussianSplat)
        #expect(cloud.count == 3)
        #expect(cloud.positions == [0, 0, 0, 1, 2, -1, 2, 4, -2])
        #expect(cloud.boundsMin == [0, 0, -2])
        #expect(cloud.boundsMax == [2, 4, 0])
        #expect(cloud.opacities == [2, 2, 2])
        #expect(Array(cloud.scales.prefix(3)) == [-3, -3, -3])
        // Normalized and reordered to x y z w.
        #expect(Array(cloud.rotations.prefix(4)) == [0, 0, 0, 1])
        #expect(Array(cloud.colors.prefix(3)) == [1, 1, 1])
    }

    @Test func readsAsciiColoredPointsAfterSkippingFaces() throws {
        let ply = """
        ply
        format ascii 1.0
        comment made by hand
        element face 1
        property list uchar int vertex_indices
        element vertex 2
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header
        3 0 1 1
        0 0 0 255 0 0
        1 1 1 0 0 255

        """
        let cloud = try PLYPointCloud(data: Data(ply.utf8))
        #expect(!cloud.isGaussianSplat)
        #expect(cloud.count == 2)
        #expect(cloud.positions == [0, 0, 0, 1, 1, 1])
        // Red back out of the zeroth-order harmonic.
        let red = cloud.colors.prefix(3).map { 0.5 + PLYPointCloud.shC0 * $0 }
        #expect(abs(red[0] - 1) < 1e-5 && abs(red[1]) < 1e-5 && abs(red[2]) < 1e-5)
        #expect(cloud.scales.count == 6 && cloud.rotations.count == 8 && cloud.opacities.count == 2)
    }

    @Test func readsBigEndianBinaryAfterSkippingBinaryFaces() throws {
        var data = Data("""
        ply
        format binary_big_endian 1.0
        element face 1
        property list uchar int vertex_indices
        element vertex 1
        property double x
        property double y
        property double z
        end_header

        """.utf8)
        data.append(3)
        for i: Int32 in [0, 0, 0] { withUnsafeBytes(of: i.bigEndian) { data.append(contentsOf: $0) } }
        for v: Double in [1.5, -2, 3] { withUnsafeBytes(of: v.bitPattern.bigEndian) { data.append(contentsOf: $0) } }

        let cloud = try PLYPointCloud(data: data)
        #expect(cloud.positions == [1.5, -2, 3])
    }

    @MainActor
    @Test func buildsACenteredTappableEntity() async throws {
        let cloud = try PLYPointCloud(data: Self.splatPLY(count: 3))
        let entity = try await cloud.makeEntity()
        #expect(entity.children.contains { $0.components.has(CollisionComponent.self) })
        #expect(entity.children.contains { $0.position == -cloud.center })
    }

    @Test func rejectsTruncatedAndInvalidFiles() {
        #expect(throws: PLYPointCloud.ParseError.notPLY) { try PLYPointCloud(data: Data("hello".utf8)) }
        let truncated = Self.splatPLY(count: 4).dropLast(10)
        #expect(throws: PLYPointCloud.ParseError.truncated) { try PLYPointCloud(data: Data(truncated)) }
        let empty = Data("ply\nformat ascii 1.0\nelement vertex 0\nproperty float x\nproperty float y\nproperty float z\nend_header\n".utf8)
        #expect(throws: PLYPointCloud.ParseError.missingVertices) { try PLYPointCloud(data: empty) }
    }
}
