#if os(iOS)
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WikipediaScraperCore
import WikipediaScraperSharedUI

// MARK: - FileDocument types

struct GEDCOMDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var content: String

    init(content: String = "") { self.content = content }

    init(configuration: ReadConfiguration) throws {
        content = String(
            data: configuration.file.regularFileContents ?? Data(),
            encoding: .utf8
        ) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(content.utf8))
    }
}

struct ZIPDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - ViewModel

@MainActor
final class iPadPersonViewModel: ObservableObject {
    @Published var urlString: String = "" {
        didSet { UserDefaults.standard.set(urlString, forKey: "last_url_string") }
    }
    @Published var persons: [EditablePerson] = []
    @Published var selectedPersonID: UUID? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var statusMessage: String? = nil

    // Export state
    @Published var gedDocument  = GEDCOMDocument()
    @Published var zipDocument  = ZIPDocument()
    @Published var isExportingGED: Bool = false
    @Published var isExportingZip: Bool = false

    // Per-session fetch options — persisted across launches
    @Published var useNotes: Bool = false {
        didSet { UserDefaults.standard.set(useNotes, forKey: "fetch_use_notes") }
    }
    @Published var useAllImages: Bool = false {
        didSet { UserDefaults.standard.set(useAllImages, forKey: "fetch_use_all_images") }
    }
    @Published var noPeople: Bool = false {
        didSet {
            rebuildStubs()
            UserDefaults.standard.set(noPeople, forKey: "fetch_no_people")
        }
    }

    init() {
        urlString    = UserDefaults.standard.string(forKey: "last_url_string") ?? ""
        useNotes     = UserDefaults.standard.bool(forKey: "fetch_use_notes")
        useAllImages = UserDefaults.standard.bool(forKey: "fetch_use_all_images")
        noPeople     = UserDefaults.standard.bool(forKey: "fetch_no_people")
    }

    var hasData: Bool { persons.contains { !$0.isStub } }

    // MARK: - Person access

    func selectedPersonBinding() -> Binding<EditablePerson>? {
        guard let id = selectedPersonID,
              persons.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.persons.first(where: { $0.id == id }) ?? EditablePerson() },
            set: { newValue in
                if let idx = self.persons.firstIndex(where: { $0.id == id }) {
                    self.persons[idx] = newValue
                }
            }
        )
    }

    // MARK: - Sources

    var sources: [SourceInfo] {
        var result: [SourceInfo] = []
        let full = persons.filter { !$0.isStub }

        let wikiPersons = full.filter { !$0.wikiURL.isEmpty || !$0.wikiTitle.isEmpty }
        if !wikiPersons.isEmpty {
            result.append(SourceInfo(
                id: SourceInfo.wikipediaID,
                type: .wikipedia,
                name: "Wikipedia",
                icon: "globe",
                description: "Information extracted from Wikipedia infoboxes and article summaries.",
                citedByNames: wikiPersons.map(\.wikiTitle).filter { !$0.isEmpty }
            ))
        }

        let llmPersons = full.filter {
            !$0.llmAlternateNames.isEmpty || !$0.llmTitles.isEmpty
            || !$0.llmFacts.isEmpty || !$0.llmEvents.isEmpty
            || !$0.influentialPeople.isEmpty
        }
        if !llmPersons.isEmpty {
            result.append(SourceInfo(
                id: SourceInfo.claudeAIID,
                type: .claudeAI,
                name: "Claude AI (Anthropic)",
                icon: "wand.and.stars",
                description: "Additional information extracted by Claude AI from Wikipedia article text. Data should be independently verified.",
                citedByNames: llmPersons.map(\.wikiTitle).filter { !$0.isEmpty }
            ))
        }

        return result
    }

    // MARK: - Stub extraction

    private func rebuildStubs() {
        guard !noPeople else {
            persons.removeAll { $0.isStub }
            return
        }
        let full = persons.filter { !$0.isStub }

        var seen = Set(full.flatMap { p -> [String] in
            var keys: [String] = []
            if !p.wikiTitle.isEmpty { keys.append(p.wikiTitle.lowercased()) }
            let name = (p.givenName + " " + p.surname).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { keys.append(name.lowercased()) }
            return keys
        })

        var stubs: [EditablePerson] = []

        func addStub(name: String, wikiTitle: String = "") {
            let key = wikiTitle.isEmpty ? name.lowercased() : wikiTitle.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            var stub = EditablePerson()
            stub.isStub = true
            stub.wikiTitle = wikiTitle
            let parts = name.components(separatedBy: " ").filter { !$0.isEmpty }
            if parts.count > 1 {
                stub.givenName = parts.dropLast().joined(separator: " ")
                stub.surname   = parts.last!
            } else {
                stub.givenName = name
            }
            stubs.append(stub)
        }

        for p in full {
            for s in p.spouses      where !s.name.isEmpty { addStub(name: s.name) }
            for c in p.children     where !c.name.isEmpty { addStub(name: c.name) }
            if !p.father.isEmpty { addStub(name: p.father) }
            if !p.mother.isEmpty { addStub(name: p.mother) }
            for pos in p.titledPositions {
                if !pos.predecessor.isEmpty { addStub(name: pos.predecessor) }
                if !pos.successor.isEmpty   { addStub(name: pos.successor) }
            }
            for ip in p.influentialPeople {
                addStub(name: ip.name, wikiTitle: ip.wikiTitle ?? "")
            }
        }

        persons = full + stubs
    }

    func removePerson(id: UUID) {
        persons.removeAll { $0.id == id }
        if selectedPersonID == id { selectedPersonID = persons.first(where: { !$0.isStub })?.id }
        rebuildStubs()
    }

    // MARK: - URL parsing

    private func parseURLs(_ input: String) -> [String] {
        return input.components(separatedBy: CharacterSet.whitespaces.union(.newlines))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",")) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Fetch

    func fetch() async {
        let urls = parseURLs(urlString)
        guard !urls.isEmpty else { return }

        errorMessage = nil
        statusMessage = nil
        isLoading = true
        defer { isLoading = false }

        for (index, fetchURL) in urls.enumerated() {
            if urls.count > 1 {
                statusMessage = "Fetching \(index + 1) of \(urls.count)…"
            }
            do {
                try await fetchOne(fetchURL, index: index, total: urls.count)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        statusMessage = nil
        rebuildStubs()
    }

    private func fetchOne(_ fetchURL: String, index: Int, total: Int) async throws {
        let multi = total > 1
        let pageTitle = try WikipediaClient.pageTitle(from: fetchURL)

        async let summaryResult   = WikipediaClient.fetchSummary(pageTitle: pageTitle, verbose: false)
        async let wikitextResult  = WikipediaClient.fetchWikitext(pageTitle: pageTitle, verbose: false)
        let (summary, wikitext)   = try await (summaryResult, wikitextResult)

        let (parsedPerson, _) = InfoboxParser.parse(
            wikitext:   wikitext,
            pageTitle:  pageTitle,
            verbose:    false
        )

        var editable = EditablePerson(from: parsedPerson)
        editable.wikiTitle = summary.title
        if editable.wikiURL.isEmpty      { editable.wikiURL = fetchURL }
        if let extract = summary.extract, editable.wikiExtract.isEmpty {
            editable.wikiExtract = extract
        }
        editable.imageURL = summary.originalimage?.source
            ?? summary.thumbnail?.source
            ?? editable.imageURL

        // ── Notes ─────────────────────────────────────────────────────────
        if useNotes {
            statusMessage = multi ? "Fetching sections (\(index + 1)/\(total))…" : "Fetching article sections…"
            do {
                editable.wikiSections = try await WikipediaClient.fetchSections(
                    pageTitle: pageTitle, verbose: false)
            } catch { /* non-fatal */ }
        }

        // ── All images ─────────────────────────────────────────────────────
        if useAllImages {
            statusMessage = multi ? "Fetching images (\(index + 1)/\(total))…" : "Fetching image list…"
            do {
                let primaryURL = editable.imageURL.isEmpty ? nil : editable.imageURL
                let infos = try await WikipediaClient.fetchAllImageURLs(
                    pageTitle:    pageTitle,
                    excludingURL: primaryURL,
                    verbose:      false)
                editable.additionalMedia = infos.map { info in
                    var item = EditableMediaItem()
                    item.url     = info.url
                    item.caption = info.title
                        .replacingOccurrences(of: "File:", with: "")
                        .replacingOccurrences(of: "_", with: " ")
                    return item
                }
            } catch { /* non-fatal */ }
        }

        // ── LLM enrichment ─────────────────────────────────────────────────
        let llm = LLMSettings.shared
        if llm.isEnabled {
            let key = llm.apiKey.isEmpty
                ? (ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? "")
                : llm.apiKey
            if key.isEmpty {
                errorMessage = "AI Analysis requires an Anthropic API key. Set it in Settings."
            } else {
                statusMessage = multi ? "Running AI analysis (\(index + 1)/\(total))…" : "Running AI analysis…"
                do {
                    let analysis = try await LLMClient.analyze(
                        pageTitle: pageTitle,
                        wikitext:  wikitext,
                        extract:   summary.extract,
                        apiKey:    key,
                        verbose:   false)
                    editable.llmAlternateNames = analysis.alternateNames
                    editable.llmTitles         = analysis.additionalTitles
                    editable.llmFacts          = analysis.additionalFacts
                    editable.llmEvents         = analysis.additionalEvents
                    editable.influentialPeople = analysis.influentialPeople
                } catch {
                    errorMessage = "AI analysis failed: \(error.localizedDescription)"
                }
            }
        }

        // Replace matching entry (including stubs) or append
        if let idx = persons.firstIndex(where: {
            !$0.wikiTitle.isEmpty && $0.wikiTitle == editable.wikiTitle
        }) {
            editable.id = persons[idx].id
            persons[idx] = editable
        } else {
            persons.append(editable)
        }
        selectedPersonID = editable.id
    }

    // MARK: - Export as GEDCOM

    func saveAsGED() {
        var personDatas = persons.filter { !$0.isStub }.map { $0.toPersonData() }
        if noPeople { personDatas = personDatas.map { var p = $0; stripFamilyRefs(&p); return p } }
        var builder    = GEDCOMBuilder()
        gedDocument    = GEDCOMDocument(content: builder.build(persons: personDatas, verbose: false))
        isExportingGED = true
    }

    // MARK: - Export as ZIP

    func saveAsZip() async {
        do {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(exportFilename + ".zip")
            try await buildAndWriteZip(to: tempURL)
            let rawData = try Data(contentsOf: tempURL)
            try? FileManager.default.removeItem(at: tempURL)
            zipDocument    = ZIPDocument(data: rawData)
            isExportingZip = true
        } catch {
            statusMessage = "Error building ZIP: \(error.localizedDescription)"
        }
    }

    private func buildAndWriteZip(to url: URL) async throws {
        let full = persons.filter { !$0.isStub }
        var mediaFiles: [(path: String, data: Data)] = []
        var personDatas = full.map { $0.toPersonData() }
        if noPeople { personDatas = personDatas.map { var p = $0; stripFamilyRefs(&p); return p } }

        for (i, person) in full.enumerated() {
            let prefix = safeBasename(person.wikiTitle, fallback: "person_\(i)")

            if !person.imageURL.isEmpty {
                do {
                    let (data, mime) = try await WikipediaClient.fetchImageData(
                        from: person.imageURL, verbose: false)
                    let relPath = "media/\(prefix).\(mimeExt(mime))"
                    personDatas[i].imageFilePath = relPath
                    mediaFiles.append((path: relPath, data: data))
                } catch {
                    statusMessage = "Warning: could not fetch image for \(person.wikiTitle)"
                }
            }

            for (j, item) in person.additionalMedia.enumerated() {
                guard !item.url.isEmpty else { continue }
                do {
                    let (data, mime) = try await WikipediaClient.fetchImageData(
                        from: item.url, verbose: false)
                    let relPath = "media/\(prefix)_\(j + 1).\(mimeExt(mime))"
                    personDatas[i].additionalMedia[j].filePath = relPath
                    mediaFiles.append((path: relPath, data: data))
                } catch { /* non-fatal */ }
            }
        }

        var builder = GEDCOMBuilder()
        let gedcom  = builder.build(persons: personDatas, verbose: false)
        try GEDZIPBuilder.create(gedcom: gedcom, mediaFiles: mediaFiles, at: url)
    }

    // MARK: - Export result handler

    func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url): statusMessage = "Saved \(url.lastPathComponent)"
        case .failure(let err): statusMessage = "Export failed: \(err.localizedDescription)"
        }
    }

    // MARK: - Helpers

    var exportFilename: String {
        if let first = persons.first(where: { !$0.isStub }), !first.wikiTitle.isEmpty {
            return first.wikiTitle
                .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
                .joined(separator: "_")
        }
        return "export"
    }

    private func stripFamilyRefs(_ p: inout PersonData) {
        p.spouses            = []
        p.children           = []
        p.parents            = []
        p.father             = nil
        p.mother             = nil
        p.influentialPeople  = []
        for i in p.titledPositions.indices {
            p.titledPositions[i].predecessor          = nil
            p.titledPositions[i].predecessorWikiTitle = nil
            p.titledPositions[i].successor            = nil
            p.titledPositions[i].successorWikiTitle   = nil
        }
    }

    private func mimeExt(_ mime: String) -> String {
        let m = mime.lowercased()
        if m.contains("png")  { return "png"  }
        if m.contains("webp") { return "webp" }
        if m.contains("gif")  { return "gif"  }
        return "jpg"
    }

    private func safeBasename(_ name: String, fallback: String) -> String {
        let s = name
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return s.isEmpty ? fallback : s
    }
}
#endif
