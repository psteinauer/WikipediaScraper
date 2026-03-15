// ScraperConfigTests.swift — XCTest suite for ScraperConfig

import XCTest
@testable import WikipediaScraperCore

final class ScraperConfigTests: XCTestCase {

    // Helper: write a temp config file and return its path.
    private func writeTempConfig(_ contents: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("test_scraperconfig_\(UUID().uuidString).rc")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Empty config

    func testEmptyConfigHasEmptyDictionaries() {
        let config = ScraperConfig.empty
        XCTAssertTrue(config.factMappings.isEmpty)
        XCTAssertTrue(config.eventMappings.isEmpty)
    }

    // MARK: - Facts section

    func testParseFacts() throws {
        let contents = """
        [facts]
        house = Royal House
        awards = Award
        """
        let path = try writeTempConfig(contents)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = ScraperConfig.load(path: path)
        XCTAssertEqual(config.factMappings["house"], "Royal House")
        XCTAssertEqual(config.factMappings["awards"], "Award")
        XCTAssertTrue(config.eventMappings.isEmpty)
    }

    // MARK: - Events section

    func testParseEvents() throws {
        let contents = """
        [events]
        coronation = Coronation Ceremony
        baptism = Baptism
        """
        let path = try writeTempConfig(contents)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = ScraperConfig.load(path: path)
        XCTAssertEqual(config.eventMappings["coronation"], "Coronation Ceremony")
        XCTAssertEqual(config.eventMappings["baptism"], "Baptism")
        XCTAssertTrue(config.factMappings.isEmpty)
    }

    // MARK: - Both sections together

    func testParseBothSections() throws {
        let contents = """
        [facts]
        house = Dynasty

        [events]
        coronation = Coronation
        """
        let path = try writeTempConfig(contents)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = ScraperConfig.load(path: path)
        XCTAssertEqual(config.factMappings["house"], "Dynasty")
        XCTAssertEqual(config.eventMappings["coronation"], "Coronation")
    }

    // MARK: - Comments and blank lines are ignored

    func testHashCommentsIgnored() throws {
        let contents = """
        # This is a comment
        [facts]
        # Another comment
        house = Royal House
        """
        let path = try writeTempConfig(contents)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = ScraperConfig.load(path: path)
        XCTAssertEqual(config.factMappings["house"], "Royal House")
        XCTAssertEqual(config.factMappings.count, 1)
    }

    func testSemicolonCommentsIgnored() throws {
        let contents = """
        ; This is a semicolon comment
        [facts]
        ; Another comment
        house = Castle
        """
        let path = try writeTempConfig(contents)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = ScraperConfig.load(path: path)
        XCTAssertEqual(config.factMappings["house"], "Castle")
        XCTAssertEqual(config.factMappings.count, 1)
    }

    func testBlankLinesIgnored() throws {
        let contents = """

        [facts]

        house = Hanover


        awards = Award

        """
        let path = try writeTempConfig(contents)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = ScraperConfig.load(path: path)
        XCTAssertEqual(config.factMappings["house"], "Hanover")
        XCTAssertEqual(config.factMappings["awards"], "Award")
    }

    // MARK: - Unknown sections silently ignored

    func testUnknownSectionIgnored() throws {
        let contents = """
        [unknown_section]
        foo = bar
        [facts]
        house = Hanover
        """
        let path = try writeTempConfig(contents)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = ScraperConfig.load(path: path)
        XCTAssertEqual(config.factMappings["house"], "Hanover")
        XCTAssertNil(config.factMappings["foo"])
    }

    // MARK: - Key normalisation (lowercase, spaces → underscores)

    func testKeysAreLowercased() throws {
        let contents = """
        [facts]
        HOUSE = Royal House
        Awards = Award
        """
        let path = try writeTempConfig(contents)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = ScraperConfig.load(path: path)
        XCTAssertEqual(config.factMappings["house"], "Royal House")
        XCTAssertEqual(config.factMappings["awards"], "Award")
    }

    func testKeySpacesConvertedToUnderscores() throws {
        let contents = """
        [facts]
        royal house = Dynasty Name
        """
        let path = try writeTempConfig(contents)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = ScraperConfig.load(path: path)
        XCTAssertEqual(config.factMappings["royal_house"], "Dynasty Name")
    }

    // MARK: - Values are trimmed

    func testValuesAreTrimmed() throws {
        let contents = """
        [facts]
        house =   Royal House
        """
        let path = try writeTempConfig(contents)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = ScraperConfig.load(path: path)
        XCTAssertEqual(config.factMappings["house"], "Royal House")
    }

    // MARK: - Missing file returns .empty

    func testMissingFileReturnsEmpty() {
        let config = ScraperConfig.load(path: "/tmp/nonexistent_file_\(UUID().uuidString).rc")
        XCTAssertTrue(config.factMappings.isEmpty)
        XCTAssertTrue(config.eventMappings.isEmpty)
    }

    // MARK: - Multiple entries in same section

    func testMultipleEntriesInSameSection() throws {
        let contents = """
        [facts]
        house = Royal House
        awards = Award
        party = Political Party
        branch = Military Branch
        rank = Military Rank
        """
        let path = try writeTempConfig(contents)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = ScraperConfig.load(path: path)
        XCTAssertEqual(config.factMappings.count, 5)
        XCTAssertEqual(config.factMappings["house"], "Royal House")
        XCTAssertEqual(config.factMappings["awards"], "Award")
        XCTAssertEqual(config.factMappings["party"], "Political Party")
        XCTAssertEqual(config.factMappings["branch"], "Military Branch")
        XCTAssertEqual(config.factMappings["rank"], "Military Rank")
    }

    // MARK: - Entry without section is ignored

    func testEntryBeforeSectionIsIgnored() throws {
        let contents = """
        orphan_key = orphan value
        [facts]
        house = Hanover
        """
        let path = try writeTempConfig(contents)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = ScraperConfig.load(path: path)
        XCTAssertNil(config.factMappings["orphan_key"])
        XCTAssertEqual(config.factMappings["house"], "Hanover")
    }
}
