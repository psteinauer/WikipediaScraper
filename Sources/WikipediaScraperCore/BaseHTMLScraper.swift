// BaseHTMLScraper.swift — Shared base class for HTML-based person-page scrapers
//
// To add support for a new HTML-based website:
//   1. Create `final class MyScraper: BaseHTMLScraper` in a new file
//   2. Override `supportedHosts`, optionally override `canHandle(url:)`, and
//      override `validate(html:url:)` and `parsePage(html:sourceURL:options:verbose:)`
//   3. Add your scraper to the `entries` array in `ScraperRegistry`
//
// `BaseHTMLScraper` handles:
//   - Fetching the HTML document (UTF-8 with ISO-Latin-1 fallback)
//   - Calling validate() then parsePage() in sequence
//   - HTML tag stripping and entity decoding
//   - Common date/place/cause string splitting
//
// Subclasses are responsible for site-specific HTML structure interpretation.

import Foundation

/// Abstract base class for scrapers that work against plain HTML person pages.
///
/// Subclasses must override `parsePage(html:sourceURL:options:verbose:)` to
/// extract a `PersonData` value from the raw HTML string.  They should also
/// override `supportedHosts` and, when the default host-suffix logic is
/// insufficient, `canHandle(url:)`.
///
/// HTML utility methods (`stripHTML`, `extractTagContent`, etc.) and date/place
/// helpers (`parseDatePlace`, `parseDatePlaceCause`) are provided as `internal`
/// methods so all subclasses can use them without reimplementation.
open class BaseHTMLScraper: PersonPageScraper {

    // MARK: - PersonPageScraper — subclasses must override

    /// Lower-case hostnames this scraper handles. Override in every subclass.
    open class var supportedHosts: [String] { [] }

    public required init() {}

    // MARK: - Scrape entry point (provided; subclasses typically don't override)

    public func scrape(url: URL, options: ScrapeOptions, verbose: Bool) async throws -> PersonData {
        if verbose { fputs("  [\(type(of: self))] Fetching '\(url.absoluteString)'…\n", stderr) }
        let html = try await fetchHTML(url: url)
        try validate(html: html, url: url)
        return try parsePage(html: html, sourceURL: url, options: options, verbose: verbose)
    }

    // MARK: - Subclass hooks

    /// Override to validate that the fetched HTML actually represents a person page.
    /// Throw `ScraperError.notAPersonPage` if the content is not a biography.
    /// The default implementation always succeeds.
    open func validate(html: String, url: URL) throws {}

    /// Parse the HTML into a `PersonData` value.
    ///
    /// This method **must** be overridden by every concrete subclass.
    /// It is called after `validate(html:url:)` succeeds.
    open func parsePage(html: String, sourceURL: URL,
                        options: ScrapeOptions, verbose: Bool) throws -> PersonData {
        preconditionFailure("\(type(of: self)) must override parsePage(html:sourceURL:options:verbose:)")
    }

    // MARK: - Networking

    /// Fetch the page at `url` and return it as a string.
    /// Tries UTF-8 first, then falls back to ISO-Latin-1.
    func fetchHTML(url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1) else {
            throw ScraperError.parseError("Could not decode HTML from \(url.absoluteString)")
        }
        return html
    }

    // MARK: - HTML utilities

    /// Return the text content of the first `<tag>…</tag>` element in `html`.
    func extractTagContent(tag: String, from html: String) -> String? {
        guard let regex = try? NSRegularExpression(
                  pattern: "<\(tag)[^>]*>(.*?)</\(tag)>",
                  options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(match.range(at: 1), in: html)
        else { return nil }
        return String(html[r])
    }

    /// Return all `<b>KEY:</b> VALUE` pairs found in the HTML.
    func extractBoldFields(from html: String) -> [(key: String, value: String)] {
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

    /// Extract text content from all `<p>…</p>` elements.
    func extractParagraphs(from html: String) -> [String] {
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

    /// Return the absolute URL string of the first `<img>` or `<amp-img>` in `html`.
    func extractFirstImage(from html: String, baseURL: URL) -> String? {
        let pattern = #"<(?:amp-img|img)\s[^>]*src=['"]([^'"]+)['"]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(match.range(at: 1), in: html)
        else { return nil }
        let src = String(html[r])
        if src.hasPrefix("http")  { return src }
        if src.hasPrefix("//")    { return "https:" + src }
        if src.hasPrefix("data:") { return nil }          // inline data URI — not useful
        return URL(string: src, relativeTo: baseURL)?.absoluteString
    }

    /// Strip HTML tags and decode common entities from `s`.
    func stripHTML(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&nbsp;", " "), ("&#160;", " "), ("&#8212;", "—"),
        ]
        for (e, r) in entities { t = t.replacingOccurrences(of: e, with: r) }
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Date / place parsing helpers

    /// Split "December 6, 1421 at Windsor Castle" into `(date, "Windsor Castle")`.
    func parseDatePlace(_ s: String) -> (date: GEDCOMDate?, place: String?) {
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

    /// Split "May 21, 1471 at Tower of London (murdered), aged 49…" into
    /// `(date, place, cause)`.
    func parseDatePlaceCause(_ s: String) -> (date: GEDCOMDate?, place: String?, cause: String?) {
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
}
