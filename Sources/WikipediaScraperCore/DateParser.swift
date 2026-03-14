// DateParser.swift — Parse Wikipedia date strings into GEDCOMDate

import Foundation

public struct DateParser {

    // Parse wikitext date templates and plain text dates
    public static func parse(_ raw: String) -> GEDCOMDate? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        var result = GEDCOMDate()
        result.original = s

        // Strip HTML tags
        s = stripPattern(#"<[^>]+>"#, from: s, replacement: "")

        // Handle known wikitext date templates first: {{birth date|YYYY|M|D}}, etc.
        if let parsed = parseWikitextTemplate(s) {
            return parsed
        }

        // Strip remaining/unknown wikitext templates (e.g. {{efn|...}}, {{circa|...}})
        s = stripAllTemplates(s)

        // Strip wikilinks [[Target|Display]] → Display
        s = stripPattern(#"\[\[(?:[^\]|]*\|)?([^\]]+)\]\]"#, from: s, replacement: "$1")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for qualifiers in the leading text
        let lower = s.lowercased()
        if lower.hasPrefix("c.") || lower.hasPrefix("ca.") || lower.hasPrefix("circa") ||
           lower.hasPrefix("abt") || lower.hasPrefix("about") || lower.hasPrefix("approx") {
            result.qualifier = .about
            s = stripPattern(#"^(c\.|ca\.|circa|abt\.?|about|approx\.?)\s*"#, from: s,
                             replacement: "", options: [.regularExpression, .caseInsensitive])
        } else if lower.hasPrefix("bef") || lower.hasPrefix("before") {
            result.qualifier = .before
            s = stripPattern(#"^(bef\.?|before)\s*"#, from: s,
                             replacement: "", options: [.regularExpression, .caseInsensitive])
        } else if lower.hasPrefix("aft") || lower.hasPrefix("after") {
            result.qualifier = .after
            s = stripPattern(#"^(aft\.?|after)\s*"#, from: s,
                             replacement: "", options: [.regularExpression, .caseInsensitive])
        }

        // Try parsing remaining string as a date
        if let d = parseTextDate(s) {
            result.day   = d.day
            result.month = d.month
            result.year  = d.year
            return result.isEmpty ? nil : result
        }
        return nil
    }

    // MARK: - Date range parser

    /// Parse a date range like "20 June 1837 – 22 January 1901" or {{reign|Y|M|D|Y|M|D}}.
    /// Returns (start, end) — either may be nil.
    public static func parseRange(_ raw: String) -> (start: GEDCOMDate?, end: GEDCOMDate?) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return (nil, nil) }

        s = stripPattern(#"<[^>]+>"#, from: s, replacement: "")

        // {{reign|Y|M|D|Y|M|D}} or similar multi-date templates
        if let (name, args) = extractTemplate(s) {
            let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
            if lower.hasPrefix("reign") || lower == "years active" || lower == "active" {
                let nums = args
                    .filter { !$0.contains("=") }
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if nums.count >= 6 {
                    var start = GEDCOMDate(); start.original = s
                    start.year = nums[0]; start.month = nums[1]; start.day = nums[2]
                    var end = GEDCOMDate(); end.original = s
                    end.year = nums[3]; end.month = nums[4]; end.day = nums[5]
                    return (start.isEmpty ? nil : start, end.isEmpty ? nil : end)
                } else if nums.count >= 4 {
                    var start = GEDCOMDate(); start.original = s
                    start.year = nums[0]; start.month = nums[1]
                    var end = GEDCOMDate(); end.original = s
                    end.year = nums[2]; end.month = nums[3]
                    return (start.isEmpty ? nil : start, end.isEmpty ? nil : end)
                } else if nums.count >= 2 {
                    var start = GEDCOMDate(); start.original = s
                    start.year = nums[0]
                    var end = GEDCOMDate(); end.original = s
                    end.year = nums[1]
                    return (start.isEmpty ? nil : start, end.isEmpty ? nil : end)
                }
            }
        }

        // Replace {{Snd}} / {{ndash}} with en-dash
        s = s.replacingOccurrences(of: "{{Snd}}", with: "–", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "{{ndash}}", with: "–", options: .caseInsensitive)

        // Unwrap single-arg wrapper templates before stripping
        s = unwrapSingleArg("awrap", in: s)
        s = unwrapSingleArg("nowrap", in: s)

        // Strip remaining templates
        s = stripAllTemplates(s)

        // Split on en-dash, em-dash, or " to "
        for sep in ["–", "—", " to ", " - "] {
            if s.contains(sep) {
                let parts = s.components(separatedBy: sep)
                if parts.count >= 2 {
                    let s1 = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let s2 = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    let start = s1.isEmpty ? nil : parse(s1)
                    let end   = s2.isEmpty ? nil : parse(s2)
                    if start != nil || end != nil { return (start, end) }
                }
            }
        }

        // No separator — single start date
        return (parse(s), nil)
    }

    public static func unwrapSingleArg(_ name: String, in s: String) -> String {
        guard s.contains("{{") else { return s }
        let pat = "\\{\\{\\s*\(NSRegularExpression.escapedPattern(for: name))\\s*\\|([^{}]*)\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) else { return s }
        return regex.stringByReplacingMatches(
            in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
    }

    // MARK: - Wikitext template parser

    private static func parseWikitextTemplate(_ s: String) -> GEDCOMDate? {
        // Match the outermost {{ ... }}
        guard let (name, argParts) = extractTemplate(s) else { return nil }

        var result = GEDCOMDate()
        result.original = s

        let lower = name.lowercased()

        if lower.contains("birth date") || lower.contains("death date") ||
           lower.contains("start date") || lower.contains("end date") || lower == "bda" {
            // Filter out key=value args, keep positional numeric args
            let nums = argParts
                .filter { !$0.contains("=") }
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if nums.count >= 3 { result.year = nums[0]; result.month = nums[1]; result.day = nums[2] }
            else if nums.count == 2 { result.year = nums[0]; result.month = nums[1] }
            else if nums.count == 1 { result.year = nums[0] }
            return result.isEmpty ? nil : result
        }

        if lower.contains("circa") || lower.contains("floruit") || lower == "fl." || lower == "fl" {
            result.qualifier = .about
            let nums = argParts.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if let y = nums.first { result.year = y }
            return result.isEmpty ? nil : result
        }

        return nil
    }

    private static func extractTemplate(_ s: String) -> (name: String, args: [String])? {
        guard s.contains("{{") else { return nil }
        // Find the opening {{
        guard let openRange = s.range(of: "{{") else { return nil }
        let afterOpen = s[openRange.upperBound...]

        // Find the matching closing }}
        var depth = 1
        var idx = afterOpen.startIndex
        var content = ""
        while idx < afterOpen.endIndex {
            let c = afterOpen[idx]
            let next = afterOpen.index(after: idx)
            if c == "{", next < afterOpen.endIndex, afterOpen[next] == "{" {
                depth += 1; content.append("{"); content.append("{")
                idx = afterOpen.index(after: next)
                continue
            }
            if c == "}", next < afterOpen.endIndex, afterOpen[next] == "}" {
                depth -= 1
                if depth == 0 { break }
                content.append("}"); content.append("}")
                idx = afterOpen.index(after: next)
                continue
            }
            content.append(c)
            idx = afterOpen.index(after: idx)
        }

        let parts = content.components(separatedBy: "|")
        guard let name = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return (name, Array(parts.dropFirst()))
    }

    // MARK: - Plain text date parser

    private static let monthMap: [String: Int] = [
        "january":1, "february":2, "march":3, "april":4, "may":5, "june":6,
        "july":7, "august":8, "september":9, "october":10, "november":11, "december":12,
        "jan":1, "feb":2, "mar":3, "apr":4, "jun":6, "jul":7, "aug":8,
        "sep":9, "sept":9, "oct":10, "nov":11, "dec":12
    ]

    private static func parseTextDate(_ s: String) -> (day: Int?, month: Int?, year: Int?)? {
        let s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // ISO formats: YYYY-MM-DD or YYYY-MM
        if let iso = parseISO(s) { return iso }

        // Tokenise on spaces, commas, dots, slashes
        let separators = CharacterSet(charactersIn: " ,./")
        let tokens = s.components(separatedBy: separators)
                      .map { $0.trimmingCharacters(in: .whitespaces) }
                      .filter { !$0.isEmpty }

        var day: Int?
        var month: Int?
        var year: Int?

        for token in tokens {
            if let m = monthMap[token.lowercased()] {
                month = m
            } else if let n = Int(token) {
                if n > 31 {
                    year = n
                } else if n >= 1 && n <= 31 && day == nil && year == nil {
                    day = n
                }
            }
        }

        guard year != nil || month != nil else { return nil }
        return (day, month, year)
    }

    private static func parseISO(_ s: String) -> (day: Int?, month: Int?, year: Int?)? {
        // YYYY-MM-DD
        if s.count >= 10 {
            let parts = s.prefix(10).split(separator: "-", maxSplits: 2)
            if parts.count == 3,
               let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) {
                return (d, m, y)
            }
        }
        // YYYY-MM
        if s.count >= 7 {
            let parts = s.prefix(7).split(separator: "-", maxSplits: 1)
            if parts.count == 2,
               let y = Int(parts[0]), let m = Int(parts[1]) {
                return (nil, m, y)
            }
        }
        return nil
    }

    // MARK: - String helpers

    /// Remove all {{ ... }} template blocks from a string (used to clean footnotes, etc.)
    private static func stripAllTemplates(_ s: String) -> String {
        var output = ""
        var depth = 0
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            let next = s.index(after: i)
            if c == "{", next < s.endIndex, s[next] == "{" {
                depth += 1
                i = s.index(after: next)
                continue
            }
            if c == "}", next < s.endIndex, s[next] == "}" {
                if depth > 0 { depth -= 1 }
                i = s.index(after: next)
                continue
            }
            if depth == 0 { output.append(c) }
            i = s.index(after: i)
        }
        return output
    }

    private static func stripPattern(
        _ pattern: String,
        from s: String,
        replacement: String,
        options: NSString.CompareOptions = .regularExpression
    ) -> String {
        s.replacingOccurrences(of: pattern, with: replacement, options: options)
    }
}
