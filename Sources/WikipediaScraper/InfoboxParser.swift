// InfoboxParser.swift — Extract person data from Wikipedia wikitext infobox

import Foundation

struct InfoboxParser {

    // MARK: - Entry point

    /// Parse the Wikipedia infobox and return both the PersonData and the raw field dictionary
    /// (raw fields are needed for the --mappings option).
    static func parse(wikitext: String, pageTitle: String, verbose: Bool,
                      config: ScraperConfig = .empty) -> (person: PersonData, rawFields: [String: String]) {
        var person = PersonData()
        person.wikiTitle = pageTitle

        // Extract the infobox block
        guard let fields = extractInfoboxFields(from: wikitext, verbose: verbose) else {
            if verbose { fputs("  [info] No infobox found; using page title only.\n", stderr) }
            person.name = cleanText(pageTitle)
            return (person, [:])
        }

        // Name
        person.name = (fields["name"] ?? fields["full_name"]).flatMap { cleanText($0) } ?? cleanText(pageTitle)
        if let bn = fields["birth_name"] { person.birthName = cleanText(bn) }
        person.givenName = fields["given_name"].flatMap { cleanText($0) }
            ?? fields["first_name"].flatMap { cleanText($0) }
        person.surname = fields["surname"].flatMap { cleanText($0) }
            ?? fields["last_name"].flatMap { cleanText($0) }
            ?? fields["family_name"].flatMap { cleanText($0) }

        // Auto-split name if components aren't explicit
        if person.givenName == nil, person.surname == nil, let full = person.name {
            let parts = full.components(separatedBy: " ")
            if parts.count >= 2 {
                person.givenName = parts.dropLast().joined(separator: " ")
                person.surname = parts.last
            } else {
                person.givenName = full
            }
        }

        // Sex / gender
        if let g = fields["gender"] ?? fields["sex"] {
            let lower = g.lowercased()
            if lower.contains("female") || lower.contains("woman") || lower == "f" {
                person.sex = .female
            } else if lower.contains("male") || lower.contains("man") || lower == "m" {
                person.sex = .male
            }
        }
        // Heuristic from pronouns field
        if person.sex == .unknown, let p = fields["pronouns"] {
            if p.lowercased().contains("she") { person.sex = .female }
            else if p.lowercased().contains("he") { person.sex = .male }
        }

        // Birth
        let birthDateRaw = fields["birth_date"] ?? fields["date_of_birth"] ?? fields["born"]
        let birthPlaceRaw = fields["birth_place"] ?? fields["place_of_birth"] ?? fields["birthplace"]
        if birthDateRaw != nil || birthPlaceRaw != nil {
            var evt = PersonEvent()
            if let d = birthDateRaw { evt.date = DateParser.parse(d) }
            if let p = birthPlaceRaw { evt.place = cleanText(p) }
            person.birth = evt
        }

        // Death
        let deathDateRaw = fields["death_date"] ?? fields["date_of_death"] ?? fields["died"]
        let deathPlaceRaw = fields["death_place"] ?? fields["place_of_death"] ?? fields["deathplace"]
        if deathDateRaw != nil || deathPlaceRaw != nil {
            var evt = PersonEvent()
            if let d = deathDateRaw { evt.date = DateParser.parse(d) }
            if let p = deathPlaceRaw { evt.place = cleanText(p) }
            person.death = evt
        }

        // Burial
        let burialRaw = fields["burial_place"] ?? fields["place_of_burial"] ?? fields["resting_place"]
        if let b = burialRaw {
            var evt = PersonEvent()
            evt.place = cleanText(b)
            if let coord = fields["resting_place_coordinates"] { evt.note = cleanText(coord) }
            person.burial = evt
        }

        // Baptism
        if let bd = fields["baptism_date"] ?? fields["christening_date"] {
            var evt = PersonEvent()
            evt.date = DateParser.parse(bd)
            evt.place = (fields["baptism_place"] ?? fields["christening_place"]).flatMap { cleanText($0) }
            person.baptism = evt
        }

        // Spouse(s)
        let spouseKeys = ["spouse", "spouses", "partner", "partners"]
        for key in spouseKeys {
            if let v = fields[key] {
                person.spouses.append(contentsOf: parseSpouses(v))
            }
        }

        // Children
        if let c = fields["children"] ?? fields["issue"] ?? fields["offspring"] {
            person.children = parsePersonRefList(c)
        }

        // Parents
        if let f = fields["father"] {
            person.father = cleanText(f).map { PersonRef(name: $0, wikiTitle: extractWikiTitle(from: f)) }
        }
        if let m = fields["mother"] {
            person.mother = cleanText(m).map { PersonRef(name: $0, wikiTitle: extractWikiTitle(from: m)) }
        }
        if let p = fields["parents"] { person.parents = parsePersonRefList(p) }

        // ── Burial date (separate from burial place) ──────────────────────────
        if let bd = fields["burial_date"] {
            if person.burial == nil { person.burial = PersonEvent() }
            person.burial?.date = DateParser.parse(bd)
        }

        // ── Death cause ────────────────────────────────────────────────────────
        if let dc = fields["death_cause"] ?? fields["cause_of_death"] {
            if let cause = cleanText(dc) {
                if person.death == nil { person.death = PersonEvent() }
                person.death?.cause = cause
            }
        }

        // Track fields processed by hardcoded handlers so RC can override names
        // and add mappings for fields not covered here.
        var hardcodedFactFields  = Set<String>()
        var hardcodedEventFields = Set<String>()

        // ── House / dynasty ────────────────────────────────────────────────────
        let houseAliases = ["house", "dynasty", "royal_house"]
        houseAliases.forEach { hardcodedFactFields.insert($0) }
        if let h = fields["house"] ?? fields["dynasty"] ?? fields["royal_house"] {
            let typeName = houseAliases.compactMap { config.factMappings[$0] }.first ?? "House"
            if let clean = cleanText(h), !clean.isEmpty {
                person.personFacts.append(PersonFact(type: typeName, value: clean))
            }
        }

        // ── Political party ────────────────────────────────────────────────────
        hardcodedFactFields.insert("party")
        if let p = fields["party"] {
            let typeName = config.factMappings["party"] ?? "Political party"
            for item in parseList(p) where !item.isEmpty {
                person.personFacts.append(PersonFact(type: typeName, value: item))
            }
        }

        // ── Military fields ────────────────────────────────────────────────────
        // Single-value fields: join list items into one fact value
        for (fieldKey, defaultType) in [("branch",        "Military branch"),
                                        ("rank",           "Military rank"),
                                        ("service_years",  "Service years"),
                                        ("allegiance",     "Allegiance")] {
            hardcodedFactFields.insert(fieldKey)
            guard let v = fields[fieldKey] else { continue }
            let typeName = config.factMappings[fieldKey] ?? defaultType
            let items = parseList(v)
            if !items.isEmpty {
                let joined = items.joined(separator: ", ")
                person.personFacts.append(PersonFact(type: typeName, value: joined))
            } else if let clean = cleanText(v), !clean.isEmpty {
                person.personFacts.append(PersonFact(type: typeName, value: clean))
            }
        }
        // Battles — one fact per battle
        hardcodedFactFields.insert("battles")
        hardcodedFactFields.insert("battles/wars")
        let battlesRaw    = fields["battles"] ?? fields["battles/wars"] ?? ""
        let battleTypeName = config.factMappings["battles"] ?? config.factMappings["battles/wars"] ?? "Battle"
        for item in parseList(battlesRaw) where !item.isEmpty {
            person.personFacts.append(PersonFact(type: battleTypeName, value: item))
        }

        // ── Awards ─────────────────────────────────────────────────────────────
        hardcodedFactFields.insert("awards")
        if let a = fields["awards"] {
            let typeName = config.factMappings["awards"] ?? "Award"
            for item in parseList(a) where !item.isEmpty {
                person.personFacts.append(PersonFact(type: typeName, value: item))
            }
        }

        // ── Honorifics (simple titles, no date range) ──────────────────────────
        let honorificKeys = ["title", "titles", "royal_title", "noble_title",
                             "honorific_prefix", "honorific_suffix",
                             "post_nominals", "style", "imperial_style"]
        for key in honorificKeys {
            if let t = fields[key], let clean = cleanText(t), !clean.isEmpty {
                person.honorifics.append(clean)
            }
        }

        // ── Royalty: succession + reign → titledPositions ──────────────────────
        // Suffixes: "" (first), "1", "2", … "10"
        for suffix in ([""] + (1...10).map { String($0) }) {
            guard let succRaw = fields["succession\(suffix)"],
                  let succTitle = cleanText(succRaw), !succTitle.isEmpty else { continue }

            var pos = TitledPosition(title: succTitle)

            if let reignRaw = fields["reign\(suffix)"] {
                let (start, end) = DateParser.parseRange(reignRaw)
                pos.startDate = start
                pos.endDate   = end
            }
            pos.predecessor = fields["predecessor\(suffix)"].flatMap { cleanText($0) }
            pos.successor   = fields["successor\(suffix)"].flatMap { cleanText($0) }
            person.titledPositions.append(pos)

            // Coronation as custom event
            hardcodedEventFields.insert("coronation\(suffix)")
            if let corRaw = fields["coronation\(suffix)"],
               !corRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // cor-type overrides everything; otherwise RC config; otherwise default
                let corDefaultType = config.eventMappings["coronation"] ?? "Coronation"
                var evt = CustomEvent(type: corDefaultType)
                evt.date  = DateParser.parse(corRaw)
                evt.place = fields["cor-place\(suffix)"].flatMap { cleanText($0) }
                if let ct = fields["cor-type\(suffix)"], let ctClean = cleanText(ct),
                   !ctClean.isEmpty { evt.type = ctClean }
                person.customEvents.append(evt)
            }
        }

        // ── Officeholder: office + term → titledPositions ─────────────────────
        // Suffixes: "" (first), "2", "3", … "15"
        for suffix in ([""] + (2...15).map { String($0) }) {
            guard let offRaw = fields["office\(suffix)"],
                  let offTitle = cleanText(offRaw), !offTitle.isEmpty else { continue }
            // Avoid duplicates from royalty pass
            guard !person.titledPositions.contains(where: { $0.title == offTitle }) else { continue }

            var pos = TitledPosition(title: offTitle)
            if let ts = fields["term_start\(suffix)"] { pos.startDate = DateParser.parse(ts) }
            if let te = fields["term_end\(suffix)"]   { pos.endDate   = DateParser.parse(te) }
            pos.predecessor = (fields["preceded_by\(suffix)"] ?? fields["predecessor\(suffix)"])
                                .flatMap { cleanText($0) }
            pos.successor   = (fields["succeeded_by\(suffix)"] ?? fields["successor\(suffix)"])
                                .flatMap { cleanText($0) }
            person.titledPositions.append(pos)
        }

        // ── RC-defined facts (fields not covered by hardcoded handlers above) ──
        // Entries whose field name matches a hardcoded field override its display
        // name (already applied above). Any remaining entries add new facts.
        for field in config.factMappings.keys.sorted() {
            guard !hardcodedFactFields.contains(field),
                  let typeName = config.factMappings[field], !typeName.isEmpty,
                  let v = fields[field] else { continue }
            for item in parseList(v) where !item.isEmpty {
                person.personFacts.append(PersonFact(type: typeName, value: item))
            }
        }

        // ── RC-defined events (fields not covered by hardcoded handlers above) ─
        for field in config.eventMappings.keys.sorted() {
            guard !hardcodedEventFields.contains(field),
                  let typeName = config.eventMappings[field], !typeName.isEmpty,
                  let v = fields[field] else { continue }
            var evt = CustomEvent(type: typeName)
            evt.date = DateParser.parse(v)
            // If no date parsed, store the cleaned text as a note
            if evt.date == nil || evt.date!.isEmpty { evt.note = cleanText(v) }
            person.customEvents.append(evt)
        }

        // ── Occupation ─────────────────────────────────────────────────────────
        let occKeys = ["occupation", "occupation(s)", "profession", "employer"]
        for key in occKeys {
            if let o = fields[key] {
                person.occupations.append(contentsOf: parseList(o))
            }
        }

        // ── Nationality / citizenship ──────────────────────────────────────────
        if let n = fields["nationality"] ?? fields["citizenship"] ?? fields["country"] {
            person.nationality = cleanText(n)
        }

        // ── Religion ───────────────────────────────────────────────────────────
        if let r = fields["religion"] ?? fields["faith"] {
            person.religion = cleanText(r)
        }

        // ── Image ──────────────────────────────────────────────────────────────
        if let img = fields["image"] ?? fields["photo"] ?? fields["picture"] {
            let filename = img.trimmingCharacters(in: .whitespacesAndNewlines)
                             .replacingOccurrences(of: "File:", with: "")
                             .replacingOccurrences(of: "Image:", with: "")
            if !filename.isEmpty {
                person.imageURL = wikimediaThumbURL(filename: filename)
            }
        }

        if verbose {
            fputs("  [info] Parsed infobox: \(fields.count) fields found.\n", stderr)
        }

        return (person, fields)
    }

    // MARK: - Infobox extraction

    private static func extractInfoboxFields(from wikitext: String, verbose: Bool) -> [String: String]? {
        // Find the start of any {{Infobox ...}} template
        let lower = wikitext.lowercased()
        guard let startRange = lower.range(of: "{{infobox") else { return nil }

        let startIdx = wikitext.distance(from: wikitext.startIndex, to: startRange.lowerBound)

        if verbose {
            let nameEnd = wikitext.index(startRange.lowerBound, offsetBy: 40, limitedBy: wikitext.endIndex) ?? wikitext.endIndex
            fputs("  [info] Found infobox: \(wikitext[startRange.lowerBound..<nameEnd])...\n", stderr)
        }

        // Extract the balanced {{ }} block
        var depth = 0
        let chars = Array(wikitext)
        var i = startIdx
        var blockStart = i
        var blockEnd = i

        while i < chars.count - 1 {
            if chars[i] == "{" && chars[i+1] == "{" {
                if depth == 0 { blockStart = i }
                depth += 1
                i += 2
                continue
            }
            if chars[i] == "}" && chars[i+1] == "}" {
                depth -= 1
                if depth == 0 { blockEnd = i + 2; break }
                i += 2
                continue
            }
            i += 1
        }

        guard blockEnd > blockStart else { return nil }
        let block = String(chars[blockStart..<blockEnd])

        return parseInfoboxBlock(block)
    }

    private static func parseInfoboxBlock(_ block: String) -> [String: String] {
        var fields: [String: String] = [:]

        // Split on | but respect nested {{ }} and [[ ]]
        var currentField = ""
        var depth = 0
        let chars = Array(block)
        var i = 0

        // Skip the template name line (first part before first |)
        var foundFirstPipe = false

        while i < chars.count {
            let c = chars[i]
            let hasNext = i + 1 < chars.count
            let next: Character = hasNext ? chars[i+1] : "\0"

            if c == "{" && next == "{" {
                depth += 1; currentField.append(c); currentField.append(next); i += 2
            } else if c == "[" && next == "[" {
                depth += 1; currentField.append(c); currentField.append(next); i += 2
            } else if c == "}" && next == "}" {
                depth -= 1; currentField.append(c); currentField.append(next); i += 2
            } else if c == "]" && next == "]" {
                depth -= 1; currentField.append(c); currentField.append(next); i += 2
            } else if c == "|" && depth <= 1 {
                if !foundFirstPipe {
                    foundFirstPipe = true
                    currentField = ""
                } else {
                    addField(currentField, to: &fields)
                    currentField = ""
                }
                i += 1
            } else {
                currentField.append(c)
                i += 1
            }
        }
        // Last field
        if foundFirstPipe && !currentField.isEmpty {
            addField(currentField, to: &fields)
        }

        return fields
    }

    private static func addField(_ raw: String, to fields: inout [String: String]) {
        // Each field is "key = value"
        guard let eqRange = raw.range(of: "=") else { return }
        let key = String(raw[raw.startIndex..<eqRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        let value = String(raw[eqRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty && !value.isEmpty {
            fields[key] = value
        }
    }

    // MARK: - Helpers

    static func cleanText(_ s: String) -> String? {
        var t = s

        // Remove ref tags first (including multiline content)
        if let regex = try? NSRegularExpression(pattern: "<ref[^>]*>.*?</ref>",
                                                 options: [.dotMatchesLineSeparators]) {
            t = regex.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
        }
        t = t.replacingOccurrences(of: #"<ref[^/]*/>"#, with: "", options: .regularExpression)

        // Replace <br> with comma before stripping other tags
        t = t.replacingOccurrences(of: #"<br\s*/?>"#, with: ", ", options: [.regularExpression, .caseInsensitive])

        // Strip HTML tags
        t = t.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        // Decode common HTML entities
        t = t.replacingOccurrences(of: "&nbsp;",  with: " ")
        t = t.replacingOccurrences(of: "&amp;",   with: "&")
        t = t.replacingOccurrences(of: "&lt;",    with: "<")
        t = t.replacingOccurrences(of: "&gt;",    with: ">")
        t = t.replacingOccurrences(of: "&quot;",  with: "\"")
        t = t.replacingOccurrences(of: "&#160;",  with: " ")
        t = t.replacingOccurrences(of: "&#8211;", with: "–")
        t = t.replacingOccurrences(of: "&#8212;", with: "—")

        // Unwrap single-argument wrapper templates before further processing
        t = t.replacingOccurrences(of: #"\{\{(?:awrap|nowrap)\|([^|{}]+)\}\}"#,
                                   with: "$1",
                                   options: [.regularExpression, .caseInsensitive])

        // Expand list templates: {{hlist|a|b|c}} → a, b, c
        t = expandListTemplates(t)

        // Remove remaining wikitext templates
        t = stripTemplates(t)

        // Strip wikilinks [[target|display]] → display, [[target]] → target
        t = t.replacingOccurrences(of: #"\[\[(?:[^\]|]*\|)?([^\]]+)\]\]"#, with: "$1", options: .regularExpression)
        // Remove any leftover single [ ] brackets
        t = t.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")

        // Strip bullet markers that survive list template expansion
        t = t.replacingOccurrences(of: #"(^|,\s*)\*\s*"#, with: "$1", options: .regularExpression)

        // Newlines → space
        t = t.replacingOccurrences(of: "\n", with: " ")

        // Clean up extra spaces and trailing punctuation
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        t = t.trimmingCharacters(in: .init(charactersIn: " ,;"))

        return t.isEmpty ? nil : t
    }

    private static func expandListTemplates(_ s: String) -> String {
        // {{hlist|a|b|c}}, {{flatlist|...}}, {{ubl|a|b}} → "a, b, c"
        let listTemplates = ["hlist", "flatlist", "ubl", "ublist", "plainlist", "bulleted list",
                             "unbulleted list", "cslist", "collapsible list"]
        var result = s
        for tmpl in listTemplates {
            guard let regex = try? NSRegularExpression(
                pattern: "\\{\\{\\s*\(NSRegularExpression.escapedPattern(for: tmpl))\\s*\\|([^}]*)\\}\\}",
                options: .caseInsensitive
            ) else { continue }
            let ns = result as NSString
            var offset = 0
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
            for match in matches {
                let range = NSRange(location: match.range.location + offset, length: match.range.length)
                if match.range(at: 1).location != NSNotFound {
                    let argsRange = NSRange(location: match.range(at: 1).location + offset,
                                           length: match.range(at: 1).length)
                    let args = (result as NSString).substring(with: argsRange)
                    let items = args.components(separatedBy: "|")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty && !$0.contains("=") }
                        .map { $0.replacingOccurrences(of: #"^\s*\*\s*"#, with: "", options: .regularExpression) }
                        .filter { !$0.isEmpty }
                    let replacement = items.joined(separator: ", ")
                    result = (result as NSString).replacingCharacters(in: range, with: replacement)
                    offset += replacement.count - match.range.length
                }
            }
        }
        return result
    }

    private static func stripTemplates(_ s: String) -> String {
        // For known display templates, extract their text argument
        // {{small|text}}, {{nowrap|text}}, {{lang|xx|text}} → text
        var result = s
        let displayTemplates = ["small", "nowrap", "lang", "abbr", "tooltip", "ill", "interlanguage link"]
        for tmpl in displayTemplates {
            result = result.replacingOccurrences(
                of: #"\{\{\#tmpl\|[^|}\n]*\|([^}]+)\}\}"#.replacingOccurrences(of: "#tmpl", with: tmpl),
                with: "$1",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        // Remove remaining templates entirely
        var output = ""
        var depth = 0
        var i = result.startIndex
        while i < result.endIndex {
            let next = result.index(after: i)
            if result[i] == "{", next < result.endIndex, result[next] == "{" {
                depth += 1
                i = result.index(after: next)
                continue
            }
            if result[i] == "}", next < result.endIndex, result[next] == "}" {
                if depth > 0 { depth -= 1 }
                i = result.index(after: next)
                continue
            }
            if depth == 0 { output.append(result[i]) }
            i = result.index(after: i)
        }
        return output
    }

    private static func parseList(_ s: String) -> [String] {
        var t = s
        t = t.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        let lines = t.components(separatedBy: .newlines)
        return lines.compactMap { cleanText($0) }
                    .map { $0.replacingOccurrences(of: #"^\s*[\*\-\•]\s*"#, with: "", options: .regularExpression) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("|") && !$0.hasSuffix("|") && !$0.contains("={{") }
    }

    // Extract the Wikipedia article target from [[Target|Display]] or [[Target]]
    private static func extractWikiTitle(from s: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]\|]+)"#) else { return nil }
        let ns = s as NSString
        guard let match = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              match.range(at: 1).location != NSNotFound else { return nil }
        let raw = ns.substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
        return raw.isEmpty ? nil : raw
    }

    // Parse a list field and return [PersonRef], preserving wikiTitle before cleaning
    private static func parsePersonRefList(_ s: String) -> [PersonRef] {
        var t = s
        t = t.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        return t.components(separatedBy: .newlines).compactMap { raw -> PersonRef? in
            let wt = extractWikiTitle(from: raw)
            guard let name = cleanText(raw) else { return nil }
            let clean = name.replacingOccurrences(of: #"^\s*[\*\-\•]\s*"#, with: "", options: .regularExpression)
            guard !clean.isEmpty && !clean.hasPrefix("|") && !clean.hasSuffix("|") && !clean.contains("={{") else { return nil }
            return PersonRef(name: clean, wikiTitle: wt)
        }
    }

    private static func parseSpouses(_ s: String) -> [SpouseInfo] {
        // {{marriage|Name|date}} or {{marriage|Name|date|end date}}
        var spouses: [SpouseInfo] = []

        // Check for {{marriage|...}} templates
        let marriagePattern = #"\{\{marriage\|([^|}]+)(?:\|([^|}]*))?(?:\|([^|}]*))?(?:\|([^}]*))?\}\}"#
        if let regex = try? NSRegularExpression(pattern: marriagePattern, options: .caseInsensitive) {
            let ns = s as NSString
            let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
            for match in matches {
                let nameRaw = (match.range(at: 1).location != NSNotFound) ? ns.substring(with: match.range(at: 1)) : ""
                let startDate = (match.range(at: 2).location != NSNotFound) ? ns.substring(with: match.range(at: 2)) : ""
                let wt = extractWikiTitle(from: nameRaw)
                var info = SpouseInfo(name: cleanText(nameRaw) ?? nameRaw, wikiTitle: wt)
                if !startDate.isEmpty { info.marriageDate = DateParser.parse(startDate) }
                spouses.append(info)
            }
        }

        if spouses.isEmpty {
            // Plain text / wikilinks — extract wikiTitle before cleaning
            var t = s
            t = t.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            spouses = t.components(separatedBy: .newlines).compactMap { raw -> SpouseInfo? in
                let wt = extractWikiTitle(from: raw)
                guard let name = cleanText(raw) else { return nil }
                let clean = name.replacingOccurrences(of: #"^\s*[\*\-\•]\s*"#, with: "", options: .regularExpression)
                guard !clean.isEmpty && !clean.hasPrefix("|") && !clean.hasSuffix("|") && !clean.contains("={{") else { return nil }
                return SpouseInfo(name: clean, wikiTitle: wt)
            }
        }

        return spouses
    }

    private static func wikimediaThumbURL(filename: String) -> String {
        // Convert spaces to underscores, URL-encode
        let normalized = filename
            .replacingOccurrences(of: " ", with: "_")
        let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalized
        return "https://commons.wikimedia.org/wiki/Special:FilePath/\(encoded)?width=400"
    }
}
