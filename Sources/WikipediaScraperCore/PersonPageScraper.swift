// PersonPageScraper.swift — Protocol and global registry for person-page scrapers
//
// To add support for a new HTML-based website:
//   1. Create `final class MyScraper: BaseHTMLScraper` in a new file in WikipediaScraperCore
//      (inherit HTML utilities, date helpers, and the default scrape() flow for free)
//   2. Add it to the `entries` array in `ScraperRegistry` below
//
// To add support for a non-HTML website (e.g. a JSON API or wikitext source):
//   1. Create `struct MyScraper: PersonPageScraper` (or subclass another base class)
//   2. Add it to the `entries` array in `ScraperRegistry` below

import Foundation

// MARK: - ScrapeOptions

public struct ScrapeOptions {
    /// Fetch article sections and store them as GEDCOM notes.
    public var includeNotes:     Bool
    /// Fetch all images from the article (not just the portrait).
    public var includeAllImages: Bool
    /// Called with human-readable progress strings during scraping.
    public var onProgress:       (@Sendable (String) -> Void)?

    public init(
        includeNotes:     Bool = false,
        includeAllImages: Bool = false,
        onProgress:       (@Sendable (String) -> Void)? = nil
    ) {
        self.includeNotes     = includeNotes
        self.includeAllImages = includeAllImages
        self.onProgress       = onProgress
    }
}

// MARK: - Protocol

/// A type that fetches and parses a biographical person page from a specific website.
///
/// Each conforming type is responsible for:
/// - Declaring which hostnames it handles (`supportedHosts`)
/// - Performing the network fetch
/// - Validating that the page is actually a biography
/// - Mapping the page content into a `PersonData` value
///
/// Throw `ScraperError.notAPersonPage` when the content is not a biography.
/// Throw other `ScraperError` variants for network or parse failures.
public protocol PersonPageScraper {

    /// Lower-case hostnames this scraper handles (exact match or as a suffix).
    static var supportedHosts: [String] { get }

    init()

    func scrape(url: URL, options: ScrapeOptions, verbose: Bool) async throws -> PersonData
}

public extension PersonPageScraper {
    /// Default host-matching: URL host equals or ends with `".<entry>"`.
    /// Concrete types may override for finer-grained matching.
    static func canHandle(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return supportedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

// MARK: - Registry

/// Global list of registered scrapers, in priority order.
///
/// Add new scrapers to `entries` — no other change is required to
/// enable them throughout the app and command-line tool.
public enum ScraperRegistry {

    // ── Register new scrapers here ────────────────────────────────────────
    private static let entries: [(canHandle: (URL) -> Bool, make: () -> any PersonPageScraper)] = [
        ({ WikipediaScraper.canHandle(url: $0)  }, { WikipediaScraper()  }),
        ({ BritRoyalsScraper.canHandle(url: $0) }, { BritRoyalsScraper() }),
    ]
    // ─────────────────────────────────────────────────────────────────────

    /// Returns a scraper that handles `url`, or `nil` if none is registered.
    public static func scraper(for url: URL) -> (any PersonPageScraper)? {
        entries.first { $0.canHandle(url) }.map { $0.make() }
    }

    /// Returns `true` if any registered scraper handles `url`.
    public static func canScrape(_ url: URL) -> Bool {
        entries.contains { $0.canHandle(url) }
    }
}
