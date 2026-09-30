//
//  ZipArchive.swift
//  SpatialReference
//

import Compression
import Foundation

/// A minimal in-memory ZIP reader, just enough to pull a `.usdz` out of the
/// `.zip` wrappers StoryMaps stores 3D models in. Foundation has no public
/// unzip API on visionOS, and this avoids a package dependency for one job.
///
/// Reads the central directory (which always carries the real sizes, even
/// when entries use data descriptors) and supports "stored" and "deflate"
/// entries. Encrypted and ZIP64 archives are rejected.
nonisolated struct ZipArchive {
    struct Entry {
        let path: String
        fileprivate let method: UInt16
        fileprivate let compressedSize: Int
        fileprivate let uncompressedSize: Int
        fileprivate let localHeaderOffset: Int

        var isDirectory: Bool { path.hasSuffix("/") }
    }

    enum ZipError: LocalizedError {
        case notAZip
        case unsupported(String)
        case corrupt(String)

        var errorDescription: String? {
            switch self {
            case .notAZip: return "The downloaded file isn't a valid ZIP archive."
            case .unsupported(let what): return "Unsupported ZIP feature: \(what)."
            case .corrupt(let what): return "The ZIP archive is corrupt (\(what))."
            }
        }
    }

    let entries: [Entry]
    private let data: Data

    init(data: Data) throws {
        self.data = data

        let endOfCentralDirectory = 0x0605_4b50 as UInt32
        let centralEntrySignature = 0x0201_4b50 as UInt32

        // The end-of-central-directory record is 22 bytes plus a comment of up
        // to 64 KiB, so scan backwards for its signature.
        guard data.count >= 22 else { throw ZipError.notAZip }
        var eocd: Int?
        var offset = data.count - 22
        let lowerBound = max(0, data.count - 22 - 0xFFFF)
        while offset >= lowerBound {
            if Self.u32(data, offset) == endOfCentralDirectory { eocd = offset; break }
            offset -= 1
        }
        guard let eocd else { throw ZipError.notAZip }

        let entryCount = Int(Self.u16(data, eocd + 10))
        let directoryOffset = Int(Self.u32(data, eocd + 16))
        if entryCount == 0xFFFF || directoryOffset == 0xFFFF_FFFF { throw ZipError.unsupported("ZIP64") }

        var entries: [Entry] = []
        var cursor = directoryOffset
        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count, Self.u32(data, cursor) == centralEntrySignature else {
                throw ZipError.corrupt("bad central directory")
            }
            let flags = Self.u16(data, cursor + 8)
            let method = Self.u16(data, cursor + 10)
            let compressedSize = Int(Self.u32(data, cursor + 20))
            let uncompressedSize = Int(Self.u32(data, cursor + 24))
            let nameLength = Int(Self.u16(data, cursor + 28))
            let extraLength = Int(Self.u16(data, cursor + 30))
            let commentLength = Int(Self.u16(data, cursor + 32))
            let localHeaderOffset = Int(Self.u32(data, cursor + 42))
            guard cursor + 46 + nameLength <= data.count else { throw ZipError.corrupt("truncated entry name") }
            if flags & 1 != 0 { throw ZipError.unsupported("encryption") }

            let nameStart = data.startIndex + cursor + 46
            let path = String(decoding: data[nameStart..<nameStart + nameLength], as: UTF8.self)
            entries.append(Entry(
                path: path, method: method,
                compressedSize: compressedSize, uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            ))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    /// The first real file with any of the given extensions. Skips directories and the
    /// `__MACOSX/._name` resource-fork stubs macOS's Archive Utility adds,
    /// which carry the same extension but aren't the actual file.
    func firstEntry(withExtensions fileExtensions: [String]) -> Entry? {
        entries.first { entry in
            guard !entry.isDirectory else { return false }
            let components = entry.path.split(separator: "/")
            guard let last = components.last, !last.hasPrefix("._"), !components.contains("__MACOSX") else { return false }
            return fileExtensions.contains { (last as NSString).pathExtension.caseInsensitiveCompare($0) == .orderedSame }
        }
    }

    func extract(_ entry: Entry) throws -> Data {
        let localHeaderSignature = 0x0403_4b50 as UInt32
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count, Self.u32(data, header) == localHeaderSignature else {
            throw ZipError.corrupt("bad local header")
        }
        let start = header + 30 + Int(Self.u16(data, header + 26)) + Int(Self.u16(data, header + 28))
        guard start + entry.compressedSize <= data.count else { throw ZipError.corrupt("truncated entry data") }

        let base = data.startIndex + start
        let payload = data[base..<base + entry.compressedSize]

        switch entry.method {
        case 0:
            return Data(payload)
        case 8:
            guard entry.uncompressedSize > 0 else { return Data() }
            var output = Data(count: entry.uncompressedSize)
            let written = output.withUnsafeMutableBytes { destination in
                payload.withUnsafeBytes { source in
                    // COMPRESSION_ZLIB is a raw deflate stream, which is what
                    // ZIP entries contain (no zlib header or checksum).
                    compression_decode_buffer(
                        destination.bindMemory(to: UInt8.self).baseAddress!, entry.uncompressedSize,
                        source.bindMemory(to: UInt8.self).baseAddress!, entry.compressedSize,
                        nil, COMPRESSION_ZLIB
                    )
                }
            }
            guard written == entry.uncompressedSize else { throw ZipError.corrupt("inflate failed for \(entry.path)") }
            return output
        default:
            throw ZipError.unsupported("compression method \(entry.method)")
        }
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        let i = data.startIndex + offset
        return UInt16(data[i]) | UInt16(data[i + 1]) << 8
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        let i = data.startIndex + offset
        return UInt32(data[i]) | UInt32(data[i + 1]) << 8 | UInt32(data[i + 2]) << 16 | UInt32(data[i + 3]) << 24
    }
}
