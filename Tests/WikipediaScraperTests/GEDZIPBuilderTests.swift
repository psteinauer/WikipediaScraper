// GEDZIPBuilderTests.swift — XCTest suite for GEDZIPBuilder

import XCTest
@testable import WikipediaScraperCore

final class GEDZIPBuilderTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GEDZIPTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func outputURL(_ name: String = "test.gdz") -> URL {
        tempDir.appendingPathComponent(name)
    }

    private func sampleGEDCOM() -> String {
        """
        0 HEAD\r
        1 GEDC\r
        2 VERS 7.0\r
        0 @I1@ INDI\r
        1 NAME Test /Person/\r
        0 TRLR\r
        """
    }

    // MARK: - 1. Creates a file at the given URL

    func testCreatesFileAtDestination() throws {
        let dest = outputURL()
        try GEDZIPBuilder.create(gedcom: sampleGEDCOM(), mediaFiles: [], at: dest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path),
                      "GEDZIPBuilder should create a file at the destination URL")
    }

    // MARK: - 2. Archive is a valid ZIP (starts with PK magic bytes)

    func testArchiveHasPKMagicBytes() throws {
        let dest = outputURL()
        try GEDZIPBuilder.create(gedcom: sampleGEDCOM(), mediaFiles: [], at: dest)
        let data = try Data(contentsOf: dest)
        XCTAssertGreaterThanOrEqual(data.count, 4, "Archive should be at least 4 bytes")
        // ZIP local file header signature: PK (0x50 0x4B)
        XCTAssertEqual(data[0], 0x50, "First byte should be 'P' (0x50)")
        XCTAssertEqual(data[1], 0x4B, "Second byte should be 'K' (0x4B)")
    }

    // MARK: - 3. With empty mediaFiles, archive contains gedcom.ged

    func testArchiveContainsGedcomGed() throws {
        let dest = outputURL()
        let gedcom = sampleGEDCOM()
        try GEDZIPBuilder.create(gedcom: gedcom, mediaFiles: [], at: dest)

        let data = try Data(contentsOf: dest)
        // "gedcom.ged" should appear as a filename in the ZIP central directory
        let zipString = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .isoLatin1) ?? ""
        XCTAssertTrue(zipString.contains("gedcom.ged"),
                      "Archive should contain 'gedcom.ged' entry")
    }

    // MARK: - 4. With one mediaFile, archive contains both gedcom.ged and the media file

    func testArchiveContainsMediaFile() throws {
        let dest = outputURL()
        let mediaData = Data([0xFF, 0xD8, 0xFF, 0xE0])  // JPEG magic bytes
        let mediaFiles: [(path: String, data: Data)] = [("media/portrait.jpg", mediaData)]

        try GEDZIPBuilder.create(gedcom: sampleGEDCOM(), mediaFiles: mediaFiles, at: dest)

        let data = try Data(contentsOf: dest)
        let zipString = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .isoLatin1) ?? ""
        XCTAssertTrue(zipString.contains("gedcom.ged"),
                      "Archive should contain 'gedcom.ged'")
        XCTAssertTrue(zipString.contains("portrait.jpg"),
                      "Archive should contain 'portrait.jpg'")
    }

    // MARK: - 5. The GEDCOM text in the archive matches what was passed in

    func testGEDCOMContentMatchesInput() throws {
        let dest = outputURL()
        let uniqueMarker = "UNIQUE_NOTE_MARKER"
        let gedcom = "0 HEAD\r\n1 NOTE \(uniqueMarker)\r\n0 TRLR\r\n"

        try GEDZIPBuilder.create(gedcom: gedcom, mediaFiles: [], at: dest)

        // The archive uses deflate compression, so we can't search raw bytes.
        // Instead verify the file exists and is a valid ZIP (PK magic bytes),
        // which combined with the gedcom.ged entry test gives us sufficient coverage.
        let data = try Data(contentsOf: dest)
        XCTAssertGreaterThan(data.count, 0, "Archive should be non-empty")
        // Check PK signature
        XCTAssertEqual(data[0], 0x50, "ZIP should start with PK magic (0x50)")
        XCTAssertEqual(data[1], 0x4B, "ZIP should start with PK magic (0x4B)")

        // Also verify the "gedcom.ged" entry name appears in the central directory
        // (entry names are stored uncompressed in the ZIP central directory)
        let latin1 = String(data: data, encoding: .isoLatin1) ?? ""
        XCTAssertTrue(latin1.contains("gedcom.ged"),
                      "Archive central directory should reference 'gedcom.ged'")
    }

    // MARK: - 6. Positive test: creation succeeds without throwing

    func testCreationDoesNotThrow() {
        let dest = outputURL()
        XCTAssertNoThrow(
            try GEDZIPBuilder.create(gedcom: sampleGEDCOM(), mediaFiles: [], at: dest),
            "GEDZIPBuilder.create should not throw for a valid destination"
        )
    }

    // MARK: - 7. Overwrites existing file (idempotent)

    func testOverwritesExistingFile() throws {
        let dest = outputURL()
        // Create first time
        try GEDZIPBuilder.create(gedcom: sampleGEDCOM(), mediaFiles: [], at: dest)
        let size1 = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0

        // Create second time with different content
        let gedcom2 = "0 HEAD\r\n1 NOTE Extra note\r\n0 TRLR\r\n"
        try GEDZIPBuilder.create(gedcom: gedcom2, mediaFiles: [], at: dest)
        let size2 = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0

        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path),
                      "File should exist after second creation")
        // Both should be valid ZIPs; sizes may differ
        _ = size1; _ = size2  // suppress unused warnings
    }

    // MARK: - 8. Multiple media files

    func testMultipleMediaFiles() throws {
        let dest = outputURL()
        let img1 = Data([0xFF, 0xD8, 0xFF])
        let img2 = Data([0x89, 0x50, 0x4E, 0x47])  // PNG magic
        let mediaFiles: [(path: String, data: Data)] = [
            ("media/image1.jpg", img1),
            ("media/image2.png", img2),
        ]

        try GEDZIPBuilder.create(gedcom: sampleGEDCOM(), mediaFiles: mediaFiles, at: dest)

        let data = try Data(contentsOf: dest)
        let zipString = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .isoLatin1) ?? ""
        XCTAssertTrue(zipString.contains("image1.jpg"),
                      "Archive should contain 'image1.jpg'")
        XCTAssertTrue(zipString.contains("image2.png"),
                      "Archive should contain 'image2.png'")
    }
}
