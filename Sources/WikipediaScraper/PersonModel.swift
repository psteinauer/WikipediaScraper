// PersonModel.swift — Data model for a person extracted from Wikipedia

import Foundation

// MARK: - Date value

struct GEDCOMDate {
    enum Qualifier { case exact, about, before, after }
    var qualifier: Qualifier = .exact
    var day:   Int?
    var month: Int?
    var year:  Int?
    var original: String = ""

    static let monthNames = ["JAN","FEB","MAR","APR","MAY","JUN",
                             "JUL","AUG","SEP","OCT","NOV","DEC"]

    var gedcom: String {
        var parts: [String] = []
        switch qualifier {
        case .about:  parts.append("ABT")
        case .before: parts.append("BEF")
        case .after:  parts.append("AFT")
        case .exact:  break
        }
        if let d = day,   d >= 1                { parts.append(String(d)) }
        if let m = month, m >= 1, m <= 12       { parts.append(GEDCOMDate.monthNames[m-1]) }
        if let y = year                          { parts.append(String(y)) }
        return parts.joined(separator: " ")
    }

    var isEmpty: Bool { year == nil && month == nil && day == nil }
}

// MARK: - Events

struct PersonEvent {
    var date:  GEDCOMDate?
    var place: String?
    var note:  String?
    var cause: String?   // DEAT.CAUS — cause of death
}

// A titled position held for a period (maps to GEDCOM TITL with DATE FROM…TO)
struct TitledPosition {
    var title:       String
    var startDate:   GEDCOMDate?
    var endDate:     GEDCOMDate?
    var place:       String?      // capital / court / location of office
    var predecessor: String?
    var successor:   String?
    var note:        String?
}

// A custom named event (maps to GEDCOM EVEN with TYPE)
struct CustomEvent {
    var type:  String
    var date:  GEDCOMDate?
    var place: String?
    var note:  String?
}

// A named individual attribute (maps to GEDCOM FACT with TYPE)
struct PersonFact {
    var type:  String   // e.g. "House", "Award", "Military rank", "Political party"
    var value: String
}

// MARK: - PersonRef

struct PersonRef {
    var name: String
    var wikiTitle: String?   // Wikipedia article title (used for deduplication/linking)
}

// MARK: - Spouse

struct SpouseInfo {
    var name:          String
    var wikiTitle:     String?         // Wikipedia article title for linking
    var marriageDate:  GEDCOMDate?
    var marriagePlace: String?
    var divorceDate:   GEDCOMDate?
}

// MARK: - Sex

enum Sex { case male, female, unknown }

// MARK: - Person

struct PersonData {
    // ── Identity ──────────────────────────────────────────────────────────
    var name:           String?
    var givenName:      String?
    var surname:        String?
    var birthName:      String?
    var alternateNames: [String] = []
    var sex:            Sex = .unknown

    // ── Life events ───────────────────────────────────────────────────────
    var birth:    PersonEvent?
    var death:    PersonEvent?
    var burial:   PersonEvent?
    var baptism:  PersonEvent?

    // ── Titled positions (TITL with DATE FROM…TO) ─────────────────────────
    // e.g. "Queen of the United Kingdom" from 1837 to 1901
    var titledPositions: [TitledPosition] = []

    // ── Custom named events (EVEN TYPE) ───────────────────────────────────
    // e.g. Coronation 28 June 1838, Imperial Durbar 1 January 1877
    var customEvents: [CustomEvent] = []

    // ── Individual attributes (FACT TYPE) ─────────────────────────────────
    // e.g. House: Hanover, Award: Order of the Garter
    var personFacts: [PersonFact] = []

    // ── Simple honorific / style titles (TITL, no date range) ─────────────
    // e.g. "Sir", "The Right Honourable", post-nominal letters
    var honorifics: [String] = []

    // ── Family ────────────────────────────────────────────────────────────
    var spouses:  [SpouseInfo] = []
    var children: [PersonRef]  = []
    var father:   PersonRef?
    var mother:   PersonRef?
    var parents:  [PersonRef]  = []

    // ── Standard attributes ───────────────────────────────────────────────
    var occupations: [String] = []
    var nationality: String?
    var religion:    String?

    // ── Media ─────────────────────────────────────────────────────────────
    var imageURL:      String?   // remote URL (plain .ged FILE tag)
    var imageFilePath: String?   // relative path inside GEDZIP (overrides imageURL)
    var imageData:     Data?
    var imageMimeType: String?

    // ── Additional media (--allimages) ────────────────────────────────────
    var additionalMedia: [AdditionalMedia] = []

    // ── Source ────────────────────────────────────────────────────────────
    var wikiURL:     String?
    var wikiTitle:   String?
    var wikiExtract: String?

    // ── Wikipedia article sections (--notes) ──────────────────────────────
    var wikiSections: [(title: String, text: String)] = []
}

// A single additional media file (portrait or article image)
struct AdditionalMedia {
    var filePath: String    // relative path inside GEDZIP, or remote URL for plain .ged
    var origURL:  String?   // original Wikimedia source URL
    var title:    String?   // caption / filename shown in GEDCOM
    var mimeType: String?
}
