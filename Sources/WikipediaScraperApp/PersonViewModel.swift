import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WikipediaScraperCore
import WikipediaScraperSharedUI

@MainActor
final class PersonViewModel: ObservableObject {
    @Published var urls: [String] = [] {
        didSet { UserDefaults.standard.set(urls, forKey: "url_list") }
    }
    @Published var persons: [EditablePerson] = []
    @Published var selectedPersonID: UUID? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var statusMessage: String? = nil
    @Published var mediaWarnings: [String] = []
    @Published var aiProgressEntries: [AIProgressEntry] = []
    @Published var showingAIProgress: Bool = false
    @Published var isAnalyzing: Bool = false
    @Published var gedcomPreviewText: String? = nil
    @Published var showingGEDCOMPreview: Bool = false

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
        urls         = UserDefaults.standard.stringArray(forKey: "url_list") ?? []
        useNotes     = UserDefaults.standard.bool(forKey: "fetch_use_notes")
        useAllImages = UserDefaults.standard.bool(forKey: "fetch_use_all_images")
        noPeople     = UserDefaults.standard.bool(forKey: "fetch_no_people")
    }

    func handleOpenURL(_ url: URL) {
        guard url.scheme == "wikipedia-gedcom",
              url.host == "add",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let urlParam = components.queryItems?.first(where: { $0.name == "url" })?.value,
              !urlParam.isEmpty else { return }
        addURL(urlParam)
    }

    func addURL(_ urlString: String) {
        guard !urls.contains(urlString) else { return }
        urls.append(urlString)
        guard !isLoading else { return }
        Task { await fetchSingleURL(urlString) }
    }

    func removeURL(_ urlString: String) {
        urls.removeAll { $0 == urlString }
        persons = []
        errorMessage = nil
        statusMessage = nil
        guard !urls.isEmpty, !isLoading else { return }
        Task { await fetch() }
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
                addStub(name: ip.name, wikiTitle: ip.wikiTitle)
            }
        }

        persons = full + stubs
    }

    // MARK: - Remove person

    func removePerson(id: UUID) {
        persons.removeAll { $0.id == id }
        if selectedPersonID == id { selectedPersonID = persons.first(where: { !$0.isStub })?.id }
        rebuildStubs()
    }

    // MARK: - Fetch

    func fetchOnLaunch() async {
        guard !urls.isEmpty, persons.isEmpty else { return }
        await fetch()
    }

    func fetch() async {
        guard !urls.isEmpty else { return }

        errorMessage = nil
        statusMessage = nil
        aiProgressEntries = []
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

        async let summaryResult  = WikipediaClient.fetchSummary(pageTitle: pageTitle, verbose: false)
        async let wikitextResult = WikipediaClient.fetchWikitext(pageTitle: pageTitle, verbose: false)
        let (summary, wikitext)  = try await (summaryResult, wikitextResult)

        let (parsedPerson, _) = InfoboxParser.parse(
            wikitext:  wikitext,
            pageTitle: pageTitle,
            verbose:   false
        )

        var editable = EditablePerson(from: parsedPerson)
        editable.wikiTitle = summary.title
        if editable.wikiURL.isEmpty { editable.wikiURL = fetchURL }
        if let extract = summary.extract, editable.wikiExtract.isEmpty {
            editable.wikiExtract = extract
        }
        // Prefer the summary's direct upload.wikimedia.org URL over the
        // Special:FilePath redirect produced by the infobox parser.
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

    private func fetchSingleURL(_ urlString: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await fetchOne(urlString, index: 0, total: 1)
        } catch is CancellationError {
            // Task was cancelled (e.g. scene lifecycle); nothing to show.
        } catch {
            errorMessage = error.localizedDescription
        }
        statusMessage = nil
        rebuildStubs()
    }

    // MARK: - AI Analysis

    func analyzeWithLLM() async {
        guard hasData else { return }
        let llm = LLMSettings.shared
        let key = llm.apiKey.isEmpty
            ? (ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? "")
            : llm.apiKey
        guard !key.isEmpty else {
            errorMessage = "AI Analysis requires an Anthropic API key. Configure it in Settings (⌘,)."
            return
        }
        errorMessage = nil
        aiProgressEntries = []
        isAnalyzing = true
        showingAIProgress = true
        defer { isAnalyzing = false }

        let targets = persons.filter { !$0.isStub && !$0.wikiTitle.isEmpty }
        for (index, person) in targets.enumerated() {
            if targets.count > 1 {
                statusMessage = "Analysing \(index + 1) of \(targets.count)…"
            }
            let entryIdx = aiProgressEntries.count
            aiProgressEntries.append(AIProgressEntry(title: person.wikiTitle))
            do {
                let wikitext = try await WikipediaClient.fetchWikitext(pageTitle: person.wikiTitle, verbose: false)
                let extract  = person.wikiExtract.isEmpty ? nil : person.wikiExtract
                let analysis = try await LLMClient.analyze(
                    pageTitle:  person.wikiTitle,
                    wikitext:   wikitext,
                    extract:    extract,
                    apiKey:     key,
                    verbose:    false,
                    onProgress: { [weak self] message in
                        guard let self else { return }
                        self.aiProgressEntries[entryIdx].steps.append(message)
                    })
                if let idx = persons.firstIndex(where: { $0.id == person.id }) {
                    persons[idx].llmAlternateNames = analysis.alternateNames
                    persons[idx].llmTitles         = analysis.additionalTitles
                    persons[idx].llmFacts          = analysis.additionalFacts.map { EditablePersonFact(from: $0) }
                    persons[idx].llmEvents         = analysis.additionalEvents.map { EditableCustomEvent(from: $0) }
                    persons[idx].influentialPeople = analysis.influentialPeople.map { EditableInfluentialPerson(from: $0) }
                }
                aiProgressEntries[entryIdx].isDone = true
            } catch {
                aiProgressEntries[entryIdx].steps.append("Error: \(error.localizedDescription)")
                aiProgressEntries[entryIdx].failed = true
                errorMessage = "AI analysis failed for \(person.wikiTitle): \(error.localizedDescription)"
            }
        }
        statusMessage = nil
    }

    // MARK: - Export as GEDCOM

    func saveAsGED() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ged") ?? .data]
        panel.nameFieldStringValue = exportFilename
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true

        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    var personDatas = self.persons.filter { !$0.isStub }.map { $0.toPersonData() }
                    if self.noPeople { personDatas = personDatas.map { var p = $0; self.stripFamilyRefs(&p); return p } }
                    var builder = GEDCOMBuilder()
                    let gedcom  = builder.build(persons: personDatas, verbose: false)
                    try gedcom.write(to: url, atomically: true, encoding: .utf8)
                    self.statusMessage = "Saved \(url.lastPathComponent)"
                    // Show the generated GEDCOM in the viewer
                    self.gedcomPreviewText   = gedcom
                    self.showingGEDCOMPreview = true
                } catch {
                    self.statusMessage = "Error saving: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Preview GEDCOM

    func previewGEDCOM() {
        var personDatas = persons.filter { !$0.isStub }.map { $0.toPersonData() }
        if noPeople { personDatas = personDatas.map { var p = $0; stripFamilyRefs(&p); return p } }
        var builder = GEDCOMBuilder()
        gedcomPreviewText  = builder.build(persons: personDatas, verbose: false)
        showingGEDCOMPreview = true
    }

    // MARK: - Export as ZIP

    func saveAsZip() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.zip]
        panel.nameFieldStringValue = exportFilename
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true

        let response = await withCheckedContinuation { continuation in
            panel.begin { response in continuation.resume(returning: response) }
        }
        guard response == .OK, let url = panel.url else { return }

        do {
            try await buildAndWriteZip(to: url)
            statusMessage = "Saved \(url.lastPathComponent)"
        } catch {
            statusMessage = "Error saving ZIP: \(error.localizedDescription)"
        }
    }

    // MARK: - Open in MacFamilyTree

    func openInMacFamilyTree() async {
        let appPath = "/Applications/MacFamilyTree 11.app"
        guard FileManager.default.fileExists(atPath: appPath) else {
            statusMessage = "MacFamilyTree 11 is not installed in /Applications."
            return
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(exportFilename + ".zip")
        do {
            try await buildAndWriteZip(to: tempURL)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", appPath, tempURL.path]
            try process.run()
        } catch {
            statusMessage = "Could not open in MacFamilyTree: \(error.localizedDescription)"
        }
    }

    // MARK: - ZIP helper

    private func buildAndWriteZip(to url: URL) async throws {
        let full = persons.filter { !$0.isStub }
        var mediaFiles: [(path: String, data: Data)] = []
        var personDatas = full.map { $0.toPersonData() }
        if noPeople { personDatas = personDatas.map { var p = $0; stripFamilyRefs(&p); return p } }
        var zipWarnings: [String] = []

        for (i, person) in full.enumerated() {
            let prefix = safeBasename(person.wikiTitle, fallback: "person_\(i)")

            // Primary image
            if !person.imageURL.isEmpty {
                do {
                    let (data, mime) = try await WikipediaClient.fetchImageData(
                        from: person.imageURL, verbose: false)
                    let relPath = "media/\(prefix).\(mimeExt(mime))"
                    personDatas[i].imageFilePath = relPath
                    mediaFiles.append((path: relPath, data: data))
                } catch {
                    zipWarnings.append("Portrait of \(person.wikiTitle): \(error.localizedDescription)")
                }
            }

            // Additional media
            for (j, item) in person.additionalMedia.enumerated() {
                guard !item.url.isEmpty else { continue }
                do {
                    let (data, mime) = try await WikipediaClient.fetchImageData(
                        from: item.url, verbose: false)
                    let relPath = "media/\(prefix)_\(j + 1).\(mimeExt(mime))"
                    personDatas[i].additionalMedia[j].filePath = relPath
                    mediaFiles.append((path: relPath, data: data))
                } catch {
                    let name = item.caption.isEmpty ? item.url : item.caption
                    zipWarnings.append("\(name): \(error.localizedDescription)")
                }
            }
        }

        if !zipWarnings.isEmpty {
            mediaWarnings += zipWarnings
        }

        var builder = GEDCOMBuilder()
        let gedcom  = builder.build(persons: personDatas, verbose: false)
        try GEDZIPBuilder.create(gedcom: gedcom, mediaFiles: mediaFiles, at: url)
    }

    // MARK: - Helpers

    var gedcomFilename: String { exportFilename + ".ged" }

    private var exportFilename: String {
        if let first = persons.first(where: { !$0.isStub }), !first.wikiTitle.isEmpty {
            return sanitizeFilename(first.wikiTitle)
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

    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }
}
