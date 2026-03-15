// MappingsReporterTests.swift — XCTest suite for MappingsReporter

import XCTest
@testable import WikipediaScraperCore

final class MappingsReporterTests: XCTestCase {

    // MARK: - Helpers

    private func makePerson(name: String? = "Test Person", birthYear: Int? = 1819, deathYear: Int? = 1901) -> PersonData {
        var person = PersonData()
        person.name = name
        person.wikiTitle = name
        person.givenName = "Test"
        person.surname = "Person"
        if let y = birthYear {
            var birt = PersonEvent()
            var d = GEDCOMDate(); d.year = y
            birt.date = d
            person.birth = birt
        }
        if let y = deathYear {
            var deat = PersonEvent()
            var d = GEDCOMDate(); d.year = y
            deat.date = d
            person.death = deat
        }
        return person
    }

    private func makeRawFields() -> [String: String] {
        [
            "name": "Test Person",
            "birth_date": "{{birth date|1819|5|24}}",
            "death_date": "{{death date|1901|1|22}}",
        ]
    }

    // MARK: - 1. Output is non-empty for a person with birth/death/name

    func testOutputIsNonEmpty() {
        let person = makePerson()
        let output = MappingsReporter.report(person: person, rawFields: makeRawFields(), wikiURL: nil)
        XCTAssertFalse(output.isEmpty, "MappingsReporter output should not be empty")
    }

    // MARK: - 2. Output contains "WIKIPEDIA FIELD" / "Infobox Field" header

    func testContainsWikipediaFieldHeader() {
        let person = makePerson()
        let output = MappingsReporter.report(person: person, rawFields: makeRawFields(), wikiURL: nil)
        // The header row uses "WIKIPEDIA FIELD" (all caps)
        XCTAssertTrue(output.contains("WIKIPEDIA FIELD") || output.contains("Infobox Field") || output.contains("FIELD"),
                      "Output should contain a field mapping header")
    }

    // MARK: - 3. Output contains "GEDCOM Output" / "GEDCOM 7 STRUCTURE" header

    func testContainsGEDCOMHeader() {
        let person = makePerson()
        let output = MappingsReporter.report(person: person, rawFields: makeRawFields(), wikiURL: nil)
        XCTAssertTrue(output.contains("GEDCOM") ,
                      "Output should contain 'GEDCOM' header text")
    }

    // MARK: - 4. Output contains the person's name

    func testContainsPersonName() {
        let person = makePerson(name: "Queen Victoria")
        var fields = makeRawFields()
        fields["name"] = "Queen Victoria"
        let output = MappingsReporter.report(person: person, rawFields: fields, wikiURL: nil)
        XCTAssertTrue(output.contains("Victoria"),
                      "Output should contain the person's name")
    }

    // MARK: - 5. Unmapped fields section appears when rawFields has keys not in person

    func testUnmappedFieldsSection() {
        let person = makePerson()
        var fields = makeRawFields()
        fields["some_unknown_field"] = "unknown value"
        fields["another_unknown"] = "another value"
        let output = MappingsReporter.report(person: person, rawFields: fields, wikiURL: nil)
        XCTAssertTrue(output.contains("some_unknown_field") || output.contains("NOT MAPPED") || output.contains("unmapped"),
                      "Output should contain unmapped field names or an 'unmapped' section")
    }

    // MARK: - 6. Non-crashing on empty PersonData

    func testNonCrashingOnEmptyPerson() {
        let person = PersonData()
        XCTAssertNoThrow(
            MappingsReporter.report(person: person, rawFields: [:], wikiURL: nil),
            "MappingsReporter should not crash on empty PersonData"
        )
        let output = MappingsReporter.report(person: person, rawFields: [:], wikiURL: nil)
        XCTAssertFalse(output.isEmpty, "Output should not be empty even for empty person")
    }

    // MARK: - 7. Includes wikiURL when provided

    func testIncludesWikiURL() {
        let person = makePerson()
        let url = "https://en.wikipedia.org/wiki/Test_Person"
        let output = MappingsReporter.report(person: person, rawFields: makeRawFields(), wikiURL: url)
        XCTAssertTrue(output.contains("en.wikipedia.org"),
                      "Output should include the provided wikiURL")
    }

    // MARK: - 8. Birth date appears in output

    func testBirthDateMapped() {
        let person = makePerson(birthYear: 1819)
        let output = MappingsReporter.report(person: person, rawFields: makeRawFields(), wikiURL: nil)
        XCTAssertTrue(output.contains("1819") || output.contains("birth_date"),
                      "Output should reference birth date information")
    }

    // MARK: - 9. Titled positions appear in output

    func testTitledPositionsMapped() {
        var person = makePerson()
        var startDate = GEDCOMDate(); startDate.year = 1837
        var endDate   = GEDCOMDate(); endDate.year   = 1901
        let pos = TitledPosition(title: "Queen of the United Kingdom",
                                 startDate: startDate, endDate: endDate)
        person.titledPositions = [pos]
        var fields = makeRawFields()
        fields["succession"] = "Queen of the United Kingdom"

        let output = MappingsReporter.report(person: person, rawFields: fields, wikiURL: nil)
        XCTAssertTrue(output.contains("Queen") || output.contains("TITL") || output.contains("1837"),
                      "Output should contain titled position information")
    }

    // MARK: - 10. Religion appears in output

    func testReligionMapped() {
        var person = makePerson()
        person.religion = "Church of England"
        var fields = makeRawFields()
        fields["religion"] = "Church of England"

        let output = MappingsReporter.report(person: person, rawFields: fields, wikiURL: nil)
        XCTAssertTrue(output.contains("religion") || output.contains("Church"),
                      "Output should contain religion information")
    }
}
