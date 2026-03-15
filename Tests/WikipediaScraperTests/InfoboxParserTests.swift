// InfoboxParserTests.swift — XCTest suite for InfoboxParser

import XCTest
@testable import WikipediaScraperCore

final class InfoboxParserTests: XCTestCase {

    // MARK: - Royal infobox (Queen Victoria)

    private let victoriaWikitext = """
    {{Infobox royalty
    | name = Queen Victoria
    | birth_date = {{birth date|1819|5|24|df=yes}}
    | birth_place = Kensington Palace, London
    | death_date = {{death date|1901|1|22|df=yes}}
    | death_place = Osborne House, Isle of Wight
    | burial_place = Frogmore Mausoleum
    | spouse = [[Albert, Prince Consort|Albert]]
    | father = [[Prince Edward, Duke of Kent and Strathearn|Edward, Duke of Kent]]
    | mother = [[Princess Victoria of Saxe-Coburg-Saalfeld]]
    | issue = [[Victoria, Princess Royal]]
    | religion = Church of England
    | succession = Queen of the United Kingdom
    | reign = {{reign|1837|6|20|1901|1|22}}
    | predecessor = [[William IV]]
    | successor = [[Edward VII]]
    | house = Hanover
    }}
    """

    func testQueenVictoriaName() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertEqual(person.name, "Queen Victoria")
    }

    func testQueenVictoriaBirthYear() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertEqual(person.birth?.date?.year, 1819)
    }

    func testQueenVictoriaBirthMonth() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertEqual(person.birth?.date?.month, 5)
    }

    func testQueenVictoriaBirthDay() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertEqual(person.birth?.date?.day, 24)
    }

    func testQueenVictoriaBirthPlace() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertTrue(person.birth?.place?.contains("Kensington") == true,
                      "Expected birth place to contain 'Kensington', got: \(person.birth?.place ?? "nil")")
    }

    func testQueenVictoriaDeathYear() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertEqual(person.death?.date?.year, 1901)
    }

    func testQueenVictoriaDeathPlace() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertTrue(person.death?.place?.contains("Osborne") == true,
                      "Expected death place to contain 'Osborne', got: \(person.death?.place ?? "nil")")
    }

    func testQueenVictoriaBurialPlace() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertTrue(person.burial?.place?.contains("Frogmore") == true,
                      "Expected burial place to contain 'Frogmore', got: \(person.burial?.place ?? "nil")")
    }

    func testQueenVictoriaTitledPositionsCount() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertGreaterThanOrEqual(person.titledPositions.count, 1)
    }

    func testQueenVictoriaTitledPositionTitle() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertEqual(person.titledPositions.first?.title, "Queen of the United Kingdom")
    }

    func testQueenVictoriaTitledPositionStartDate() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertEqual(person.titledPositions.first?.startDate?.year, 1837)
    }

    func testQueenVictoriaTitledPositionEndDate() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertEqual(person.titledPositions.first?.endDate?.year, 1901)
    }

    func testQueenVictoriaTitledPositionPredecessor() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertEqual(person.titledPositions.first?.predecessor, "William IV")
    }

    func testQueenVictoriaTitledPositionSuccessor() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertEqual(person.titledPositions.first?.successor, "Edward VII")
    }

    func testQueenVictoriaTitledPositionPredecessorWikiTitle() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertEqual(person.titledPositions.first?.predecessorWikiTitle, "William IV")
    }

    func testQueenVictoriaSpousesCount() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertGreaterThanOrEqual(person.spouses.count, 1)
    }

    func testQueenVictoriaSpouseName() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertEqual(person.spouses.first?.name, "Albert")
    }

    func testQueenVictoriaFather() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertNotNil(person.father)
        XCTAssertTrue(person.father?.name.contains("Edward") == true,
                      "Expected father name to contain 'Edward', got: \(person.father?.name ?? "nil")")
    }

    func testQueenVictoriaMother() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertNotNil(person.mother)
        XCTAssertTrue(person.mother?.name.contains("Victoria") == true,
                      "Expected mother name to contain 'Victoria', got: \(person.mother?.name ?? "nil")")
    }

    func testQueenVictoriaHouseFact() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        let houseFact = person.personFacts.first { $0.type == "House" }
        XCTAssertNotNil(houseFact, "Expected a personFact with type 'House'")
        XCTAssertEqual(houseFact?.value, "Hanover")
    }

    func testQueenVictoriaReligion() {
        let (person, _) = InfoboxParser.parse(wikitext: victoriaWikitext, pageTitle: "Queen Victoria", verbose: false)
        XCTAssertEqual(person.religion, "Church of England")
    }

    // MARK: - Officeholder infobox (George Washington)

    private let washingtonWikitext = """
    {{Infobox officeholder
    | name = George Washington
    | birth_date = {{birth date|1732|2|22}}
    | birth_place = Pope's Creek, Virginia
    | death_date = {{death date|1799|12|14}}
    | death_place = Mount Vernon, Virginia
    | office = 1st President of the United States
    | term_start = April 30, 1789
    | term_end = March 4, 1797
    | predecessor = None (new office)
    | successor = [[John Adams]]
    | spouse = [[Martha Washington]]
    | children = [[John Parke Custis]]
    }}
    """

    func testWashingtonName() {
        let (person, _) = InfoboxParser.parse(wikitext: washingtonWikitext, pageTitle: "George Washington", verbose: false)
        XCTAssertEqual(person.name, "George Washington")
    }

    func testWashingtonBirthYear() {
        let (person, _) = InfoboxParser.parse(wikitext: washingtonWikitext, pageTitle: "George Washington", verbose: false)
        XCTAssertEqual(person.birth?.date?.year, 1732)
    }

    func testWashingtonBirthMonth() {
        let (person, _) = InfoboxParser.parse(wikitext: washingtonWikitext, pageTitle: "George Washington", verbose: false)
        XCTAssertEqual(person.birth?.date?.month, 2)
    }

    func testWashingtonDeathYear() {
        let (person, _) = InfoboxParser.parse(wikitext: washingtonWikitext, pageTitle: "George Washington", verbose: false)
        XCTAssertEqual(person.death?.date?.year, 1799)
    }

    func testWashingtonTitledPositions() {
        let (person, _) = InfoboxParser.parse(wikitext: washingtonWikitext, pageTitle: "George Washington", verbose: false)
        XCTAssertGreaterThanOrEqual(person.titledPositions.count, 1)
    }

    func testWashingtonOfficeTitle() {
        let (person, _) = InfoboxParser.parse(wikitext: washingtonWikitext, pageTitle: "George Washington", verbose: false)
        let hasPresident = person.titledPositions.contains { $0.title.contains("President") }
        XCTAssertTrue(hasPresident, "Expected a titled position containing 'President'")
    }

    func testWashingtonTermStart() {
        let (person, _) = InfoboxParser.parse(wikitext: washingtonWikitext, pageTitle: "George Washington", verbose: false)
        let presPos = person.titledPositions.first { $0.title.contains("President") }
        XCTAssertEqual(presPos?.startDate?.year, 1789)
    }

    func testWashingtonTermEnd() {
        let (person, _) = InfoboxParser.parse(wikitext: washingtonWikitext, pageTitle: "George Washington", verbose: false)
        let presPos = person.titledPositions.first { $0.title.contains("President") }
        XCTAssertEqual(presPos?.endDate?.year, 1797)
    }

    func testWashingtonSuccessor() {
        let (person, _) = InfoboxParser.parse(wikitext: washingtonWikitext, pageTitle: "George Washington", verbose: false)
        let presPos = person.titledPositions.first { $0.title.contains("President") }
        XCTAssertEqual(presPos?.successor, "John Adams")
    }

    func testWashingtonSpouses() {
        let (person, _) = InfoboxParser.parse(wikitext: washingtonWikitext, pageTitle: "George Washington", verbose: false)
        XCTAssertGreaterThanOrEqual(person.spouses.count, 1)
    }

    // MARK: - Scientist infobox (Einstein)

    private let einsteinWikitext = """
    {{Infobox scientist
    | name = Albert Einstein
    | birth_name = Albert Einstein
    | birth_date = {{birth date|1879|3|14}}
    | birth_place = Ulm, Kingdom of Württemberg
    | death_date = {{death date|1955|4|18}}
    | death_place = Princeton, New Jersey
    | nationality = German
    | occupation = Theoretical physicist
    | awards = Nobel Prize in Physics (1921)
    }}
    """

    func testEinsteinName() {
        let (person, _) = InfoboxParser.parse(wikitext: einsteinWikitext, pageTitle: "Albert Einstein", verbose: false)
        XCTAssertEqual(person.name, "Albert Einstein")
    }

    func testEinsteinBirthYear() {
        let (person, _) = InfoboxParser.parse(wikitext: einsteinWikitext, pageTitle: "Albert Einstein", verbose: false)
        XCTAssertEqual(person.birth?.date?.year, 1879)
    }

    func testEinsteinBirthMonth() {
        let (person, _) = InfoboxParser.parse(wikitext: einsteinWikitext, pageTitle: "Albert Einstein", verbose: false)
        XCTAssertEqual(person.birth?.date?.month, 3)
    }

    func testEinsteinBirthDay() {
        let (person, _) = InfoboxParser.parse(wikitext: einsteinWikitext, pageTitle: "Albert Einstein", verbose: false)
        XCTAssertEqual(person.birth?.date?.day, 14)
    }

    func testEinsteinDeathYear() {
        let (person, _) = InfoboxParser.parse(wikitext: einsteinWikitext, pageTitle: "Albert Einstein", verbose: false)
        XCTAssertEqual(person.death?.date?.year, 1955)
    }

    func testEinsteinNationality() {
        let (person, _) = InfoboxParser.parse(wikitext: einsteinWikitext, pageTitle: "Albert Einstein", verbose: false)
        XCTAssertEqual(person.nationality, "German")
    }

    func testEinsteinOccupation() {
        let (person, _) = InfoboxParser.parse(wikitext: einsteinWikitext, pageTitle: "Albert Einstein", verbose: false)
        let hasPhysicist = person.occupations.contains { $0.contains("physicist") || $0.contains("Physicist") }
        XCTAssertTrue(hasPhysicist, "Expected occupations to contain 'physicist', got: \(person.occupations)")
    }

    func testEinsteinAwardFact() {
        let (person, _) = InfoboxParser.parse(wikitext: einsteinWikitext, pageTitle: "Albert Einstein", verbose: false)
        let awardFact = person.personFacts.first { $0.type == "Award" }
        XCTAssertNotNil(awardFact, "Expected a personFact with type 'Award'")
    }

    // MARK: - Sex detection

    func testSexFemale() {
        let wikitext = """
        {{Infobox person
        | name = Jane Smith
        | gender = female
        | birth_date = {{birth date|1950|1|1}}
        }}
        """
        let (person, _) = InfoboxParser.parse(wikitext: wikitext, pageTitle: "Jane Smith", verbose: false)
        XCTAssertEqual(person.sex, .female)
    }

    func testSexMale() {
        let wikitext = """
        {{Infobox person
        | name = John Smith
        | gender = male
        | birth_date = {{birth date|1950|1|1}}
        }}
        """
        let (person, _) = InfoboxParser.parse(wikitext: wikitext, pageTitle: "John Smith", verbose: false)
        XCTAssertEqual(person.sex, .male)
    }

    // MARK: - cleanText behaviour

    func testCleanTextStripsBR() {
        let result = InfoboxParser.cleanText("line1<br />line2")
        XCTAssertNotNil(result)
        // br tag should be replaced or stripped; no raw HTML in result
        XCTAssertFalse(result?.contains("<br") == true)
    }

    func testCleanTextStripsRef() {
        let result = InfoboxParser.cleanText("1819<ref>some footnote</ref>")
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.contains("<ref") == true)
        XCTAssertFalse(result?.contains("footnote") == true)
    }

    func testCleanTextStripsWikilinkWithPipe() {
        let result = InfoboxParser.cleanText("[[George Washington|Washington]]")
        XCTAssertEqual(result, "Washington")
    }

    func testCleanTextStripsWikilinkSimple() {
        let result = InfoboxParser.cleanText("[[Napoleon]]")
        XCTAssertEqual(result, "Napoleon")
    }

    func testCleanTextStripsSmallTemplate() {
        // {{small|some text}} — the template is removed by stripTemplates.
        // The display template handler may or may not extract the text argument,
        // but the result should not contain "{{" braces.
        let result = InfoboxParser.cleanText("{{small|some text}}")
        // nil is acceptable (empty after stripping); if non-nil, braces should be gone
        if let r = result {
            XCTAssertFalse(r.contains("{{"), "Result should not contain '{{'")
        }
    }

    // MARK: - No infobox

    func testNoInfoboxFallsBackToPageTitle() {
        let wikitext = "Some plain text without any infobox."
        let (person, _) = InfoboxParser.parse(wikitext: wikitext, pageTitle: "My Person", verbose: false)
        XCTAssertEqual(person.name, "My Person")
    }

    // MARK: - Multi-suffix officeholder (Napoleon)

    private let napoleonWikitext = """
    {{Infobox officeholder
    | name = Napoleon Bonaparte
    | birth_date = {{birth date|1769|8|15|df=y}}
    | birth_place = Ajaccio, Corsica
    | death_date = {{death date|1821|5|5|df=y}}
    | office = Emperor of the French
    | term_start = 18 May 1804
    | term_end = 6 April 1814
    | predecessor = Louis XVI
    | successor = Louis XVIII
    | office2 = First Consul of France
    | term_start2 = 19 November 1799
    | term_end2 = 18 May 1804
    | predecessor2 = Roger Ducos
    | successor2 = None
    }}
    """

    func testNapoleonTitledPositionsCount() {
        let (person, _) = InfoboxParser.parse(wikitext: napoleonWikitext, pageTitle: "Napoleon", verbose: false)
        XCTAssertGreaterThanOrEqual(person.titledPositions.count, 2,
            "Expected at least 2 titled positions, got \(person.titledPositions.count)")
    }

    func testNapoleonFirstOfficeIsEmperor() {
        let (person, _) = InfoboxParser.parse(wikitext: napoleonWikitext, pageTitle: "Napoleon", verbose: false)
        let hasEmperor = person.titledPositions.contains { $0.title.contains("Emperor") }
        XCTAssertTrue(hasEmperor, "Expected a titled position containing 'Emperor'")
    }

    func testNapoleonSecondOfficeIsConsul() {
        let (person, _) = InfoboxParser.parse(wikitext: napoleonWikitext, pageTitle: "Napoleon", verbose: false)
        let hasConsul = person.titledPositions.contains { $0.title.contains("Consul") }
        XCTAssertTrue(hasConsul, "Expected a titled position containing 'Consul'")
    }

    // MARK: - Marriage template (Henry VIII)

    private let henryWikitext = """
    {{Infobox royalty
    | name = Henry VIII
    | birth_date = {{birth date|1491|6|28|df=yes}}
    | spouse = {{marriage|Catherine of Aragon|11 June 1509|23 May 1533|reason=ann}}{{marriage|Anne Boleyn|25 January 1533|19 May 1536|reason=ann}}
    }}
    """

    func testHenrySpousesCount() {
        let (person, _) = InfoboxParser.parse(wikitext: henryWikitext, pageTitle: "Henry VIII", verbose: false)
        XCTAssertGreaterThanOrEqual(person.spouses.count, 2,
            "Expected at least 2 spouses, got \(person.spouses.count)")
    }

    func testHenryFirstSpouseName() {
        let (person, _) = InfoboxParser.parse(wikitext: henryWikitext, pageTitle: "Henry VIII", verbose: false)
        XCTAssertEqual(person.spouses.first?.name, "Catherine of Aragon")
    }

    // MARK: - Config overrides

    func testConfigOverridesHouseFactType() {
        var config = ScraperConfig()
        config.factMappings["house"] = "Royal House"

        let (person, _) = InfoboxParser.parse(
            wikitext: victoriaWikitext,
            pageTitle: "Queen Victoria",
            verbose: false,
            config: config)

        let royalHouseFact = person.personFacts.first { $0.type == "Royal House" }
        XCTAssertNotNil(royalHouseFact, "Expected a personFact with type 'Royal House'")
        XCTAssertEqual(royalHouseFact?.value, "Hanover")
    }
}
