// LLMParser.swift — Claude AI-assisted Wikipedia article analysis for genealogy

import Foundation

// MARK: - LLM Analysis Result

public struct LLMAnalysis {
    public var alternateNames:   [String]          = []
    public var additionalTitles: [String]           = []
    public var additionalFacts:  [PersonFact]       = []
    public var additionalEvents: [CustomEvent]      = []
    public var influentialPeople: [InfluentialPerson] = []

    public init() {}
}

// MARK: - Claude API client

public struct LLMClient {

    // MARK: - Public entry point

    /// Analyse a Wikipedia article with Claude and return enriched genealogical data.
    ///
    /// - Parameters:
    ///   - pageTitle: Wikipedia article title (used for context in the prompt).
    ///   - wikitext:  Raw wikitext of the article (truncated internally to keep tokens reasonable).
    ///   - extract:   Plain-text summary from the REST API (prepended to the prompt for clarity).
    ///   - apiKey:    Anthropic API key (`ANTHROPIC_API_KEY` env var or `--api-key` option).
    ///   - model:     Claude model ID (default `claude-sonnet-4-6`).
    ///   - verbose:   Print progress to stderr.
    public static func analyze(
        pageTitle: String,
        wikitext:  String,
        extract:   String?,
        apiKey:    String,
        model:     String = "claude-sonnet-4-6",
        verbose:   Bool   = false
    ) async throws -> LLMAnalysis {

        if verbose { fputs("  [llm] Calling Claude (\(model)) for \(pageTitle)…\n", stderr) }

        let requestBody = buildRequest(
            pageTitle: pageTitle,
            wikitext:  wikitext,
            extract:   extract,
            model:     model)

        let responseJSON = try await callAPI(requestBody: requestBody, apiKey: apiKey)

        let analysis = parseResponse(responseJSON, verbose: verbose)

        if verbose {
            fputs("  [llm] Found: \(analysis.alternateNames.count) alt names, " +
                  "\(analysis.additionalTitles.count) titles, " +
                  "\(analysis.additionalFacts.count) facts, " +
                  "\(analysis.additionalEvents.count) events, " +
                  "\(analysis.influentialPeople.count) influential people\n", stderr)
        }

        return analysis
    }

    // MARK: - Request construction

    private static func buildRequest(
        pageTitle: String,
        wikitext:  String,
        extract:   String?,
        model:     String
    ) -> [String: Any] {

        // Truncate wikitext to keep token count reasonable (wikitext is dense markup)
        let maxWikitextChars = 30_000
        let truncatedWikitext = wikitext.count > maxWikitextChars
            ? String(wikitext.prefix(maxWikitextChars)) + "\n\n[… article truncated …]"
            : wikitext

        var userContent = "Wikipedia article: \"\(pageTitle)\"\n\n"
        if let e = extract, !e.isEmpty {
            userContent += "=== Summary ===\n\(e)\n\n"
        }
        userContent += "=== Wikitext ===\n\(truncatedWikitext)"

        return [
            "model": model,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userContent]
            ]
        ]
    }

    // MARK: - API call

    private static func callAPI(
        requestBody: [String: Any],
        apiKey: String
    ) async throws -> [String: Any] {

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ScraperError.invalidURL("https://api.anthropic.com/v1/messages")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json",    forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,                forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",          forHTTPHeaderField: "anthropic-version")

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ScraperError.parseError("LLM API returned non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw ScraperError.httpError(http.statusCode, "Anthropic API: \(body)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScraperError.parseError("LLM API response is not a JSON object")
        }
        return json
    }

    // MARK: - Response parsing

    private static func parseResponse(
        _ json: [String: Any],
        verbose: Bool
    ) -> LLMAnalysis {

        // Extract the text content from Claude's response
        guard let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String
        else {
            if verbose { fputs("  [llm] Warning: could not extract text from response\n", stderr) }
            return LLMAnalysis()
        }

        // The model should return a JSON object; strip any surrounding markdown fences
        let cleaned = extractJSON(from: text)

        guard let jsonData = cleaned.data(using: .utf8),
              let result   = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            if verbose { fputs("  [llm] Warning: response did not contain valid JSON: \(text.prefix(200))\n", stderr) }
            return LLMAnalysis()
        }

        return parseAnalysisJSON(result)
    }

    /// Strip Markdown code fences (```json … ```) if present, leaving bare JSON.
    private static func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            // Drop the opening fence line and closing fence
            var lines = trimmed.components(separatedBy: "\n")
            if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
            if lines.last?.hasPrefix("```") == true  { lines.removeLast() }
            return lines.joined(separator: "\n")
        }
        return trimmed
    }

    private static func parseAnalysisJSON(_ obj: [String: Any]) -> LLMAnalysis {
        var analysis = LLMAnalysis()

        // Alternate names
        if let names = obj["alternate_names"] as? [String] {
            analysis.alternateNames = names.filter { !$0.isEmpty }
        }

        // Additional titles / honorifics
        if let titles = obj["additional_titles"] as? [String] {
            analysis.additionalTitles = titles.filter { !$0.isEmpty }
        }

        // Additional facts
        if let facts = obj["additional_facts"] as? [[String: Any]] {
            analysis.additionalFacts = facts.compactMap { fact in
                guard let type  = fact["type"]  as? String, !type.isEmpty,
                      let value = fact["value"] as? String, !value.isEmpty
                else { return nil }
                return PersonFact(type: type, value: value)
            }
        }

        // Additional events
        if let events = obj["additional_events"] as? [[String: Any]] {
            analysis.additionalEvents = events.compactMap { ev in
                guard let type = ev["type"] as? String, !type.isEmpty else { return nil }
                var event = CustomEvent(type: type)
                if let dateStr = ev["date"] as? String, !dateStr.isEmpty {
                    var d = GEDCOMDate()
                    d.original = dateStr
                    // Try to parse simple GEDCOM-style date from LLM output
                    parseLLMDate(dateStr, into: &d)
                    event.date = d
                }
                event.place = ev["place"] as? String
                event.note  = ev["note"]  as? String
                return event
            }
        }

        // Influential people
        if let people = obj["influential_people"] as? [[String: Any]] {
            analysis.influentialPeople = people.compactMap { p in
                guard let name = p["name"] as? String, !name.isEmpty,
                      let rel  = p["relationship"] as? String, !rel.isEmpty
                else { return nil }
                return InfluentialPerson(
                    name:         name,
                    wikiTitle:    p["wiki_title"]  as? String,
                    relationship: rel,
                    note:         p["note"] as? String)
            }
        }

        return analysis
    }

    // MARK: - Simple GEDCOM date parser for LLM-supplied strings
    //
    // The LLM is instructed to return dates in GEDCOM format (e.g. "24 MAY 1819",
    // "ABT 1820", "BEF 1900"), so we just copy the string into `original` and do
    // a best-effort structured parse so GEDCOMDate.gedcom produces the right output.

    private static func parseLLMDate(_ s: String, into d: inout GEDCOMDate) {
        let upper = s.uppercased().trimmingCharacters(in: .whitespaces)

        if upper.hasPrefix("ABT") || upper.hasPrefix("ABOUT") || upper.hasPrefix("CIRCA") || upper.hasPrefix("C.") {
            d.qualifier = .about
        } else if upper.hasPrefix("BEF") || upper.hasPrefix("BEFORE") {
            d.qualifier = .before
        } else if upper.hasPrefix("AFT") || upper.hasPrefix("AFTER") {
            d.qualifier = .after
        }

        // Strip qualifier prefix and split remaining tokens
        let stripped = upper
            .replacingOccurrences(of: "^(ABT|ABOUT|CIRCA|C\\.|BEF|BEFORE|AFT|AFTER)\\s*", with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let tokens = stripped.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        for token in tokens {
            if let y = Int(token), y > 999 && y < 3000 { d.year = y; continue }
            if let m = GEDCOMDate.monthNames.firstIndex(of: token) { d.month = m + 1; continue }
            if let day = Int(token), day >= 1 && day <= 31 { d.day = day; continue }
        }
    }

    // MARK: - System prompt

    private static let systemPrompt = """
    You are an expert genealogist analysing Wikipedia articles about historical and notable people. \
    Your task is to extract structured genealogical data that supplements the structured infobox data \
    already parsed from the article.

    Return ONLY a single valid JSON object — no prose, no markdown fences, no explanation. \
    Use this exact schema:

    {
      "alternate_names": [
        "string — other names, nicknames, birth name if different, name in another language"
      ],
      "additional_titles": [
        "string — honorifics, styles, post-nominal letters, honorary degrees not in the infobox"
      ],
      "additional_facts": [
        { "type": "string — fact category e.g. Education, Award, Residence, Military rank",
          "value": "string — the fact value" }
      ],
      "additional_events": [
        { "type": "string — event name e.g. Coronation, Trial, Exile, Appointment",
          "date": "string in GEDCOM date format e.g. 24 MAY 1819  or  ABT 1820  or  BEF 1900",
          "place": "string or null",
          "note": "string — one sentence of context, or null" }
      ],
      "influential_people": [
        { "name": "string — full name as commonly known",
          "wiki_title": "string — Wikipedia article title if the person has one, else null",
          "relationship": "string — brief label e.g. Mentor, Patron, Rival, Ally, Teacher, Student, Commander, Subordinate",
          "note": "string — one sentence describing how they influenced or related to the subject" }
      ]
    }

    Rules:
    - Only include data that is explicitly stated in the article. Do not infer or hallucinate.
    - Limit influential_people to the 10 most historically significant.
    - Do not duplicate data that is already in a standard infobox (birth, death, burial, marriage, \
      direct family members, main occupations, main titles with date ranges).
    - Dates must be in GEDCOM format: D MON YYYY (day is optional, month is 3-letter ALL-CAPS).
    - If a field has no data, use an empty array [].
    """
}
