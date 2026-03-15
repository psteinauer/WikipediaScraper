// LLMTests.swift — Liveness test for LLMClient.analyze
//
// This test requires:
//   - Network access
//   - ANTHROPIC_API_KEY environment variable to be set
//
// It is skipped automatically when the API key is not present.

import XCTest
@testable import WikipediaScraperCore

final class LLMTests: XCTestCase {

    // MARK: - Liveness test

    func testLLMAnalysisLiveness() async throws {
        // Skip if API key not set
        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("ANTHROPIC_API_KEY not set — skipping LLM liveness test")
        }

        // Fetch a short article (Albert Einstein) for the test
        let pageTitle = "Albert Einstein"
        let wikitext: String
        let extract: String?

        do {
            async let wikitextTask = WikipediaClient.fetchWikitext(pageTitle: pageTitle, verbose: false)
            async let summaryTask  = WikipediaClient.fetchSummary(pageTitle: pageTitle, verbose: false)
            let (wt, summary) = try await (wikitextTask, summaryTask)
            wikitext = wt
            extract  = summary.extract
        } catch {
            if (error as? URLError) != nil {
                throw XCTSkip("Network unavailable — skipping LLM liveness test")
            }
            throw error
        }

        // Call the LLM
        let result: LLMAnalysis
        do {
            result = try await LLMClient.analyze(
                pageTitle: pageTitle,
                wikitext:  wikitext,
                extract:   extract,
                apiKey:    apiKey,
                verbose:   false
            )
        } catch {
            if let scraperError = error as? ScraperError {
                switch scraperError {
                case .httpError(let code, _) where code == 401:
                    throw XCTSkip("ANTHROPIC_API_KEY is invalid (401 Unauthorized) — skipping LLM test")
                case .httpError(let code, _) where code == 429:
                    throw XCTSkip("Rate limited by Anthropic API (429) — skipping LLM test")
                default: break
                }
            }
            if (error as? URLError) != nil {
                throw XCTSkip("Network unavailable — skipping LLM liveness test")
            }
            throw error
        }

        // Assert the result has at least some data
        let hasAnyData = !result.alternateNames.isEmpty
            || !result.additionalFacts.isEmpty
            || !result.additionalTitles.isEmpty
            || !result.influentialPeople.isEmpty
            || !result.additionalEvents.isEmpty

        XCTAssertTrue(hasAnyData,
                      "LLM analysis for Albert Einstein should return at least one piece of data " +
                      "(alternateNames, additionalFacts, additionalTitles, influentialPeople, or additionalEvents). " +
                      "All were empty, which suggests the LLM returned no data.")
    }
}
