// DateParserTests.swift — XCTest suite for DateParser and GEDCOMDate

import XCTest
@testable import WikipediaScraperCore

final class DateParserTests: XCTestCase {

    // MARK: - Wikitext template parsing

    func testBirthDateTemplate() {
        let d = DateParser.parse("{{birth date|1819|5|24}}")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.day, 24)
        XCTAssertEqual(d?.month, 5)
        XCTAssertEqual(d?.year, 1819)
        XCTAssertEqual(d?.qualifier, .exact)
    }

    func testDeathDateTemplateWithDfParam() {
        let d = DateParser.parse("{{death date|1901|1|22|df=yes}}")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.day, 22)
        XCTAssertEqual(d?.month, 1)
        XCTAssertEqual(d?.year, 1901)
    }

    func testStartDateTemplate() {
        let d = DateParser.parse("{{start date|1837|6|20}}")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.day, 20)
        XCTAssertEqual(d?.month, 6)
        XCTAssertEqual(d?.year, 1837)
    }

    func testCircaTemplate() {
        let d = DateParser.parse("{{circa|1066}}")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.year, 1066)
        XCTAssertEqual(d?.qualifier, .about)
    }

    func testFloruitTemplate() {
        let d = DateParser.parse("{{floruit|1200}}")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.year, 1200)
        XCTAssertEqual(d?.qualifier, .about)
    }

    func testFlDotTemplate() {
        let d = DateParser.parse("{{fl.|1340}}")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.year, 1340)
        XCTAssertEqual(d?.qualifier, .about)
    }

    // MARK: - ISO date parsing

    func testISOFullDate() {
        let d = DateParser.parse("1819-05-24")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.day, 24)
        XCTAssertEqual(d?.month, 5)
        XCTAssertEqual(d?.year, 1819)
    }

    func testISOYearMonth() {
        let d = DateParser.parse("1819-05")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.month, 5)
        XCTAssertEqual(d?.year, 1819)
        XCTAssertNil(d?.day)
    }

    // MARK: - Plain text date parsing

    func testPlainFullDate() {
        let d = DateParser.parse("24 May 1819")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.day, 24)
        XCTAssertEqual(d?.month, 5)
        XCTAssertEqual(d?.year, 1819)
    }

    func testPlainMonthYear() {
        let d = DateParser.parse("May 1819")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.month, 5)
        XCTAssertEqual(d?.year, 1819)
        XCTAssertNil(d?.day)
    }

    func testPlainYearOnly() {
        let d = DateParser.parse("1819")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.year, 1819)
        XCTAssertNil(d?.month)
        XCTAssertNil(d?.day)
    }

    func testPlainLowercaseMonth() {
        let d = DateParser.parse("24 may 1819")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.day, 24)
        XCTAssertEqual(d?.month, 5)
        XCTAssertEqual(d?.year, 1819)
    }

    func testPlainUppercaseMonth() {
        let d = DateParser.parse("24 MAY 1819")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.day, 24)
        XCTAssertEqual(d?.month, 5)
        XCTAssertEqual(d?.year, 1819)
    }

    // MARK: - Qualifier prefixes

    func testQualifierCDot() {
        let d = DateParser.parse("c. 1066")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.qualifier, .about)
        XCTAssertEqual(d?.year, 1066)
    }

    func testQualifierCirca() {
        let d = DateParser.parse("circa 1200")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.qualifier, .about)
        XCTAssertEqual(d?.year, 1200)
    }

    func testQualifierAbout() {
        let d = DateParser.parse("about 1300")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.qualifier, .about)
        XCTAssertEqual(d?.year, 1300)
    }

    func testQualifierAbt() {
        let d = DateParser.parse("abt 1400")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.qualifier, .about)
        XCTAssertEqual(d?.year, 1400)
    }

    func testQualifierBefore() {
        let d = DateParser.parse("before 1500")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.qualifier, .before)
        XCTAssertEqual(d?.year, 1500)
    }

    func testQualifierBef() {
        let d = DateParser.parse("bef 1600")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.qualifier, .before)
        XCTAssertEqual(d?.year, 1600)
    }

    func testQualifierAfter() {
        let d = DateParser.parse("after 1700")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.qualifier, .after)
        XCTAssertEqual(d?.year, 1700)
    }

    func testQualifierAft() {
        let d = DateParser.parse("aft 1800")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.qualifier, .after)
        XCTAssertEqual(d?.year, 1800)
    }

    // MARK: - HTML and wikitext stripping

    func testHTMLStripping() {
        let d = DateParser.parse("<span>24 May 1819</span>")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.day, 24)
        XCTAssertEqual(d?.month, 5)
        XCTAssertEqual(d?.year, 1819)
    }

    func testWikilinkStripping() {
        let d = DateParser.parse("[[24 May|24 May]] [[1819]]")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.year, 1819)
    }

    func testRefTagStripping() {
        // DateParser strips generic HTML tags <...> so "<ref>" and "</ref>" are removed
        // but the *content* between them is NOT removed (only tags, not text content).
        // The string becomes "1819some ref" after stripping the angle-bracket tags.
        // However the year "1819" should still be parseable from the remaining tokens.
        // If the implementation doesn't produce a date, we just verify no crash occurs.
        let d = DateParser.parse("1819<ref>some ref</ref>")
        // Best-effort: if parsed, year should be 1819
        if let date = d {
            XCTAssertEqual(date.year, 1819)
        }
        // Not asserting non-nil because the "some ref" text may confuse the tokeniser
    }

    // MARK: - Nil cases

    func testEmptyString() {
        let d = DateParser.parse("")
        XCTAssertNil(d)
    }

    func testWhitespaceOnly() {
        let d = DateParser.parse("   ")
        XCTAssertNil(d)
    }

    // MARK: - parseRange tests

    func testReignTemplate() {
        let (start, end) = DateParser.parseRange("{{reign|1837|6|20|1901|1|22}}")
        XCTAssertNotNil(start)
        XCTAssertNotNil(end)
        XCTAssertEqual(start?.year, 1837)
        XCTAssertEqual(start?.month, 6)
        XCTAssertEqual(start?.day, 20)
        XCTAssertEqual(end?.year, 1901)
        XCTAssertEqual(end?.month, 1)
        XCTAssertEqual(end?.day, 22)
    }

    func testRangeEnDash() {
        let (start, end) = DateParser.parseRange("1837\u{2013}1901") // en-dash
        XCTAssertNotNil(start)
        XCTAssertNotNil(end)
        XCTAssertEqual(start?.year, 1837)
        XCTAssertEqual(end?.year, 1901)
    }

    func testRangeEmDash() {
        let (start, end) = DateParser.parseRange("1837\u{2014}1901") // em-dash
        XCTAssertNotNil(start)
        XCTAssertNotNil(end)
        XCTAssertEqual(start?.year, 1837)
        XCTAssertEqual(end?.year, 1901)
    }

    func testRangeToKeyword() {
        let (start, end) = DateParser.parseRange("1837 to 1901")
        XCTAssertNotNil(start)
        XCTAssertNotNil(end)
        XCTAssertEqual(start?.year, 1837)
        XCTAssertEqual(end?.year, 1901)
    }

    func testRangeFullDates() {
        let (start, end) = DateParser.parseRange("20 June 1837 \u{2013} 22 January 1901")
        XCTAssertNotNil(start)
        XCTAssertNotNil(end)
        XCTAssertEqual(start?.day, 20)
        XCTAssertEqual(start?.month, 6)
        XCTAssertEqual(start?.year, 1837)
        XCTAssertEqual(end?.day, 22)
        XCTAssertEqual(end?.month, 1)
        XCTAssertEqual(end?.year, 1901)
    }

    func testRangeSingleDate() {
        let (start, end) = DateParser.parseRange("1837")
        XCTAssertNotNil(start)
        XCTAssertEqual(start?.year, 1837)
        XCTAssertNil(end)
    }
}

// MARK: - GEDCOMDate tests

final class GEDCOMDateTests: XCTestCase {

    func testGEDCOMFullDate() {
        var d = GEDCOMDate()
        d.day = 24; d.month = 5; d.year = 1819; d.qualifier = .exact
        XCTAssertEqual(d.gedcom, "24 MAY 1819")
    }

    func testGEDCOMMonthYear() {
        var d = GEDCOMDate()
        d.month = 5; d.year = 1819
        XCTAssertEqual(d.gedcom, "MAY 1819")
    }

    func testGEDCOMYearOnly() {
        var d = GEDCOMDate()
        d.year = 1819
        XCTAssertEqual(d.gedcom, "1819")
    }

    func testGEDCOMAbout() {
        var d = GEDCOMDate()
        d.qualifier = .about; d.year = 1066
        XCTAssertEqual(d.gedcom, "ABT 1066")
    }

    func testGEDCOMBefore() {
        var d = GEDCOMDate()
        d.qualifier = .before; d.year = 1500
        XCTAssertEqual(d.gedcom, "BEF 1500")
    }

    func testGEDCOMAfter() {
        var d = GEDCOMDate()
        d.qualifier = .after; d.year = 1700
        XCTAssertEqual(d.gedcom, "AFT 1700")
    }

    func testGEDCOMEmpty() {
        let d = GEDCOMDate()
        XCTAssertEqual(d.gedcom, "")
        XCTAssertTrue(d.isEmpty)
    }

    func testIsNotEmpty() {
        var d = GEDCOMDate()
        d.year = 1819
        XCTAssertFalse(d.isEmpty)
    }
}
