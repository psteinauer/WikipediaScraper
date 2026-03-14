// PersonModel.swift — Data model for a person extracted from Wikipedia

import Foundation

// MARK: - Date value

public struct GEDCOMDate {
    public enum Qualifier { case exact, about, before, after }
    public var qualifier: Qualifier = .exact
    public var day:   Int?
    public var month: Int?
    public var year:  Int?
    public var original: String = ""

    public static let monthNames = ["JAN","FEB","MAR","APR","MAY","JUN",
                             "JUL","AUG","SEP","OCT","NOV","DEC"]

    public var gedcom: String {
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

    public var isEmpty: Bool { year == nil && month == nil && day == nil }
}

// MARK: - Events

public struct PersonEvent {
    public var date:  GEDCOMDate?
    public var place: String?
    public var note:  String?
    public var cause: String?   // DEAT.CAUS — cause of death
}

// A titled position held for a period (maps to GEDCOM TITL with DATE FROM…TO)
public struct TitledPosition {
    public var title:                String
    public var startDate:            GEDCOMDate?
    public var endDate:              GEDCOMDate?
    public var place:                String?      // capital / court / location of office
    public var predecessor:          String?
    public var predecessorWikiTitle: String?      // Wikipedia article title for linking
    public var successor:            String?
    public var successorWikiTitle:   String?      // Wikipedia article title for linking
    public var note:                 String?
}

// A custom named event (maps to GEDCOM EVEN with TYPE)
public struct CustomEvent {
    public var type:  String
    public var date:  GEDCOMDate?
    public var place: String?
    public var note:  String?
}

// A named individual attribute (maps to GEDCOM FACT with TYPE)
public struct PersonFact {
    public var type:  String   // e.g. "House", "Award", "Military rank", "Political party"
    public var value: String
}

// MARK: - PersonRef

public struct PersonRef {
    public var name: String
    public var wikiTitle: String?   // Wikipedia article title (used for deduplication/linking)
}

// MARK: - Spouse

public struct SpouseInfo {
    public var name:          String
    public var wikiTitle:     String?         // Wikipedia article title for linking
    public var marriageDate:  GEDCOMDate?
    public var marriagePlace: String?
    public var divorceDate:   GEDCOMDate?
}

// MARK: - Sex

public enum Sex { case male, female, unknown }

// MARK: - Person

public struct PersonData {
    // ── Identity ──────────────────────────────────────────────────────────
    public var name:           String?
    public var givenName:      String?
    public var surname:        String?
    public var birthName:      String?
    public var alternateNames: [String] = []
    public var sex:            Sex = .unknown

    // ── Life events ───────────────────────────────────────────────────────
    public var birth:    PersonEvent?
    public var death:    PersonEvent?
    public var burial:   PersonEvent?
    public var baptism:  PersonEvent?

    // ── Titled positions (TITL with DATE FROM…TO) ─────────────────────────
    // e.g. "Queen of the United Kingdom" from 1837 to 1901
    public var titledPositions: [TitledPosition] = []

    // ── Custom named events (EVEN TYPE) ───────────────────────────────────
    // e.g. Coronation 28 June 1838, Imperial Durbar 1 January 1877
    public var customEvents: [CustomEvent] = []

    // ── Individual attributes (FACT TYPE) ─────────────────────────────────
    // e.g. House: Hanover, Award: Order of the Garter
    public var personFacts: [PersonFact] = []

    // ── Simple honorific / style titles (TITL, no date range) ─────────────
    // e.g. "Sir", "The Right Honourable", post-nominal letters
    public var honorifics: [String] = []

    // ── Family ────────────────────────────────────────────────────────────
    public var spouses:  [SpouseInfo] = []
    public var children: [PersonRef]  = []
    public var father:   PersonRef?
    public var mother:   PersonRef?
    public var parents:  [PersonRef]  = []

    // ── Standard attributes ───────────────────────────────────────────────
    public var occupations: [String] = []
    public var nationality: String?
    public var religion:    String?

    // ── Media ─────────────────────────────────────────────────────────────
    public var imageURL:      String?   // remote URL (plain .ged FILE tag)
    public var imageFilePath: String?   // relative path inside GEDZIP (overrides imageURL)
    public var imageData:     Data?
    public var imageMimeType: String?

    // ── Additional media (--allimages) ────────────────────────────────────
    public var additionalMedia: [AdditionalMedia] = []

    // ── Source ────────────────────────────────────────────────────────────
    public var wikiURL:     String?
    public var wikiTitle:   String?
    public var wikiExtract: String?

    // ── Wikipedia article sections (--notes) ──────────────────────────────
    public var wikiSections: [(title: String, text: String)] = []
}

// A single additional media file (portrait or article image)
public struct AdditionalMedia {
    public var filePath: String    // relative path inside GEDZIP, or remote URL for plain .ged
    public var origURL:  String?   // original Wikimedia source URL
    public var title:    String?   // caption / filename shown in GEDCOM
    public var mimeType: String?
    public init(filePath: String, origURL: String? = nil, title: String? = nil, mimeType: String? = nil) {
        self.filePath = filePath; self.origURL = origURL; self.title = title; self.mimeType = mimeType
    }
}
