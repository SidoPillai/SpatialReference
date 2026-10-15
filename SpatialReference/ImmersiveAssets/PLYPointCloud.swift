//
//  PLYPointCloud.swift
//  SpatialReference
//

import CoreGraphics
import Foundation
import Metal
import RealityKit
import UniformTypeIdentifiers

/// The vertices of a `.ply` file, ready to hand to RealityKit's Gaussian
/// splat renderer.
///
/// A 3D Gaussian Splatting capture (the `f_dc_*`, `scale_*`, `rot_*` and
/// `opacity` properties) keeps its own shape and color. Any other PLY, such
/// as a colored point cloud or a scanned mesh, shows each vertex as a small
/// round splat; faces are ignored.
nonisolated struct PLYPointCloud: Sendable {

    enum ParseError: LocalizedError, Equatable {
        case notPLY
        case unsupportedFormat(String)
        case missingVertices
        case truncated

        var errorDescription: String? {
            switch self {
            case .notPLY: "This isn’t a PLY file."
            case .unsupportedFormat(let detail): "This PLY file can’t be read (\(detail))."
            case .missingVertices: "This PLY file has no points to show."
            case .truncated: "This PLY file is incomplete."
            }
        }
    }

    /// What the Files picker offers for `.ply`.
    static let contentType = UTType(filenameExtension: "ply") ?? UTType(importedAs: "public.polygon-file-format")

    /// The zeroth-order spherical-harmonic constant: color = 0.5 + C0 · f_dc.
    static let shC0: Float = 0.282_094_79

    private(set) var count = 0
    /// Whether the file carries full Gaussian splat attributes.
    private(set) var isGaussianSplat = false
    /// Packed `x y z` per point.
    private(set) var positions: [Float] = []
    /// Packed log-space `x y z` scale per point.
    private(set) var scales: [Float] = []
    /// Packed `x y z w` (imaginary first, as `simd_quatf.vector`) per point.
    private(set) var rotations: [Float] = []
    /// One opacity logit per point.
    private(set) var opacities: [Float] = []
    /// Packed zeroth-order spherical-harmonic `r g b` per point.
    private(set) var colors: [Float] = []
    private(set) var boundsMin = SIMD3<Float>(repeating: .infinity)
    private(set) var boundsMax = SIMD3<Float>(repeating: -.infinity)
    /// Where most points are; see `percentileBounds`.
    private(set) var coreMin = SIMD3<Float>.zero
    private(set) var coreMax = SIMD3<Float>.zero

    /// The middle of where most points are, ignoring stray outliers.
    var center: SIMD3<Float> { (coreMin + coreMax) / 2 }
    /// The size of where most points are, ignoring stray outliers.
    var extents: SIMD3<Float> { coreMax - coreMin }

    // MARK: - Header

    struct Header: Sendable {
        enum Format: String, Sendable { case ascii, binaryLittleEndian = "binary_little_endian", binaryBigEndian = "binary_big_endian" }

        struct Property: Sendable {
            let name: String
            let type: ScalarType
            /// The count type of a list property, such as a face's indices.
            let listCountType: ScalarType?
        }

        struct Element: Sendable {
            let name: String
            let count: Int
            var properties: [Property] = []
        }

        let format: Format
        let elements: [Element]
        /// Where the body starts, just past `end_header`.
        let bodyOffset: Int
    }

    enum ScalarType: Sendable {
        case int8, uint8, int16, uint16, int32, uint32, float32, float64

        init?(_ name: String) {
            switch name {
            case "char", "int8": self = .int8
            case "uchar", "uint8": self = .uint8
            case "short", "int16": self = .int16
            case "ushort", "uint16": self = .uint16
            case "int", "int32": self = .int32
            case "uint", "uint32": self = .uint32
            case "float", "float32": self = .float32
            case "double", "float64": self = .float64
            default: return nil
            }
        }

        var size: Int {
            switch self {
            case .int8, .uint8: 1
            case .int16, .uint16: 2
            case .int32, .uint32, .float32: 4
            case .float64: 8
            }
        }

        var isInteger: Bool { self != .float32 && self != .float64 }
    }

    static func header(of data: Data) throws -> Header {
        // The header is plain ASCII and small; don't scan a huge body for it.
        let marker = Data("end_header".utf8)
        let searchEnd = min(data.count, 64 * 1024)
        guard data.starts(with: Data("ply".utf8)),
              let range = data.range(of: marker, in: data.startIndex..<data.startIndex + searchEnd) else {
            throw ParseError.notPLY
        }
        var bodyOffset = range.upperBound - data.startIndex
        if bodyOffset < data.count, data[data.startIndex + bodyOffset] == UInt8(ascii: "\r") { bodyOffset += 1 }
        if bodyOffset < data.count, data[data.startIndex + bodyOffset] == UInt8(ascii: "\n") { bodyOffset += 1 }

        let text = String(decoding: data[data.startIndex..<range.lowerBound], as: UTF8.self)
        var format: Header.Format?
        var elements: [Header.Element] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            switch words.first {
            case "format":
                guard words.count >= 2, let parsed = Header.Format(rawValue: words[1]) else {
                    throw ParseError.unsupportedFormat("format \(words.dropFirst().first ?? "?")")
                }
                format = parsed
            case "element":
                guard words.count == 3, let count = Int(words[2]), count >= 0 else {
                    throw ParseError.unsupportedFormat("element line")
                }
                elements.append(Header.Element(name: words[1], count: count))
            case "property":
                guard !elements.isEmpty else { throw ParseError.unsupportedFormat("property outside an element") }
                if words.count == 5, words[1] == "list", let countType = ScalarType(words[2]), let type = ScalarType(words[3]) {
                    elements[elements.count - 1].properties.append(.init(name: words[4], type: type, listCountType: countType))
                } else if words.count == 3, let type = ScalarType(words[1]) {
                    elements[elements.count - 1].properties.append(.init(name: words[2], type: type, listCountType: nil))
                } else {
                    throw ParseError.unsupportedFormat("property \(words.dropFirst().joined(separator: " "))")
                }
            default:
                continue  // ply, comment, obj_info
            }
        }
        guard let format else { throw ParseError.unsupportedFormat("no format line") }
        return Header(format: format, elements: elements, bodyOffset: bodyOffset)
    }

    // MARK: - Body

    init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    init(data: Data) throws {
        let header = try Self.header(of: data)
        guard let vertexIndex = header.elements.firstIndex(where: { $0.name == "vertex" }) else {
            throw ParseError.missingVertices
        }
        let vertex = header.elements[vertexIndex]
        guard vertex.count > 0 else { throw ParseError.missingVertices }
        guard !vertex.properties.contains(where: { $0.listCountType != nil }) else {
            throw ParseError.unsupportedFormat("list properties on vertices")
        }
        let names = vertex.properties.map(\.name)
        guard ["x", "y", "z"].allSatisfy(names.contains) else {
            throw ParseError.unsupportedFormat("vertices without x, y and z")
        }
        isGaussianSplat = ["f_dc_0", "f_dc_1", "f_dc_2", "opacity", "scale_0", "scale_1", "scale_2", "rot_0", "rot_1", "rot_2", "rot_3"]
            .allSatisfy(names.contains)

        // Each vertex's values in property order, whatever the file format.
        // Only the properties used below are read; a 3DGS file has dozens.
        let columns = Columns(vertex.properties)
        let n = vertex.count
        let splat = isGaussianSplat
        // Written through raw pointers: this loop runs a million times or
        // more, and array bookkeeping dominates it in Debug builds.
        var row = [Float](repeating: 0, count: vertex.properties.count)
        var positions = [Float](repeating: 0, count: n * 3)
        var colors = [Float](repeating: 0, count: n * 3)
        var scales = [Float](repeating: 0, count: splat ? n * 3 : 0)
        var rotations = [Float](repeating: 0, count: splat ? n * 4 : 0)
        var opacities = [Float](repeating: 0, count: splat ? n : 0)
        var kept = 0
        // Scalar math throughout: SIMD calls are slow in Debug builds.
        var minX = Float.infinity, minY = Float.infinity, minZ = Float.infinity
        var maxX = -Float.infinity, maxY = -Float.infinity, maxZ = -Float.infinity

        try row.withUnsafeMutableBufferPointer { r in
        try positions.withUnsafeMutableBufferPointer { pos in
        try colors.withUnsafeMutableBufferPointer { col in
        try scales.withUnsafeMutableBufferPointer { sca in
        try rotations.withUnsafeMutableBufferPointer { rot in
        try opacities.withUnsafeMutableBufferPointer { opa in
            func store() {
                let x = r[columns.x], y = r[columns.y], z = r[columns.z]
                guard x.isFinite, y.isFinite, z.isFinite else { return }
                pos[kept * 3] = x
                pos[kept * 3 + 1] = y
                pos[kept * 3 + 2] = z
                if x < minX { minX = x }
                if y < minY { minY = y }
                if z < minZ { minZ = z }
                if x > maxX { maxX = x }
                if y > maxY { maxY = y }
                if z > maxZ { maxZ = z }
                if splat, let dc = columns.dc, let o = columns.opacity, let sc = columns.scale, let q = columns.rotation {
                    col[kept * 3] = r[dc.0]
                    col[kept * 3 + 1] = r[dc.1]
                    col[kept * 3 + 2] = r[dc.2]
                    opa[kept] = r[o]
                    sca[kept * 3] = r[sc.0]
                    sca[kept * 3 + 1] = r[sc.1]
                    sca[kept * 3 + 2] = r[sc.2]
                    // 3DGS stores the real part first; RealityKit wants it last.
                    let w = r[q.0], qx = r[q.1], qy = r[q.2], qz = r[q.3]
                    let length = (w * w + qx * qx + qy * qy + qz * qz).squareRoot()
                    let scale: Float = length > 0 ? 1 / length : 0
                    rot[kept * 4] = qx * scale
                    rot[kept * 4 + 1] = qy * scale
                    rot[kept * 4 + 2] = qz * scale
                    rot[kept * 4 + 3] = length > 0 ? w * scale : 1
                } else {
                    var rgb = SIMD3<Float>(repeating: 0.8)
                    if let (cr, cg, cb) = columns.rgb {
                        rgb = SIMD3(r[cr], r[cg], r[cb]) / columns.rgbMax
                    }
                    let dc = (simd_clamp(rgb, .zero, .one) - 0.5) / Self.shC0
                    col[kept * 3] = dc.x
                    col[kept * 3 + 1] = dc.y
                    col[kept * 3 + 2] = dc.z
                }
                kept += 1
            }

            try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                if header.format == .ascii {
                    var lines = AsciiLines(bytes, from: header.bodyOffset)
                    for element in header.elements[..<vertexIndex] {
                        for _ in 0..<element.count { guard lines.next() != nil else { throw ParseError.truncated } }
                    }
                    for _ in 0..<n {
                        guard let line = lines.next() else { throw ParseError.truncated }
                        var i = 0
                        for word in line.split(separator: UInt8(ascii: " "), omittingEmptySubsequences: true) where i < r.count {
                            r[i] = Float(String(decoding: word, as: UTF8.self)) ?? 0
                            i += 1
                        }
                        guard i == r.count else { throw ParseError.truncated }
                        store()
                    }
                } else {
                    let bigEndian = header.format == .binaryBigEndian
                    var offset = header.bodyOffset
                    for element in header.elements[..<vertexIndex] {
                        offset = try Self.skip(element, in: bytes, from: offset, bigEndian: bigEndian)
                    }
                    let stride = vertex.properties.reduce(0) { $0 + $1.type.size }
                    guard offset + stride * n <= bytes.count else { throw ParseError.truncated }
                    var byteOffsets: [Int] = []
                    var start = 0
                    for property in vertex.properties {
                        byteOffsets.append(start)
                        start += property.type.size
                    }
                    let used = columns.used
                    let fieldColumns = used
                    let fieldOffsets = used.map { byteOffsets[$0] }
                    let fieldTypes = used.map { vertex.properties[$0].type }
                    // The common case: little-endian floats, read directly.
                    let allFloats = !bigEndian && fieldTypes.allSatisfy { $0 == .float32 }
                    for _ in 0..<n {
                        for f in 0..<fieldColumns.count {
                            r[fieldColumns[f]] = allFloats
                                ? bytes.loadUnaligned(fromByteOffset: offset + fieldOffsets[f], as: Float.self)
                                : Self.read(fieldTypes[f], in: bytes, at: offset + fieldOffsets[f], bigEndian: bigEndian)
                        }
                        offset += stride
                        store()
                    }
                }
            }
        }
        }
        }
        }
        }
        }

        count = kept
        boundsMin = SIMD3(minX, minY, minZ)
        boundsMax = SIMD3(maxX, maxY, maxZ)
        // Drop the room left by skipped non-finite points.
        positions.removeLast(positions.count - kept * 3)
        colors.removeLast(colors.count - kept * 3)
        self.positions = positions
        self.colors = colors
        if splat {
            scales.removeLast(scales.count - kept * 3)
            rotations.removeLast(rotations.count - kept * 4)
            opacities.removeLast(opacities.count - kept)
            self.scales = scales
            self.rotations = rotations
            self.opacities = opacities
        }
        (coreMin, coreMax) = Self.percentileBounds(of: self.positions, count: kept)
        if !isGaussianSplat { fillPointSplats() }
    }

    /// Where each property this reader uses sits in a vertex row.
    private struct Columns {
        let x, y, z: Int
        var dc: (Int, Int, Int)?
        var opacity: Int?
        var scale: (Int, Int, Int)?
        var rotation: (Int, Int, Int, Int)?
        var rgb: (Int, Int, Int)?
        /// Divides integer colors down to 0...1.
        var rgbMax: Float = 1

        init(_ properties: [Header.Property]) {
            let names = properties.map(\.name)
            func index(_ name: String) -> Int? { names.firstIndex(of: name) }
            x = index("x")!
            y = index("y")!
            z = index("z")!
            if let a = index("f_dc_0"), let b = index("f_dc_1"), let c = index("f_dc_2") { dc = (a, b, c) }
            opacity = index("opacity")
            if let a = index("scale_0"), let b = index("scale_1"), let c = index("scale_2") { scale = (a, b, c) }
            if let a = index("rot_0"), let b = index("rot_1"), let c = index("rot_2"), let d = index("rot_3") { rotation = (a, b, c, d) }
            if let r = index("red"), let g = index("green"), let b = index("blue") {
                rgb = (r, g, b)
                let type = properties[r].type
                rgbMax = type.isInteger ? (type == .uint16 ? 65535 : 255) : 1
            }
        }

        var used: [Int] {
            var all = [x, y, z]
            if let dc { all += [dc.0, dc.1, dc.2] }
            if let opacity { all.append(opacity) }
            if let scale { all += [scale.0, scale.1, scale.2] }
            if let rotation { all += [rotation.0, rotation.1, rotation.2, rotation.3] }
            if let rgb { all += [rgb.0, rgb.1, rgb.2] }
            return all
        }
    }

    /// The `limit` splats that contribute most to the image, by opacity times
    /// volume, the usual measure for pruning a capture. Bounds stay those of
    /// the full capture so it's placed the same either way.
    func keepingMostVisible(_ limit: Int) -> PLYPointCloud {
        guard isGaussianSplat, count > limit else { return self }
        // log(sigmoid(opacity) · e^(s0+s1+s2)); scalar math for Debug builds.
        var importance = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let o = opacities[i]
            importance[i] = -log1p(exp(-o)) + scales[i * 3] + scales[i * 3 + 1] + scales[i * 3 + 2]
        }
        // Find the cutoff from a sample instead of sorting every splat.
        let step = max(1, count / 200_000)
        let sample = Swift.stride(from: 0, to: count, by: step).map { importance[$0] }.sorted(by: >)
        let cutoff = sample[min(sample.count - 1, max(0, sample.count * limit / count - 1))]

        var kept: [Int] = []
        kept.reserveCapacity(limit)
        for i in 0..<count where importance[i] >= cutoff && kept.count < limit { kept.append(i) }

        func gather(_ values: [Float], _ width: Int) -> [Float] {
            var out = [Float]()
            out.reserveCapacity(kept.count * width)
            for i in kept { for c in 0..<width { out.append(values[i * width + c]) } }
            return out
        }
        var reduced = self
        reduced.count = kept.count
        reduced.positions = gather(positions, 3)
        reduced.colors = gather(colors, 3)
        reduced.scales = gather(scales, 3)
        reduced.rotations = gather(rotations, 4)
        reduced.opacities = gather(opacities, 1)
        return reduced
    }

    /// The 1st to 99th percentile of each axis. Captures often have a few
    /// stray splats far out in the background; fitting to the full bounds
    /// would shrink the actual subject to a speck.
    static func percentileBounds(of positions: [Float], count: Int) -> (SIMD3<Float>, SIMD3<Float>) {
        guard count > 0 else { return (.zero, .zero) }
        // A sample is plenty to place percentiles.
        let step = max(1, count / 100_000)
        var lower = SIMD3<Float>.zero, upper = SIMD3<Float>.zero
        for axis in 0..<3 {
            let values = Swift.stride(from: 0, to: count, by: step).map { positions[$0 * 3 + axis] }.sorted()
            let last = Float(values.count - 1)
            lower[axis] = values[Int((last * 0.01).rounded(.down))]
            upper[axis] = values[Int((last * 0.99).rounded(.up))]
        }
        return (lower, upper)
    }

    /// Gives plain points a round, nearly opaque splat sized to the cloud's
    /// density, so a scan reads as a surface rather than scattered dots.
    private mutating func fillPointSplats() {
        guard count > 0 else { return }
        // Scans are mostly surfaces, so spacing goes with √n, not ∛n.
        let spacing = max(extents.max() / Float(count).squareRoot(), 1e-4)
        let logScale = log(spacing * 0.6)
        scales = [Float](repeating: logScale, count: count * 3)
        rotations = [Float]((0..<count).lazy.flatMap { _ in [Float(0), 0, 0, 1] })
        opacities = [Float](repeating: 4, count: count)  // sigmoid(4) ≈ 0.98
    }

    // MARK: - Binary helpers

    private static func read(_ type: ScalarType, in bytes: UnsafeRawBufferPointer, at offset: Int, bigEndian: Bool) -> Float {
        func load<T: FixedWidthInteger>(_: T.Type) -> T {
            let raw = bytes.loadUnaligned(fromByteOffset: offset, as: T.self)
            return bigEndian ? T(bigEndian: raw) : T(littleEndian: raw)
        }
        return switch type {
        case .int8: Float(load(Int8.self))
        case .uint8: Float(load(UInt8.self))
        case .int16: Float(load(Int16.self))
        case .uint16: Float(load(UInt16.self))
        case .int32: Float(load(Int32.self))
        case .uint32: Float(load(UInt32.self))
        case .float32: Float(bitPattern: load(UInt32.self))
        case .float64: Float(Double(bitPattern: load(UInt64.self)))
        }
    }

    /// Steps past an element (usually faces) that comes before the vertices.
    private static func skip(_ element: Header.Element, in bytes: UnsafeRawBufferPointer, from start: Int, bigEndian: Bool) throws -> Int {
        var offset = start
        for _ in 0..<element.count {
            for property in element.properties {
                if let countType = property.listCountType {
                    guard offset + countType.size <= bytes.count else { throw ParseError.truncated }
                    let n = Int(read(countType, in: bytes, at: offset, bigEndian: bigEndian))
                    offset += countType.size + n * property.type.size
                } else {
                    offset += property.type.size
                }
                guard offset <= bytes.count else { throw ParseError.truncated }
            }
        }
        return offset
    }

    /// Lines of an ASCII body, without copying it.
    private struct AsciiLines {
        let bytes: UnsafeRawBufferPointer
        var offset: Int

        init(_ bytes: UnsafeRawBufferPointer, from offset: Int) {
            self.bytes = bytes
            self.offset = offset
        }

        mutating func next() -> UnsafeRawBufferPointer.SubSequence? {
            while offset < bytes.count {
                let start = offset
                while offset < bytes.count, bytes[offset] != UInt8(ascii: "\n") { offset += 1 }
                var end = offset
                offset += 1
                if end > start, bytes[end - 1] == UInt8(ascii: "\r") { end -= 1 }
                if end > start { return bytes[start..<end] }
            }
            return nil
        }
    }
}

// MARK: - RealityKit

extension PLYPointCloud {
    /// Most points the simulator fallback draws; each becomes 6 vertices.
    static let maxMeshPoints = 150_000
    /// Most splats visionOS renders in one resource; a larger buffer is
    /// rejected as invalid.
    static let maxSplats = 400_000

    /// Whether the device shows only the `maxSplats` most visible splats.
    var exceedsSplatLimit: Bool { count > Self.maxSplats }

    /// An entity showing the points, centered on the origin, with a collision
    /// box so it can be dragged and pinched. On device the points render as
    /// Gaussian splats; the simulator has no splat renderer, so it gets small
    /// colored octahedra instead.
    @MainActor
    func makeEntity() async throws -> Entity {
        #if targetEnvironment(simulator)
        let points = try await makePointMesh()
        #else
        let points = try makeSplats()
        #endif
        points.position = -center
        let content = Entity()
        content.addChild(points)
        if isGaussianSplat {
            // 3DGS captures use the COLMAP convention: y down, z forward.
            content.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        }
        let box = Entity()
        box.components.set(CollisionComponent(shapes: [.generateBox(size: simd_max(extents, .init(repeating: 0.01)))]))
        content.addChild(box)
        return content
    }

    #if !targetEnvironment(simulator)
    @MainActor
    private func makeSplats() throws -> Entity {
        let cloud = exceedsSplatLimit ? keepingMostVisible(Self.maxSplats) : self
        return try cloud.makeSplatEntity()
    }

    @MainActor
    private func makeSplatEntity() throws -> Entity {
        func descriptor(_ values: [Float], components: Int, format: MTLAttributeFormat) throws -> GaussianSplatResource.BufferDescriptor {
            let size = values.count * MemoryLayout<Float>.stride
            let buffer = try LowLevelBuffer(descriptor: .init(capacity: size))
            buffer.replaceUnsafeMutableBytes { destination in
                values.withUnsafeBytes { destination.copyMemory(from: $0) }
            }
            return .init(buffer: buffer, format: format, stride: components * MemoryLayout<Float>.stride, offset: 0)
        }

        let buffers = try GaussianSplatResource.BufferResource(
            count: count,
            position: descriptor(positions, components: 3, format: .float3),
            scale: descriptor(scales, components: 3, format: .float3),
            rotation: descriptor(rotations, components: 4, format: .float4),
            opacity: descriptor(opacities, components: 1, format: .float),
            sphericalHarmonics: (descriptor(colors, components: 3, format: .float3), .zero)
        )
        let resource = GaussianSplatResource(buffers)
        resource.scaleActivation = .exponential
        resource.opacityActivation = .sigmoid

        let splats = Entity()
        splats.components.set(GaussianSplatComponent(resource))
        return splats
    }
    #endif

    /// One small octahedron per point (a sample of them for big clouds), each
    /// colored by its own texel in a palette texture.
    @MainActor
    func makePointMesh() async throws -> Entity {
        // Faint splats are mostly haze around a capture; leave them out.
        let visible = (0..<count).filter { !isGaussianSplat || opacities[$0] > -2 }
        let step = max(1, (visible.count + Self.maxMeshPoints - 1) / Self.maxMeshPoints)
        let picked = Swift.stride(from: 0, to: visible.count, by: step).map { visible[$0] }
        guard !picked.isEmpty else { throw ParseError.missingVertices }

        let side = Int(Float(picked.count).squareRoot().rounded(.up))
        let radius = max(extents.max() / Float(picked.count).squareRoot() * 0.6, 1e-4)
        let offsets: [SIMD3<Float>] = [[radius, 0, 0], [-radius, 0, 0], [0, radius, 0], [0, -radius, 0], [0, 0, radius], [0, 0, -radius]]
        let faces: [UInt32] = [0, 2, 4, 2, 1, 4, 1, 3, 4, 3, 0, 4, 2, 0, 5, 1, 2, 5, 3, 1, 5, 0, 3, 5]

        var vertices: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        vertices.reserveCapacity(picked.count * 6)
        uvs.reserveCapacity(picked.count * 6)
        indices.reserveCapacity(picked.count * faces.count)
        for (n, i) in picked.enumerated() {
            let p = SIMD3(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2])
            let rgb = simd_clamp(SIMD3(colors[i * 3], colors[i * 3 + 1], colors[i * 3 + 2]) * Self.shC0 + 0.5, .zero, .one)
            pixels[n * 4] = UInt8(rgb.x * 255)
            pixels[n * 4 + 1] = UInt8(rgb.y * 255)
            pixels[n * 4 + 2] = UInt8(rgb.z * 255)
            // Texel centers; v runs bottom-up in RealityKit.
            let uv = SIMD2((Float(n % side) + 0.5) / Float(side), 1 - (Float(n / side) + 0.5) / Float(side))
            let base = UInt32(vertices.count)
            for offset in offsets {
                vertices.append(p + offset)
                uvs.append(uv)
            }
            indices += faces.map { base + $0 }
        }

        var mesh = MeshDescriptor(name: "points")
        mesh.positions = MeshBuffers.Positions(vertices)
        mesh.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        mesh.primitives = .triangles(indices)

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let palette = CGImage(
                  width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw ParseError.unsupportedFormat("couldn’t build colors")
        }
        let texture = try await TextureResource(image: palette, options: .init(semantic: .color, mipmapsMode: .none))
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        return ModelEntity(mesh: try await MeshResource(from: [mesh]), materials: [material])
    }
}
