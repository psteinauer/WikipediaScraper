// BritRoyalsScraper.swift — PersonPageScraper for britroyals.com
//
// Person pages use URLs like: kings.asp?id=henry6, queens.asp?id=victoria
//
// HTML structure:
//   <h1 class="c-article__title">King Henry VI (1422 - 1461)</h1>
//   <br><b>Born:</b> December 6, 1421 at Windsor Castle
//   <br><b>Parents:</b> Henry V and Catherine of Valois
//   <br><b>Married:</b> Margaret, Daughter of Count of Anjou
//   <br><b>Died:</b> May 21, 1471 at Tower of London (murdered), aged 49…
//   <p>Biography paragraphs…</p>
//   <amp-img src="images/signature/henry6_sig.jpg" …>

import Foundation

public struct BritRoyalsScraper: PersonPageScraper {

    public static let supportedHosts = ["britroyals.com"]

    public init() {}

    /// Only accept person-specific URLs — those with an `id=` query parameter.
    public static func canHandle(url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              host == "britroyals.com" || host.hasSuffix(".britroyals.com"),
              let query = url.query, query.contains("id=")
        else { return false }
        return true
    }

    public func scrape(url: URL, options: ScrapeOptions, verbose: Bool) async throws -> PersonData {
        if verbose { fputs("  [britroyals] Fetching '\(url.absoluteString)'…\n", stderr) }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1) else {
            throw ScraperError.parseError("Could not decode HTML from \(url.absoluteString)")
        }

        // Validate: page must contain at least one known biography field
        guard html.range(of: "<b>Born:</b>", options: .caseInsensitive) != nil else {
            let id = url.queryValue(for: "id") ?? url.lastPathComponent
            throw ScraperError.notAPersonPage(id)
        }

        return try parsePage(html: html, sourceURL: url)
    }

    // MARK: - Page parsing

    private func parsePage(html: String, sourceURL: URL) throws -> PersonData {
        var person = PersonData()
        person.wikiURL = sourceURL.absoluteString

        // ── Name from <h1> ────────────────────────────────────────────────
        if let h1 = extractTagContent(tag: "h1", from: html) {
            let text = stripHTML(h1)
            // Remove "(YYYY - YYYY)" reign suffix
            let nameOnly = text
                .replacingOccurrences(of: #"\s*\(\d+.*\)$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            person.name      = nameOnly
            person.wikiTitle = nameOnly

            let (given, surname) = splitRoyalName(nameOnly)
            person.givenName = given
            person.surname   = surname

            // Infer sex from royal title prefix
            let lower = nameOnly.lowercased()
            if lower.hasPrefix("queen") || lower.hasPrefix("princess") || lower.hasPrefix("empress") {
                person.sex = .female
            } else if lower.hasPrefix("king") || lower.hasPrefix("prince") || lower.hasPrefix("emperor") {
                person.sex = .male
            }
        }

        // ── Key-value pairs: <br><b>KEY:</b> VALUE ───────────────────────
        for (key, value) in extractBoldFields(from: html) {
            applyField(key: key, value: value, to: &person)
        }

        // ── Biography paragraphs → wikiExtract ───────────────────────────
        let paragraphs = extractParagraphs(from: html)
        if !paragraphs.isEmpty {
            person.wikiExtract = paragraphs.joined(separator: "\n\n")
        }

        // ── Portrait / signature image ────────────────────────────────────
        if let imgURL = extractFirstImage(from: html, baseURL: sourceURL) {
            person.imageURL = imgURL
        }

        return person
    }

    // MARK: - Field mapping

    private func applyField(key: String, value: String, to person: inout PersonData) {
        switch key.lowercased() {

        case "name":
            if person.name == nil { person.name = value }

        case "born":
            let (date, place) = parseDatePlace(value)
            person.birth = PersonEvent(date: date, place: place)

        case "died":
            let (date, place, cause) = parseDatePlaceCause(value)
            person.death = PersonEvent(date: date, place: place, cause: cause)

        case "buried at", "buried":
            let place = value.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
            person.burial = PersonEvent(place: place)

        case "parents":
            // "Henry V and Catherine of Valois"
            if let r = value.range(of: " and ", options: .caseInsensitive) {
                let father = String(value[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                let mother = String(value[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !father.isEmpty { person.father = PersonRef(name: father) }
                if !mother.isEmpty { person.mother = PersonRef(name: mother) }
            }

        case "married", "spouse":
            let name = value.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty,
               name.lowercased() != "unmarried",
               name.lowercased() != "never married" {
                person.spouses = [SpouseInfo(name: name)]
            }

        case "house of":
            person.personFacts.append(PersonFact(type: "House", value: value))

        case "ascended to the throne":
            let datePart = value.components(separatedBy: ",")[0]
            if let date = DateParser.parse(datePart) {
                person.customEvents.append(CustomEvent(type: "Accession", date: date))
            } else {
                person.customEvents.append(CustomEvent(type: "Accession", note: value))
            }

        case "crowned":
            person.customEvents.append(CustomEvent(type: "Coronation", note: value))

        case "reigned for":
            person.personFacts.append(PersonFact(type: "Reign Duration", value: value))

        case "succeeded by":
            person.personFacts.append(PersonFact(type: "Succeeded By", value: value))

        case "relation to charles iii", "relation to charles ii",
             "relation to elizabeth ii", "relation to elizabeth i":
            break   // genealogical metadata — omit from GEDCOM

        default:
            let label = key.prefix(1).uppercased() + key.dropFirst()
            person.personFacts.append(PersonFact(type: label, value: value))
        }
    }

    // MARK: - HTML helpers

    private func extractTagContent(tag: String, from html: String) -> String? {
        guard let regex = try? NSRegularExpression(
                  pattern: "<\(tag)[^>]*>(.*?)</\(tag)>",
                  options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(match.range(at: 1), in: html)
        else { return nil }
        return String(html[r])
    }

    /// Parses all `<b>KEY:</b> VALUE` pairs from the biography block.
    private func extractBoldFields(from html: String) -> [(key: String, value: String)] {
        guard let regex = try? NSRegularExpression(
                  pattern: #"<b>([^<:]+):</b>\s*(.*?)(?=<b>[^<:]+:|<p>|<!--|\z)"#,
                  options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return [] }

        var results: [(String, String)] = []
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let kr = Range(match.range(at: 1), in: html),
                  let vr = Range(match.range(at: 2), in: html) else { continue }
            let key   = stripHTML(String(html[kr])).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = stripHTML(String(html[vr])).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && !value.isEmpty { results.append((key, value)) }
        }
        return results
    }

    private func extractParagraphs(from html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
                  pattern: "<p>(.*?)</p>",
                  options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return [] }
        var result: [String] = []
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let r = Range(match.range(at: 1), in: html) else { continue }
            let text = stripHTML(String(html[r])).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(text) }
        }
        return result
    }

    private func extractFirstImage(from html: String, baseURL: URL) -> String? {
        let pattern = #"<(?:amp-img|img)\s[^>]*src=['"]([^'"]+)['"]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(match.range(at: 1), in: html)
        else { return nil }
        let src = String(html[r])
        if src.hasPrefix("http") { return src }
        return URL(string: src, relativeTo: baseURL)?.absoluteString
    }

    private func stripHTML(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&nbsp;", " "), ("&#160;", " "), ("&#8212;", "—"),
        ]
        for (e, r) in entities { t = t.replacingOccurrences(of: e, with: r) }
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Date / place helpers

    /// "December 6, 1421 at Windsor Castle" → (date, "Windsor Castle")
    private func parseDatePlace(_ s: String) -> (date: GEDCOMDate?, place: String?) {
        let cleaned = s
            .replacingOccurrences(of: #",\s*aged\s+[\w\s,]+"#, with: "",
                                  options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.components(separatedBy: " at ")
        let place: String? = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespaces)
            : nil
        return (DateParser.parse(parts[0].trimmingCharacters(in: .whitespaces)),
                place?.isEmpty == true ? nil : place)
    }

    /// "May 21, 1471 at Tower of London (murdered), aged 49…" → (date, place, cause)
    private func parseDatePlaceCause(_ s: String) -> (date: GEDCOMDate?, place: String?, cause: String?) {
        var str = s
        var cause: String? = nil
        if let r = str.range(of: #"\([^)]+\)"#, options: .regularExpression) {
            let inner = String(str[r]).dropFirst().dropLast()
            let c = inner.trimmingCharacters(in: .whitespaces)
            if !c.isEmpty { cause = c }
            str = str.replacingCharacters(in: r, with: "").trimmingCharacters(in: .whitespaces)
        }
        let (date, place) = parseDatePlace(str)
        return (date, place, cause)
    }

    // MARK: - Name splitting

    /// "King Henry VI" → given="Henry VI", surname=nil (royals use regnal numbers)
    private func splitRoyalName(_ fullName: String) -> (given: String?, surname: String?) {
        let titleWords = ["king", "queen", "prince", "princess", "emperor", "empress",
                          "duke", "duchess", "earl", "lord", "lady", "sir", "dame"]
        var parts = fullName.components(separatedBy: " ").filter { !$0.isEmpty }
        while let first = parts.first, titleWords.contains(first.lowercased()) {
            parts.removeFirst()
        }
        guard !parts.isEmpty else { return (nil, nil) }
        if parts.count == 1 { return (parts[0], nil) }
        let lastIsNumeral = parts.last.map { isRomanNumeral($0) || $0.first?.isNumber == true } ?? false
        if lastIsNumeral { return (parts.joined(separator: " "), nil) }
        return (parts.dropLast().joined(separator: " "), parts.last)
    }

    private func isRomanNumeral(_ s: String) -> Bool {
        !s.isEmpty && CharacterSet(charactersIn: "IVXLCDMivxlcdm")
            .isSuperset(of: CharacterSet(charactersIn: s))
    }
}

// MARK: - URL helper
private extension URL {
    func queryValue(for name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }
}
