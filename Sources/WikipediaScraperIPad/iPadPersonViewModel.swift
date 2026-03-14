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
    @Published var urlString: String = ""
    @Published var person: EditablePerson = EditablePerson()
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var hasData: Bool = false
    @Published var statusMessage: String? = nil

    // Export state — .fileExporter reads these
    @Published var gedDocument  = GEDCOMDocument()
    @Published var zipDocument  = ZIPDocument()
    @Published var isExportingGED: Bool = false
    @Published var isExportingZip: Bool = false

    var exportFilename: String {
        let name = person.wikiTitle.isEmpty ? "export" : person.wikiTitle
        return name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "_")
    }

    // MARK: - Fetch

    func fetch() async {
        errorMessage  = nil
        statusMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let pageTitle = try WikipediaClient.pageTitle(from: urlString)

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
            if editable.wikiURL.isEmpty      { editable.wikiURL = urlString }
            if let extract = summary.extract, editable.wikiExtract.isEmpty {
                editable.wikiExtract = extract
            }
            if let thumb = summary.originalimage?.source, editable.imageURL.isEmpty {
                editable.imageURL = thumb
            } else if let thumb = summary.thumbnail?.source, editable.imageURL.isEmpty {
                editable.imageURL = thumb
            }

            self.person  = editable
            self.hasData = true
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Export as GEDCOM

    func saveAsGED() {
        let personData = person.toPersonData()
        var builder    = GEDCOMBuilder()
        gedDocument    = GEDCOMDocument(content: builder.build(persons: [personData], verbose: false))
        isExportingGED = true
    }

    // MARK: - Export as ZIP

    func saveAsZip() async {
        do {
            var mediaFiles: [(path: String, data: Data)] = []
            var personData = person.toPersonData()

            // Primary image
            if !person.imageURL.isEmpty {
                do {
                    let (data, mime) = try await WikipediaClient.fetchImageData(
                        from: person.imageURL, verbose: false)
                    let relPath = "media/\(safeBasename(person.wikiTitle, fallback: "portrait")).\(mimeExt(mime))"
                    personData.imageFilePath = relPath
                    mediaFiles.append((path: relPath, data: data))
                } catch {
                    statusMessage = "Warning: could not fetch primary image"
                }
            }

            // Additional media
            var resolvedExtras: [AdditionalMedia] = []
            for (idx, item) in person.additionalMedia.enumerated() {
                guard !item.url.isEmpty else { continue }
                do {
                    let (data, mime) = try await WikipediaClient.fetchImageData(
                        from: item.url, verbose: false)
                    let base    = item.caption.isEmpty ? "media_\(idx + 1)" : item.caption
                    let relPath = "media/\(safeBasename(base, fallback: "media_\(idx + 1)")).\(mimeExt(mime))"
                    resolvedExtras.append(AdditionalMedia(
                        filePath: relPath, origURL: item.url,
                        title: item.caption.isEmpty ? nil : item.caption, mimeType: mime))
                    mediaFiles.append((path: relPath, data: data))
                } catch {
                    resolvedExtras.append(AdditionalMedia(
                        filePath: item.url, origURL: item.url,
                        title: item.caption.isEmpty ? nil : item.caption))
                }
            }
            personData.additionalMedia = resolvedExtras

            // Build GEDCOM + ZIP
            var builder = GEDCOMBuilder()
            let gedcom  = builder.build(persons: [personData], verbose: false)

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(exportFilename + ".zip")
            try GEDZIPBuilder.create(gedcom: gedcom, mediaFiles: mediaFiles, at: tempURL)
            let rawData = try Data(contentsOf: tempURL)
            try? FileManager.default.removeItem(at: tempURL)

            zipDocument  = ZIPDocument(data: rawData)
            isExportingZip = true
        } catch {
            statusMessage = "Error building ZIP: \(error.localizedDescription)"
        }
    }

    // MARK: - Export result handler

    func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            statusMessage = "Saved \(url.lastPathComponent)"
        case .failure(let error):
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

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
