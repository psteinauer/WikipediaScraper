// BritRoyalsScraper.swift — BaseHTMLScraper subclass for britroyals.com
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

public final class BritRoyalsScraper: BaseHTMLScraper {

    public override class var supportedHosts: [String] { ["britroyals.com"] }

    /// Only accept person-specific URLs — those with an `id=` query parameter.
    public static func canHandle(url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              host == "britroyals.com" || host.hasSuffix(".britroyals.com"),
              let query = url.query, query.contains("id=")
        else { return false }
        return true
    }

    // MARK: - Validation

    public override func validate(html: String, url: URL) throws {
        guard html.range(of: "<b>Born:</b>", options: .caseInsensitive) != nil else {
            let id = url.queryValue(for: "id") ?? url.lastPathComponent
            throw ScraperError.notAPersonPage(id)
        }
    }

    // MARK: - Page parsing

    public override func parsePage(html: String, sourceURL: URL,
                                   options: ScrapeOptions, verbose: Bool) throws -> PersonData {
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

        // ── Timeline events ───────────────────────────────────────────────
        person.customEvents.append(contentsOf: extractTimeline(from: html))

        // ── Portrait image ────────────────────────────────────────────────
        // Use a BritRoyals-specific finder: skip signature images, site logos,
        // SVG icons, and data URIs.  The portrait is typically the first
        // content image in the `images/` directory that is not a signature.
        if let imgURL = extractPortrait(from: html, baseURL: sourceURL) {
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

    // MARK: - Portrait extraction

    /// Find the person's portrait image, skipping signatures, logos, and navigation chrome.
    ///
    /// BritRoyals pages mark the article portrait with `class='c-article__image'` on the
    /// `<amp-img>` element.  We scan every opening tag, capture its full attribute string,
    /// and prefer any tag carrying that class.  If no such tag exists we fall back to the
    /// first content image (skipping .gif/.svg, menus, arrows, signatures, and icons).
    private func extractPortrait(from html: String, baseURL: URL) -> String? {
        // Match the full attribute string of every <amp-img> or <img> opening tag.
        guard let tagRegex = try? NSRegularExpression(
                  pattern: #"<(?:amp-img|img)(\s[^>]*?)(?:>|/>)"#,
                  options: .caseInsensitive),
              let srcRegex = try? NSRegularExpression(
                  pattern: #"\bsrc=['"]([^'"]+)['"]"#,
                  options: .caseInsensitive)
        else { return nil }

        var fallback: String? = nil

        for tagMatch in tagRegex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let attrRange = Range(tagMatch.range(at: 1), in: html) else { continue }
            let attrs      = String(html[attrRange])
            let attrsLower = attrs.lowercased()

            // Extract src= value from this tag's attributes.
            guard let srcMatch = srcRegex.firstMatch(in: attrs,
                                                     range: NSRange(attrs.startIndex..., in: attrs)),
                  let srcRange = Range(srcMatch.range(at: 1), in: attrs)
            else { continue }
            let src      = String(attrs[srcRange])
            let srcLower = src.lowercased()

            // Skip definitively non-portrait sources.
            guard !srcLower.contains("/signature/"),
                  !srcLower.contains("logo"),
                  !srcLower.hasSuffix(".svg"),
                  !srcLower.hasPrefix("data:")
            else { continue }

            // Must live in an images/ path or be an absolute URL.
            guard srcLower.contains("images/") || srcLower.hasPrefix("http") || srcLower.hasPrefix("//")
            else { continue }

            // Primary pick: the article portrait is tagged with c-article__image.
            if attrsLower.contains("c-article__image") {
                return resolveImageURL(src, baseURL: baseURL)
            }

            // Fallback: skip obvious UI chrome (menus, arrows, close buttons, tiny gifs).
            guard !srcLower.contains("menu"),
                  !srcLower.contains("arrow"),
                  !srcLower.contains("close"),
                  !srcLower.contains("icon"),
                  !srcLower.hasSuffix(".gif")
            else { continue }

            if fallback == nil { fallback = resolveImageURL(src, baseURL: baseURL) }
        }
        return fallback
    }

    private func resolveImageURL(_ src: String, baseURL: URL) -> String? {
        if src.hasPrefix("http") { return src }
        if src.hasPrefix("//")   { return "https:" + src }
        return URL(string: src, relativeTo: baseURL)?.absoluteString
    }

    // MARK: - Timeline parsing

    /// Extract chronological events from the Year/Event table present on most BritRoyals pages.
    ///
    /// The table uses `<th>Year</th><th>Event</th>` headers followed by `<tr><td>YYYY</td><td>…</td></tr>`
    /// data rows.  Each row becomes a `CustomEvent` whose type is inferred from the description text;
    /// anything that doesn't match a known genealogical event type is filed as "Historical Event".
    private func extractTimeline(from html: String) -> [CustomEvent] {
        // Find the table that has both "Year" and "Event" as <th> headers.
        guard let tableRegex = try? NSRegularExpression(
                  pattern: #"<table[^>]*>(.*?)</table>"#,
                  options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return [] }

        var timelineHTML: String? = nil
        for match in tableRegex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let r = Range(match.range(at: 1), in: html) else { continue }
            let candidate = String(html[r])
            if candidate.range(of: #"<th[^>]*>\s*Year\s*</th>"#,
                               options: [.regularExpression, .caseInsensitive]) != nil,
               candidate.range(of: #"<th[^>]*>\s*Event\s*</th>"#,
                               options: [.regularExpression, .caseInsensitive]) != nil {
                timelineHTML = candidate
                break
            }
        }
        guard let tableBody = timelineHTML else { return [] }

        // Parse each <tr> that contains exactly two <td> cells.
        guard let rowRegex = try? NSRegularExpression(
                  pattern: #"<tr[^>]*>(.*?)</tr>"#,
                  options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let cellRegex = try? NSRegularExpression(
                  pattern: #"<td[^>]*>(.*?)</td>"#,
                  options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return [] }

        var events: [CustomEvent] = []

        for rowMatch in rowRegex.matches(in: tableBody, range: NSRange(tableBody.startIndex..., in: tableBody)) {
            guard let rr = Range(rowMatch.range(at: 1), in: tableBody) else { continue }
            let rowHTML = String(tableBody[rr])

            // Skip header rows
            if rowHTML.range(of: "<th", options: .caseInsensitive) != nil { continue }

            var cells: [String] = []
            for cellMatch in cellRegex.matches(in: rowHTML, range: NSRange(rowHTML.startIndex..., in: rowHTML)) {
                guard let cr = Range(cellMatch.range(at: 1), in: rowHTML) else { continue }
                let text = stripHTML(String(rowHTML[cr])).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { cells.append(text) }
            }
            guard cells.count >= 2 else { continue }

            let yearText   = cells[0]
            let description = cells[1]
            let date       = DateParser.parse(yearText)
            let type       = classifyTimelineEvent(description)

            events.append(CustomEvent(type: type, date: date, note: description))
        }

        return events
    }

    /// Map a timeline event description to a GEDCOM event type.
    ///
    /// Recognisable types use standard genealogical labels; anything that
    /// doesn't fit a known category is filed as "Historical Event".
    private func classifyTimelineEvent(_ description: String) -> String {
        let s = description.lowercased()

        if s.contains("accede") || s.contains("accedes") || s.contains("accession")
                || s.contains("ascend") || s.contains("ascends to the throne")
                || s.contains("succeed") || s.contains("succeeds to the throne") {
            return "Accession"
        }
        if s.contains("coronat") || s.contains("crowned") {
            return "Coronation"
        }
        if s.contains("marri") || s.contains("betrothed") || s.contains("wed ") || s.contains("weds") {
            return "Marriage"
        }
        if s.contains("battle of") || s.contains("siege of") || s.contains("besieg")
                || s.contains("crusade") || s.contains("invasion") || s.contains("invades")
                || s.contains("rebellion") || s.contains("revolt") {
            return "Battle"
        }
        if s.contains("treaty") || s.contains("truce") || s.contains("peace of") {
            return "Treaty"
        }
        if s.contains("murder") || s.contains("assassinat") || s.contains("executed") {
            return "Murder"
        }
        if s.contains("canoniz") || s.contains("canonised") || s.contains("beatif") {
            return "Canonization"
        }

        return "Historical Event"
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
