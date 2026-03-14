// GEDZIPBuilder.swift — Create a GEDCOM 7 GEDZIP package (.gdz)
//
// GEDZIP specification (GEDCOM 7, §3.2):
//   • ZIP file with extension .gdz
//   • Must contain "gedcom.ged" at the ZIP root
//   • Media files are stored inside the ZIP and referenced by relative paths
//     in the FILE tags of the enclosed GEDCOM (no absolute paths or URLs)
//   • Compression is allowed

import Foundation
import ZIPFoundation

public struct GEDZIPBuilder {

    /// Create a .gdz archive at `destination`.
    ///
    /// - Parameters:
    ///   - gedcom: The GEDCOM 7 text content (FILE tags must already contain
    ///             relative paths matching entries in `mediaFiles`).
    ///   - mediaFiles: Array of `(relativePath, data)` pairs — e.g.
    ///                 `[("media/portrait.jpg", jpegData)]`.
    ///   - destination: URL where the .gdz file is written.
    public static func create(
        gedcom:     String,
        mediaFiles: [(path: String, data: Data)],
        at destination: URL
    ) throws {
        // Remove any existing file so Archive starts fresh
        try? FileManager.default.removeItem(at: destination)

        let archive = try Archive(url: destination, accessMode: .create)

        // ── gedcom.ged ────────────────────────────────────────────────────
        guard let gedcomData = gedcom.data(using: .utf8) else {
            throw GEDZIPError.encodingFailed
        }
        try archive.addEntry(
            with: "gedcom.ged",
            type: .file,
            uncompressedSize: Int64(gedcomData.count),
            compressionMethod: .deflate
        ) { position, size -> Data in
            let start = Int(position)
            let end   = min(start + size, gedcomData.count)
            return gedcomData.subdata(in: start..<end)
        }

        // ── media files ───────────────────────────────────────────────────
        for (path, data) in mediaFiles {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .none   // images are already compressed
            ) { position, size -> Data in
                let start = Int(position)
                let end   = min(start + size, data.count)
                return data.subdata(in: start..<end)
            }
        }
    }
}

public enum GEDZIPError: LocalizedError {
    case cannotCreateArchive(String)
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .cannotCreateArchive(let p): return "Cannot create ZIP archive at \(p)"
        case .encodingFailed:            return "Failed to encode GEDCOM as UTF-8"
        }
    }
}
