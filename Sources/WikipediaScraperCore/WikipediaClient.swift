// WikipediaClient.swift — Fetch data from Wikipedia APIs

import Foundation

public struct WikipediaSummary: Decodable {
    public let title: String
    public let extract: String?
    public let thumbnail: Thumbnail?
    public let originalimage: Thumbnail?

    public struct Thumbnail: Decodable {
        public let source: String
        public let width: Int?
        public let height: Int?
    }
}

public struct WikipediaClient {

    // MARK: - Public API

    /// Fetch summary (thumbnail URL, extract) from REST API
    public static func fetchSummary(pageTitle: String, verbose: Bool) async throws -> WikipediaSummary {
        let encoded = pageTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pageTitle
        let urlStr = "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)"
        guard let url = URL(string: urlStr) else { throw ScraperError.invalidURL(urlStr) }
        if verbose { fputs("  [fetch] \(urlStr)\n", stderr) }
        let (data, resp) = try await URLSession.shared.data(from: url)
        try checkHTTP(resp, url: urlStr)
        return try JSONDecoder().decode(WikipediaSummary.self, from: data)
    }

    /// Fetch raw wikitext via MediaWiki action API
    public static func fetchWikitext(pageTitle: String, verbose: Bool) async throws -> String {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "titles", value: pageTitle),
            URLQueryItem(name: "prop", value: "revisions"),
            URLQueryItem(name: "rvprop", value: "content"),
            URLQueryItem(name: "rvslots", value: "main"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]
        guard let url = components.url else { throw ScraperError.invalidURL("wikitext API") }
        if verbose { fputs("  [fetch] \(url.absoluteString)\n", stderr) }
        let (data, resp) = try await URLSession.shared.data(from: url)
        try checkHTTP(resp, url: url.absoluteString)

        // Parse: {query: {pages: [{revisions: [{slots: {main: {content: "..."}}}]}]}}
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = json["query"] as? [String: Any],
              let pages = query["pages"] as? [[String: Any]],
              let page = pages.first,
              let revisions = page["revisions"] as? [[String: Any]],
              let revision = revisions.first,
              let slots = revision["slots"] as? [String: Any],
              let mainSlot = slots["main"] as? [String: Any],
              let content = mainSlot["content"] as? String
        else {
            throw ScraperError.parseError("Could not extract wikitext from API response")
        }
        return content
    }

    /// Resolve page title from a Wikipedia URL
    public static func pageTitle(from urlString: String) throws -> String {
        guard let url = URL(string: urlString) else { throw ScraperError.invalidURL(urlString) }
        let path = url.path  // e.g. /wiki/George_Washington
        guard path.hasPrefix("/wiki/") else { throw ScraperError.invalidURL("URL must be a Wikipedia article: \(urlString)") }
        let raw = String(path.dropFirst("/wiki/".count))
        // Decode percent encoding, replace _ with space
        let decoded = raw.removingPercentEncoding ?? raw
        return decoded.replacingOccurrences(of: "_", with: " ")
    }

    /// Fetch the article as (sectionTitle, plainText) pairs for --notes
    public static func fetchSections(pageTitle: String, verbose: Bool) async throws -> [(title: String, text: String)] {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action",          value: "query"),
            URLQueryItem(name: "titles",          value: pageTitle),
            URLQueryItem(name: "prop",            value: "extracts"),
            URLQueryItem(name: "explaintext",     value: "1"),
            URLQueryItem(name: "exsectionformat", value: "wiki"),
            URLQueryItem(name: "format",          value: "json"),
            URLQueryItem(name: "formatversion",   value: "2"),
        ]
        guard let url = components.url else { throw ScraperError.invalidURL("sections API") }
        if verbose { fputs("  [fetch] \(url.absoluteString)\n", stderr) }
        let (data, resp) = try await URLSession.shared.data(from: url)
        try checkHTTP(resp, url: url.absoluteString)

        guard let json   = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query  = json["query"]  as? [String: Any],
              let pages  = query["pages"] as? [[String: Any]],
              let page   = pages.first,
              let extract = page["extract"] as? String
        else { return [] }

        return parseSections(from: extract)
    }

    private static func parseSections(from extract: String) -> [(title: String, text: String)] {
        // Section headers appear as  \n\n== Title ==\n\n  (any level of =)
        guard let regex = try? NSRegularExpression(pattern: #"\n\n(==+)\s*(.+?)\s*\1\n\n"#) else {
            let t = extract.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? [] : [("Introduction", t)]
        }

        var sections: [(title: String, text: String)] = []
        var headerRanges: [(range: Range<String.Index>, title: String)] = []

        for match in regex.matches(in: extract, range: NSRange(extract.startIndex..., in: extract)) {
            guard let titleR = Range(match.range(at: 2), in: extract),
                  let fullR  = Range(match.range,        in: extract) else { continue }
            headerRanges.append((range: fullR, title: String(extract[titleR])))
        }

        // Intro: text before first header
        let introEnd = headerRanges.first?.range.lowerBound ?? extract.endIndex
        let introText = String(extract[extract.startIndex..<introEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !introText.isEmpty { sections.append(("Introduction", introText)) }

        // Each named section
        for (i, header) in headerRanges.enumerated() {
            let textStart = header.range.upperBound
            let textEnd   = i + 1 < headerRanges.count ? headerRanges[i+1].range.lowerBound
                                                        : extract.endIndex
            let text = String(extract[textStart..<textEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { sections.append((header.title, text)) }
        }
        return sections
    }

    // MARK: - All-images support

    /// Fetch URLs for all raster images in the article (for --allimages).
    /// Returns (displayTitle, url, mimeType) sorted by name; portrait URL excluded if provided.
    public static func fetchAllImageURLs(
        pageTitle:    String,
        excludingURL: String?,
        verbose:      Bool
    ) async throws -> [(title: String, url: String, mime: String)] {

        // ── Step 1: list of image File: titles ────────────────────────────
        var c1 = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        c1.queryItems = [
            URLQueryItem(name: "action",        value: "query"),
            URLQueryItem(name: "titles",        value: pageTitle),
            URLQueryItem(name: "prop",          value: "images"),
            URLQueryItem(name: "imlimit",       value: "100"),
            URLQueryItem(name: "format",        value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
        ]
        guard let url1 = c1.url else { throw ScraperError.invalidURL("images list API") }
        if verbose { fputs("  [fetch] images list \(url1.absoluteString)\n", stderr) }
        let (data1, resp1) = try await URLSession.shared.data(from: url1)
        try checkHTTP(resp1, url: url1.absoluteString)

        guard let j1     = try JSONSerialization.jsonObject(with: data1) as? [String: Any],
              let q1     = j1["query"]  as? [String: Any],
              let pages1 = q1["pages"]  as? [[String: Any]],
              let pg1    = pages1.first,
              let images = pg1["images"] as? [[String: Any]]
        else { return [] }

        let rasterExts = Set(["jpg","jpeg","png","webp"])
        // Skip decorative/icon filenames
        let skipPrefixes = ["wikipedia logo", "pictogram", "question mark", "crystal clear",
                            "ambox", "icon-", "flag of", "commons-logo", "edit-clear",
                            "wikimedia", "nuvola", "gnome-", "portal-", "disambig"]
        let filenames: [String] = images
            .compactMap { $0["title"] as? String }
            .filter { title in
                let ext  = (title as NSString).pathExtension.lowercased()
                guard rasterExts.contains(ext) else { return false }
                let lower = title.lowercased()
                return !skipPrefixes.contains { lower.contains($0) }
            }
        guard !filenames.isEmpty else { return [] }

        // ── Step 2: batch-fetch imageinfo (url, mime, size) ───────────────
        var results: [(title: String, url: String, mime: String)] = []
        let batchSize = 20
        for batchStart in stride(from: 0, to: filenames.count, by: batchSize) {
            let batch  = filenames[batchStart ..< min(batchStart + batchSize, filenames.count)]
            var c2     = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
            c2.queryItems = [
                URLQueryItem(name: "action",        value: "query"),
                URLQueryItem(name: "titles",        value: batch.joined(separator: "|")),
                URLQueryItem(name: "prop",          value: "imageinfo"),
                URLQueryItem(name: "iiprop",        value: "url|mime|size"),
                URLQueryItem(name: "format",        value: "json"),
                URLQueryItem(name: "formatversion", value: "2"),
            ]
            guard let url2 = c2.url else { continue }
            if verbose { fputs("  [fetch] imageinfo batch \(batchStart/batchSize + 1)\n", stderr) }
            guard let (data2, resp2) = try? await URLSession.shared.data(from: url2) else { continue }
            guard (try? checkHTTP(resp2, url: url2.absoluteString)) != nil else { continue }

            guard let j2     = try? JSONSerialization.jsonObject(with: data2) as? [String: Any],
                  let q2     = j2["query"]  as? [String: Any],
                  let pages2 = q2["pages"]  as? [[String: Any]]
            else { continue }

            for page in pages2 {
                guard let fileTitle = page["title"] as? String,
                      let infoArr   = page["imageinfo"] as? [[String: Any]],
                      let info      = infoArr.first,
                      let imgURL    = info["url"]    as? String,
                      let mime      = info["mime"]   as? String,
                      let w         = info["width"]  as? Int,
                      let h         = info["height"] as? Int
                else { continue }

                // Skip tiny images (icons / thumbnails)
                guard w >= 100 && h >= 100 else { continue }

                // Skip if this matches the portrait already captured.
                // The portrait URL may be a thumbnail (e.g. "1920px-Name.jpg") while
                // imageinfo returns the full-res URL ("Name.jpg"), so strip the NNNpx- prefix.
                if let excl = excludingURL {
                    if imgURL == excl { continue }
                    let stripDim: (String) -> String = {
                        $0.replacingOccurrences(of: #"^\d+px-"#, with: "",
                                                options: .regularExpression)
                    }
                    let exclBase = stripDim(
                        (excl    as NSString).lastPathComponent.removingPercentEncoding ?? "")
                    let thisBase = stripDim(
                        (imgURL  as NSString).lastPathComponent.removingPercentEncoding ?? "")
                    if !exclBase.isEmpty && exclBase == thisBase { continue }
                }

                let supported = ["image/jpeg","image/png","image/webp"]
                if supported.contains(mime.lowercased()) {
                    results.append((title: fileTitle, url: imgURL, mime: mime))
                }
            }
        }
        return results
    }

    /// Download image data from a URL
    public static func fetchImageData(from urlString: String, verbose: Bool) async throws -> (Data, String) {
        guard let url = URL(string: urlString) else { throw ScraperError.invalidURL(urlString) }
        if verbose { fputs("  [fetch] image \(urlString)\n", stderr) }
        let (data, resp) = try await URLSession.shared.data(from: url)
        let mimeType = (resp as? HTTPURLResponse)?.mimeType ?? "image/jpeg"
        return (data, mimeType)
    }

    // MARK: - Private

    private static func checkHTTP(_ response: URLResponse, url: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw ScraperError.httpError(http.statusCode, url)
        }
    }
}

// MARK: - Errors

public enum ScraperError: LocalizedError {
    case invalidURL(String)
    case httpError(Int, String)
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let s): return "Invalid URL: \(s)"
        case .httpError(let code, let url): return "HTTP \(code) from \(url)"
        case .parseError(let msg): return "Parse error: \(msg)"
        }
    }
}
