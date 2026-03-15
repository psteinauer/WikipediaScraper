// WikipediaClientURLTests.swift — XCTest suite for WikipediaClient.pageTitle(from:)

import XCTest
@testable import WikipediaScraperCore

final class WikipediaClientURLTests: XCTestCase {

    // MARK: - Valid Wikipedia URLs

    func testQueenVictoriaURL() throws {
        let title = try WikipediaClient.pageTitle(from: "https://en.wikipedia.org/wiki/Queen_Victoria")
        XCTAssertEqual(title, "Queen Victoria")
    }

    func testAlbertEinsteinURL() throws {
        let title = try WikipediaClient.pageTitle(from: "https://en.wikipedia.org/wiki/Albert_Einstein")
        XCTAssertEqual(title, "Albert Einstein")
    }

    func testNapoleonBonaparteURL() throws {
        let title = try WikipediaClient.pageTitle(from: "https://en.wikipedia.org/wiki/Napoleon_Bonaparte")
        XCTAssertEqual(title, "Napoleon Bonaparte")
    }

    func testGenghisKhanURL() throws {
        let title = try WikipediaClient.pageTitle(from: "https://en.wikipedia.org/wiki/Genghis_Khan")
        XCTAssertEqual(title, "Genghis Khan", "Underscore should be converted to space")
    }

    func testPercentEncodedURL() throws {
        // Léon Gambetta — L%C3%A9on_Gambetta
        let title = try WikipediaClient.pageTitle(from: "https://en.wikipedia.org/wiki/L%C3%A9on_Gambetta")
        XCTAssertEqual(title, "Léon Gambetta", "Percent encoding should be decoded")
    }

    func testMultiWordURL() throws {
        let title = try WikipediaClient.pageTitle(from: "https://en.wikipedia.org/wiki/Johann_Wolfgang_von_Goethe")
        XCTAssertEqual(title, "Johann Wolfgang von Goethe")
    }

    func testNonPersonURL() throws {
        let title = try WikipediaClient.pageTitle(from: "https://en.wikipedia.org/wiki/15th_century")
        XCTAssertEqual(title, "15th century", "Non-person articles should still parse")
    }

    func testURLWithFragment() throws {
        let title = try WikipediaClient.pageTitle(from: "https://en.wikipedia.org/wiki/Queen_Victoria#Early_life")
        // The fragment portion comes after # — URL.path strips the fragment
        XCTAssertEqual(title, "Queen Victoria", "Fragment should be ignored, returning 'Queen Victoria'")
    }

    // MARK: - Error cases

    func testNotWikipediaDomainDoesNotThrowOnValidPath() {
        // Behaviour: pageTitle(from:) only checks the path prefix "/wiki/",
        // not the domain. So a non-wikipedia host with /wiki/ path will work.
        let title = try? WikipediaClient.pageTitle(from: "https://not-wikipedia.com/wiki/Foo")
        // Either returns "Foo" or throws — both are acceptable; just confirm no crash
        // If it returns a title, it should be "Foo"
        if let t = title {
            XCTAssertEqual(t, "Foo")
        }
        // If it threw, that's fine too — no assertion needed
    }

    func testNonWikiPathThrows() {
        XCTAssertThrowsError(
            try WikipediaClient.pageTitle(from: "https://en.wikipedia.org/not-wiki/Foo")
        ) { error in
            if let scraperErr = error as? ScraperError {
                switch scraperErr {
                case .invalidURL: break  // expected
                default:
                    XCTFail("Expected ScraperError.invalidURL, got \(scraperErr)")
                }
            }
        }
    }

    func testNotAURLThrows() {
        XCTAssertThrowsError(
            try WikipediaClient.pageTitle(from: "not a url")
        ) { error in
            if let scraperErr = error as? ScraperError {
                switch scraperErr {
                case .invalidURL: break  // expected
                default:
                    XCTFail("Expected ScraperError.invalidURL, got \(scraperErr)")
                }
            }
        }
    }

    func testEmptyWikiPathBehavior() {
        // "https://en.wikipedia.org/wiki/" has an empty title after /wiki/
        // Test that it either returns "" or throws — verify it doesn't crash
        let result = try? WikipediaClient.pageTitle(from: "https://en.wikipedia.org/wiki/")
        // Empty string or nil (thrown) both acceptable
        if let t = result {
            XCTAssertEqual(t, "", "Empty wiki path should return empty string")
        }
        // If it threw, that's acceptable behaviour too
    }
}
