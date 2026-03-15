// GEDCOMBuilderTests.swift — XCTest suite for GEDCOMBuilder

import XCTest
@testable import WikipediaScraperCore

final class GEDCOMBuilderTests: XCTestCase {

    // MARK: - Helpers

    private func hasLine(_ gedcom: String, _ content: String) -> Bool {
        gedcom.components(separatedBy: "\r\n").contains { $0.contains(content) }
            || gedcom.components(separatedBy: "\n").contains { $0.contains(content) }
    }

    private func countLines(in gedcom: String, containing tag: String) -> Int {
        let lines = gedcom.components(separatedBy: "\r\n").isEmpty
            ? gedcom.components(separatedBy: "\n")
            : gedcom.components(separatedBy: "\r\n")
        return lines.filter { $0.contains(tag) }.count
    }

    private func allLines(_ gedcom: String) -> [String] {
        let byCRLF = gedcom.components(separatedBy: "\r\n")
        if byCRLF.count > 1 { return byCRLF }
        return gedcom.components(separatedBy: "\n")
    }

    private func buildOnePerson(_ configure: (inout PersonData) -> Void) -> String {
        var person = PersonData()
        person.wikiTitle = "Test Person"
        person.wikiURL   = "https://en.wikipedia.org/wiki/Test_Person"
        configure(&person)
        var builder = GEDCOMBuilder()
        return builder.build(persons: [person], verbose: false)
    }

    // MARK: - 1. HEAD and TRLR present

    func testHEADPresent() {
        let gedcom = buildOnePerson { p in p.name = "Test" }
        XCTAssertTrue(allLines(gedcom).first?.contains("0 HEAD") == true,
                      "GEDCOM should start with '0 HEAD'")
    }

    func testTRLRPresent() {
        let gedcom = buildOnePerson { p in p.name = "Test" }
        let lines = allLines(gedcom).filter { !$0.isEmpty }
        XCTAssertTrue(lines.last?.contains("0 TRLR") == true,
                      "GEDCOM should end with '0 TRLR'")
    }

    // MARK: - 2. GEDC VERSION 7.0

    func testGEDCVersion() {
        let gedcom = buildOnePerson { p in p.name = "Test" }
        XCTAssertTrue(hasLine(gedcom, "2 VERS 7.0"),
                      "GEDCOM should contain '2 VERS 7.0'")
    }

    // MARK: - 3. NAME with surname slashes

    func testNAMEWithSlashes() {
        let gedcom = buildOnePerson { p in
            p.name = "Albert Einstein"
            p.givenName = "Albert"
            p.surname = "Einstein"
            p.wikiTitle = "Albert Einstein"
        }
        XCTAssertTrue(hasLine(gedcom, "1 NAME Albert /Einstein/"),
                      "Expected '1 NAME Albert /Einstein/'")
    }

    func testGIVNTag() {
        let gedcom = buildOnePerson { p in
            p.name = "Albert Einstein"
            p.givenName = "Albert"
            p.surname = "Einstein"
            p.wikiTitle = "Albert Einstein"
        }
        XCTAssertTrue(hasLine(gedcom, "2 GIVN Albert"),
                      "Expected '2 GIVN Albert'")
    }

    func testSURNTag() {
        let gedcom = buildOnePerson { p in
            p.name = "Albert Einstein"
            p.givenName = "Albert"
            p.surname = "Einstein"
            p.wikiTitle = "Albert Einstein"
        }
        XCTAssertTrue(hasLine(gedcom, "2 SURN Einstein"),
                      "Expected '2 SURN Einstein'")
    }

    // MARK: - 4. NPFX for honorific

    func testNPFXForHonorific() {
        let gedcom = buildOnePerson { p in
            p.name = "Queen Victoria"
            p.givenName = "Victoria"
            p.surname = ""
            p.wikiTitle = "Queen Victoria"
        }
        XCTAssertTrue(hasLine(gedcom, "2 NPFX Queen"),
                      "Expected '2 NPFX Queen'")
    }

    // MARK: - 5. SEX M and SEX F

    func testSEXMale() {
        let gedcom = buildOnePerson { p in
            p.name = "John Doe"
            p.sex = .male
        }
        XCTAssertTrue(hasLine(gedcom, "1 SEX M"),
                      "Expected '1 SEX M' for male person")
    }

    func testSEXFemale() {
        let gedcom = buildOnePerson { p in
            p.name = "Jane Doe"
            p.sex = .female
        }
        XCTAssertTrue(hasLine(gedcom, "1 SEX F"),
                      "Expected '1 SEX F' for female person")
    }

    func testSEXUnknownNotWritten() {
        let gedcom = buildOnePerson { p in
            p.name = "Unknown Person"
            p.sex = .unknown
        }
        XCTAssertFalse(hasLine(gedcom, "1 SEX"),
                       "Expected no '1 SEX' line for unknown sex")
    }

    // MARK: - 6. BIRT with date and place

    func testBIRTTag() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            var birt = PersonEvent()
            var d = GEDCOMDate(); d.day = 24; d.month = 5; d.year = 1819
            birt.date = d
            birt.place = "Kensington Palace"
            p.birth = birt
        }
        XCTAssertTrue(hasLine(gedcom, "1 BIRT"), "Expected '1 BIRT'")
    }

    func testBIRTDate() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            var birt = PersonEvent()
            var d = GEDCOMDate(); d.day = 24; d.month = 5; d.year = 1819
            birt.date = d
            birt.place = "Kensington Palace"
            p.birth = birt
        }
        XCTAssertTrue(hasLine(gedcom, "2 DATE 24 MAY 1819"),
                      "Expected '2 DATE 24 MAY 1819'")
    }

    func testBIRTPlace() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            var birt = PersonEvent()
            var d = GEDCOMDate(); d.day = 24; d.month = 5; d.year = 1819
            birt.date = d
            birt.place = "Kensington Palace"
            p.birth = birt
        }
        XCTAssertTrue(hasLine(gedcom, "2 PLAC Kensington Palace"),
                      "Expected '2 PLAC Kensington Palace'")
    }

    // MARK: - 7. DEAT with date and cause

    func testDEATTag() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            var deat = PersonEvent()
            var d = GEDCOMDate(); d.day = 22; d.month = 1; d.year = 1901
            deat.date = d
            deat.cause = "Old age"
            p.death = deat
        }
        XCTAssertTrue(hasLine(gedcom, "1 DEAT"), "Expected '1 DEAT'")
    }

    func testDEATDate() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            var deat = PersonEvent()
            var d = GEDCOMDate(); d.day = 22; d.month = 1; d.year = 1901
            deat.date = d
            deat.cause = "Old age"
            p.death = deat
        }
        XCTAssertTrue(hasLine(gedcom, "2 DATE 22 JAN 1901"),
                      "Expected '2 DATE 22 JAN 1901'")
    }

    func testDEATCause() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            var deat = PersonEvent()
            var d = GEDCOMDate(); d.day = 22; d.month = 1; d.year = 1901
            deat.date = d
            deat.cause = "Old age"
            p.death = deat
        }
        XCTAssertTrue(hasLine(gedcom, "2 CAUS Old age"),
                      "Expected '2 CAUS Old age'")
    }

    // MARK: - 8. BURI with place

    func testBURITag() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            var buri = PersonEvent()
            buri.place = "Frogmore Mausoleum"
            p.burial = buri
        }
        XCTAssertTrue(hasLine(gedcom, "1 BURI"), "Expected '1 BURI'")
    }

    func testBURIPlace() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            var buri = PersonEvent()
            buri.place = "Frogmore Mausoleum"
            p.burial = buri
        }
        XCTAssertTrue(hasLine(gedcom, "2 PLAC Frogmore Mausoleum"),
                      "Expected '2 PLAC Frogmore Mausoleum'")
    }

    // MARK: - 9. OCCU for each occupation

    func testOCCUMultiple() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            p.occupations = ["Physicist", "Professor"]
        }
        XCTAssertTrue(hasLine(gedcom, "1 OCCU Physicist"),
                      "Expected '1 OCCU Physicist'")
        XCTAssertTrue(hasLine(gedcom, "1 OCCU Professor"),
                      "Expected '1 OCCU Professor'")
    }

    // MARK: - 10. TITL / EVEN for titled position

    func testEVENForTitledPosition() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Queen"
            var startDate = GEDCOMDate(); startDate.year = 1837
            var endDate   = GEDCOMDate(); endDate.year   = 1901
            let pos = TitledPosition(title: "Queen of UK", startDate: startDate, endDate: endDate)
            p.titledPositions = [pos]
        }
        XCTAssertTrue(hasLine(gedcom, "Queen of UK"),
                      "Expected 'Queen of UK' in GEDCOM")
    }

    func testEVENDateFromTo() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Queen"
            var startDate = GEDCOMDate(); startDate.year = 1837
            var endDate   = GEDCOMDate(); endDate.year   = 1901
            let pos = TitledPosition(title: "Queen of UK", startDate: startDate, endDate: endDate)
            p.titledPositions = [pos]
        }
        XCTAssertTrue(hasLine(gedcom, "DATE FROM 1837 TO 1901"),
                      "Expected 'DATE FROM 1837 TO 1901'")
    }

    // MARK: - 11. FACT for person facts

    func testFACTValue() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            p.personFacts = [PersonFact(type: "House", value: "Hanover")]
        }
        XCTAssertTrue(hasLine(gedcom, "1 FACT Hanover"),
                      "Expected '1 FACT Hanover'")
    }

    func testFACTType() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            p.personFacts = [PersonFact(type: "House", value: "Hanover")]
        }
        XCTAssertTrue(hasLine(gedcom, "2 TYPE House"),
                      "Expected '2 TYPE House'")
    }

    // MARK: - 12. SOUR record present

    func testSOURRecordPresent() {
        let gedcom = buildOnePerson { p in p.name = "Test Person" }
        XCTAssertTrue(hasLine(gedcom, "0 @S1@ SOUR"),
                      "Expected '0 @S1@ SOUR'")
    }

    func testSOURTitleWikipedia() {
        let gedcom = buildOnePerson { p in p.name = "Test Person" }
        XCTAssertTrue(hasLine(gedcom, "1 TITL Wikipedia"),
                      "Expected '1 TITL Wikipedia'")
    }

    // MARK: - 13. Stub persons for family members

    func testSpouseStubNamePresent() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            p.sex  = .male
            p.spouses = [SpouseInfo(name: "Jane Doe", wikiTitle: nil)]
        }
        XCTAssertTrue(hasLine(gedcom, "1 NAME Jane"),
                      "Expected spouse stub with '1 NAME Jane...'")
    }

    func testFAMRecordPresent() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            p.sex  = .male
            p.spouses = [SpouseInfo(name: "Jane Doe", wikiTitle: nil)]
        }
        XCTAssertTrue(hasLine(gedcom, "0 @F"),
                      "Expected FAM record '0 @F...'")
    }

    func testFAMSPresent() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            p.sex  = .male
            p.spouses = [SpouseInfo(name: "Jane Doe", wikiTitle: nil)]
        }
        XCTAssertTrue(hasLine(gedcom, "1 FAMS") || hasLine(gedcom, "1 HUSB") || hasLine(gedcom, "1 WIFE"),
                      "Expected FAMS, HUSB, or WIFE link in GEDCOM")
    }

    // MARK: - 14. Deduplication across two persons

    func testINDIDeduplication() {
        var person1 = PersonData()
        person1.wikiTitle = "Person1"
        person1.name = "Person One"
        person1.wikiURL = "https://en.wikipedia.org/wiki/Person1"
        person1.spouses = [SpouseInfo(name: "Albert Prince", wikiTitle: "Albert_P")]

        var person2 = PersonData()
        person2.wikiTitle = "Albert_P"
        person2.name = "Albert Prince"
        person2.wikiURL = "https://en.wikipedia.org/wiki/Albert_P"

        var builder = GEDCOMBuilder()
        let gedcom = builder.build(persons: [person1, person2], verbose: false)

        // Count INDI records starting with "0 @I"
        let indiLines = allLines(gedcom).filter { $0.hasPrefix("0 @I") && $0.contains("INDI") }
        // Should be exactly 2: person1 and Albert_P (not 3 with a duplicate stub)
        XCTAssertEqual(indiLines.count, 2,
                       "Expected exactly 2 INDI records, got \(indiLines.count)")
    }

    // MARK: - 15. FAM deduplication

    func testFAMDeduplication() {
        var person1 = PersonData()
        person1.wikiTitle = "PersonA"
        person1.name = "Person A"
        person1.wikiURL = "https://en.wikipedia.org/wiki/PersonA"
        person1.sex = .male
        person1.spouses = [SpouseInfo(name: "Person B", wikiTitle: "PersonB")]

        var person2 = PersonData()
        person2.wikiTitle = "PersonB"
        person2.name = "Person B"
        person2.wikiURL = "https://en.wikipedia.org/wiki/PersonB"
        person2.sex = .female
        person2.spouses = [SpouseInfo(name: "Person A", wikiTitle: "PersonA")]

        var builder = GEDCOMBuilder()
        let gedcom = builder.build(persons: [person1, person2], verbose: false)

        let famLines = allLines(gedcom).filter { $0.hasPrefix("0 @F") && $0.contains("FAM") }
        XCTAssertEqual(famLines.count, 1,
                       "Expected exactly 1 FAM record for the pair, got \(famLines.count)")
    }

    // MARK: - 16. Line length limit (CONT)

    func testLineLengthLimit() {
        let longExtract = String(repeating: "A", count: 600)
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            p.wikiExtract = longExtract
        }
        let lines = allLines(gedcom)
        for line in lines where !line.isEmpty {
            XCTAssertLessThanOrEqual(line.utf8.count, 255,
                "Line exceeds 255 bytes: \(line.prefix(60))...")
        }
    }

    func testCONTLinesPresent() {
        let longExtract = String(repeating: "B", count: 600)
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            p.wikiExtract = longExtract
        }
        XCTAssertTrue(hasLine(gedcom, "CONT "),
                      "Expected CONT continuation lines for long content")
    }

    // MARK: - 17. OBJE for imageURL

    func testOBJERecord() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            p.imageURL = "https://example.com/photo.jpg"
        }
        XCTAssertTrue(hasLine(gedcom, "OBJE"),
                      "Expected OBJE record for imageURL")
    }

    func testOBJEFileURL() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            p.imageURL = "https://example.com/photo.jpg"
        }
        XCTAssertTrue(hasLine(gedcom, "1 FILE https://example.com/photo.jpg"),
                      "Expected '1 FILE https://example.com/photo.jpg'")
    }

    // MARK: - 18. NOTE for wiki sections

    func testNOTEForWikiSections() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            p.wikiSections = [("Early life", "Some text about early life...")]
        }
        XCTAssertTrue(hasLine(gedcom, "1 NOTE"),
                      "Expected '1 NOTE' for wiki sections")
        XCTAssertTrue(hasLine(gedcom, "Early life"),
                      "Expected 'Early life' in GEDCOM from wiki sections")
    }

    // MARK: - 19. Empty persons array

    func testEmptyPersonsArrayDoesNotCrash() {
        var builder = GEDCOMBuilder()
        let gedcom = builder.build(persons: [], verbose: false)
        XCTAssertTrue(allLines(gedcom).first?.contains("0 HEAD") == true,
                      "Expected '0 HEAD' even for empty persons array")
        let lines = allLines(gedcom).filter { !$0.isEmpty }
        XCTAssertTrue(lines.last?.contains("0 TRLR") == true,
                      "Expected '0 TRLR' even for empty persons array")
    }

    // MARK: - 20. LLM data in GEDCOM

    func testLLMDataPresent() {
        let gedcom = buildOnePerson { p in
            p.name = "Test Person"
            p.llmAlternateNames = ["Alex"]
            p.llmTitles = ["Baron"]
        }
        XCTAssertTrue(hasLine(gedcom, "Alex") || hasLine(gedcom, "Baron") || hasLine(gedcom, "AI Generated"),
                      "Expected LLM data or 'AI Generated' tag in GEDCOM")
    }
}
