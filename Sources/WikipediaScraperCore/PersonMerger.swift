// PersonMerger.swift — Detect and merge PersonData records that represent the same individual
//
// When multiple URLs (e.g. a Wikipedia page and a BritRoyals page) refer to the
// same person, their data is consolidated into a single PersonData record.
//
// Detection strategy:
//   1. Canonical names must match — title prefixes ("King", "Queen", …) and
//      "of <Place>" suffixes are stripped before comparison.
//   2. If both records carry a birth year, they must agree within ±2 years.
//
// Merge strategy:
//   • Scalar fields: primary wins; secondary fills any nil gaps.
//   • List fields: primary entries appear first; secondary entries are appended
//     only when no duplicate key exists (case-insensitive).
//   • The primary record's wikiURL / wikiTitle is kept as the canonical source.
//     The secondary source URL is preserved as an additional wikiURL entry so
//     the GEDCOM builder can emit a second SOUR reference.

import Foundation

public enum PersonMerger {

    // MARK: - Public API

    /// Returns a deduplicated copy of `persons` with same-individual records merged.
    ///
    /// Order is preserved: the first occurrence of each individual is its canonical position.
    public static func mergeDuplicates(in persons: [PersonData]) -> [PersonData] {
        var merged: [PersonData] = []
        var usedIndices = IndexSet()

        for i in persons.indices {
            guard !usedIndices.contains(i) else { continue }
            var primary = persons[i]
            for j in (i + 1)..<persons.count {
                guard !usedIndices.contains(j),
                      areSamePerson(primary, persons[j]) else { continue }
                primary = merge(primary, with: persons[j])
                usedIndices.insert(j)
            }
            merged.append(primary)
            usedIndices.insert(i)
        }
        return merged
    }

    // MARK: - Same-person detection

    /// Returns `true` when `a` and `b` are judged to represent the same person.
    public static func areSamePerson(_ a: PersonData, _ b: PersonData) -> Bool {
        let nameA = canonicalName(for: a)
        let nameB = canonicalName(for: b)
        guard !nameA.isEmpty, !nameB.isEmpty, nameA == nameB else { return false }

        // If both carry a birth year they must agree within ±2 years.
        if let yearA = a.birth?.date?.year, let yearB = b.birth?.date?.year {
            return abs(yearA - yearB) <= 2
        }
        return true
    }

    // MARK: - Merge

    /// Merges `secondary` data into `primary`, returning the combined record.
    ///
    /// Pass the Wikipedia-sourced record as `primary` when available — its
    /// wikiURL, wikiTitle, and wikiExtract are kept as the canonical identifiers.
    public static func merge(_ primary: PersonData, with secondary: PersonData) -> PersonData {
        var p = primary

        // ── Scalar identity fields ─────────────────────────────────────────
        p.name      = p.name      ?? secondary.name
        p.givenName = p.givenName ?? secondary.givenName
        p.surname   = p.surname   ?? secondary.surname
        p.birthName = p.birthName ?? secondary.birthName
        if p.sex == .unknown { p.sex = secondary.sex }

        // ── Standard attributes ────────────────────────────────────────────
        p.nationality = p.nationality ?? secondary.nationality
        p.religion    = p.religion    ?? secondary.religion

        // ── Life events: fill gaps in primary from secondary ───────────────
        p.birth   = mergedEvent(p.birth,   secondary.birth)
        p.death   = mergedEvent(p.death,   secondary.death)
        p.burial  = mergedEvent(p.burial,  secondary.burial)
        p.baptism = mergedEvent(p.baptism, secondary.baptism)

        // ── Family refs ────────────────────────────────────────────────────
        p.father = p.father ?? secondary.father
        p.mother = p.mother ?? secondary.mother

        // ── Lists ──────────────────────────────────────────────────────────
        p.alternateNames  = mergedStrings(p.alternateNames,  secondary.alternateNames)
        p.honorifics      = mergedStrings(p.honorifics,      secondary.honorifics)
        p.occupations     = mergedStrings(p.occupations,     secondary.occupations)
        p.spouses         = mergedSpouses(p.spouses,         secondary.spouses)
        p.children        = mergedRefs(p.children,           secondary.children)
        p.parents         = mergedRefs(p.parents,            secondary.parents)
        p.titledPositions = mergedTitles(p.titledPositions,  secondary.titledPositions)
        p.customEvents    = mergedCustomEvents(p.customEvents, secondary.customEvents)
        p.personFacts     = mergedFacts(p.personFacts,       secondary.personFacts)

        // ── Media: prefer primary portrait; adopt secondary if absent ──────
        p.imageURL      = p.imageURL      ?? secondary.imageURL
        p.imageFilePath = p.imageFilePath ?? secondary.imageFilePath
        if p.imageData == nil {
            p.imageData     = secondary.imageData
            p.imageMimeType = secondary.imageMimeType
        }

        // ── Text: prefer primary extract; append secondary as extra section ─
        p.wikiExtract = p.wikiExtract ?? secondary.wikiExtract
        if p.wikiSections.isEmpty { p.wikiSections = secondary.wikiSections }

        // ── Source URLs: keep primary; record secondary URL as additional source ─
        // Store the secondary wikiURL in additionalSourceURLs so GEDCOM can emit both.
        if let secURL = secondary.wikiURL, secURL != p.wikiURL {
            p.additionalSourceURLs.append(secURL)
        }

        return p
    }

    // MARK: - Canonical name

    static func canonicalName(for person: PersonData) -> String {
        canonicalize(person.name ?? person.wikiTitle ?? "")
    }

    private static let titlePrefixes: Set<String> = [
        "king", "queen", "prince", "princess", "emperor", "empress",
        "duke", "duchess", "earl", "lord", "lady", "sir", "dame",
        "saint", "st", "st."
    ]

    private static func canonicalize(_ raw: String) -> String {
        // Remove parenthetical year ranges like "(1422 – 1461)" often present in BritRoyals h1
        let stripped = raw.replacingOccurrences(of: #"\s*\([\d\s–\-]+\)"#, with: "",
                                                options: .regularExpression)
        var words = stripped
            .lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        // Strip leading title words
        while let first = words.first, titlePrefixes.contains(first) {
            words.removeFirst()
        }

        // Strip trailing "of <place>" — "henry ii of england" → "henry ii"
        if let ofIdx = words.firstIndex(of: "of"), ofIdx > 0 {
            words = Array(words[..<ofIdx])
        }

        return words.joined(separator: " ")
    }

    // MARK: - Private merge helpers

    private static func mergedEvent(_ primary: PersonEvent?,
                                    _ secondary: PersonEvent?) -> PersonEvent? {
        guard let sec = secondary else { return primary }
        guard var pri = primary   else { return secondary }
        if pri.date?.isEmpty ?? true { pri.date  = sec.date  }
        if pri.place == nil          { pri.place = sec.place }
        if pri.cause == nil          { pri.cause = sec.cause }
        if pri.note  == nil          { pri.note  = sec.note  }
        return pri
    }

    private static func mergedStrings(_ primary: [String], _ secondary: [String]) -> [String] {
        var seen = Set(primary.map { $0.lowercased() })
        var result = primary
        for s in secondary {
            let k = s.lowercased()
            if !seen.contains(k) { seen.insert(k); result.append(s) }
        }
        return result
    }

    private static func mergedSpouses(_ primary: [SpouseInfo],
                                      _ secondary: [SpouseInfo]) -> [SpouseInfo] {
        var seen = Set(primary.map { $0.name.lowercased() })
        var result = primary
        for s in secondary {
            let k = s.name.lowercased()
            if !seen.contains(k) { seen.insert(k); result.append(s) }
        }
        return result
    }

    private static func mergedRefs(_ primary: [PersonRef],
                                   _ secondary: [PersonRef]) -> [PersonRef] {
        var seen = Set(primary.map { $0.name.lowercased() })
        var result = primary
        for r in secondary {
            let k = r.name.lowercased()
            if !seen.contains(k) { seen.insert(k); result.append(r) }
        }
        return result
    }

    private static func mergedTitles(_ primary: [TitledPosition],
                                     _ secondary: [TitledPosition]) -> [TitledPosition] {
        var seen = Set(primary.map { $0.title.lowercased() })
        var result = primary
        for t in secondary {
            let k = t.title.lowercased()
            if !seen.contains(k) { seen.insert(k); result.append(t) }
        }
        return result
    }

    private static func mergedCustomEvents(_ primary: [CustomEvent],
                                           _ secondary: [CustomEvent]) -> [CustomEvent] {
        var seen = Set(primary.map { customEventKey($0) })
        var result = primary
        for e in secondary {
            let k = customEventKey(e)
            if !seen.contains(k) { seen.insert(k); result.append(e) }
        }
        return result
    }

    /// A stable deduplication key for a CustomEvent: type + year (if present).
    private static func customEventKey(_ e: CustomEvent) -> String {
        let year = e.date?.year.map { String($0) } ?? ""
        return "\(e.type.lowercased()):\(year)"
    }

    private static func mergedFacts(_ primary: [PersonFact],
                                    _ secondary: [PersonFact]) -> [PersonFact] {
        var seen = Set(primary.map { "\($0.type.lowercased()):\($0.value.lowercased())" })
        var result = primary
        for f in secondary {
            let k = "\(f.type.lowercased()):\(f.value.lowercased())"
            if !seen.contains(k) { seen.insert(k); result.append(f) }
        }
        return result
    }
}
