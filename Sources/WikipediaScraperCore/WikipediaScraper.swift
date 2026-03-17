// WikipediaScraper.swift — PersonPageScraper for English Wikipedia

import Foundation

public struct WikipediaScraper: PersonPageScraper {

    /// Matches any Wikipedia subdomain (en, fr, de, en.m, …).
    public static let supportedHosts = ["wikipedia.org"]

    public init() {}

    public func scrape(url: URL, options: ScrapeOptions, verbose: Bool) async throws -> PersonData {
        let urlString = url.absoluteString
        let pageTitle = try WikipediaClient.pageTitle(from: urlString)

        if verbose { fputs("  [wikipedia] Fetching '\(pageTitle)'…\n", stderr) }

        async let summaryFetch  = WikipediaClient.fetchSummary(pageTitle: pageTitle, verbose: verbose)
        async let wikitextFetch = WikipediaClient.fetchWikitext(pageTitle: pageTitle, verbose: verbose)
        let (summary, wikitext) = try await (summaryFetch, wikitextFetch)

        guard InfoboxParser.isPersonPage(wikitext: wikitext) else {
            throw ScraperError.notAPersonPage(pageTitle)
        }

        var (person, _) = InfoboxParser.parse(
            wikitext: wikitext, pageTitle: pageTitle, verbose: verbose)

        // Merge REST-summary data
        person.wikiURL   = urlString
        person.wikiTitle = summary.title
        if (person.wikiExtract ?? "").isEmpty { person.wikiExtract = summary.extract }
        person.imageURL  = summary.originalimage?.source ?? summary.thumbnail?.source ?? person.imageURL

        // Optional: article sections as GEDCOM notes
        if options.includeNotes {
            options.onProgress?("Fetching article sections…")
            person.wikiSections = (try? await WikipediaClient.fetchSections(
                pageTitle: pageTitle, verbose: verbose)) ?? []
        }

        // Optional: all raster images in the article
        if options.includeAllImages {
            options.onProgress?("Fetching image list…")
            let primary = person.imageURL.flatMap { $0.isEmpty ? nil : $0 }
            if let infos = try? await WikipediaClient.fetchAllImageURLs(
                pageTitle: pageTitle, excludingURL: primary, verbose: verbose) {
                person.additionalMedia = infos.map { info in
                    let title = info.title
                        .replacingOccurrences(of: "File:", with: "")
                        .replacingOccurrences(of: "_", with: " ")
                    return AdditionalMedia(filePath: info.url, origURL: info.url, title: title)
                }
            }
        }

        return person
    }
}
