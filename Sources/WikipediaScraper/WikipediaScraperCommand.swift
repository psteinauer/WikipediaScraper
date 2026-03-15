// WikipediaScraperCommand.swift — Wikipedia → GEDCOM 7 converter (entry point)

import ArgumentParser
import Foundation
import WikipediaScraperCore

@main
struct WikipediaScraper: AsyncParsableCommand {

    static var configuration = CommandConfiguration(
        commandName: "WikipediaScraper",
        abstract: "Convert one or more Wikipedia person pages to a GEDCOM 7.0 genealogy file.",
        discussion: """
        Fetches the Quick Facts / infobox section of each Wikipedia article and
        produces a standards-compliant GEDCOM 7.0 file importable into Mac Family
        Tree 11 and other genealogy applications.

        OUTPUT MODES (mutually exclusive)
          Default      Writes <ArticleTitle>.ged to the current directory.
                       Multiple URLs: writes <First>_et_al.ged.
          --preflight  Writes GEDCOM to standard output for inspection.
          --zip        Writes a GEDZIP archive (.zip by default; use --output
                       to specify .gdz or any other extension) containing the
                       .ged file and any referenced media (portrait images).
          --mappings   Prints a field-mapping table per URL; no GEDCOM is produced.

        EXTRA CONTENT FLAGS
          --notes      Appends each Wikipedia article section as a separate NOTE
                       record on the individual (can be combined with any mode).
          --allimages  Downloads every article image into the GEDZIP archive and
                       links each as an OBJE record. Implies --zip.
          --llm        Uses Claude AI to enrich the output with additional names,
                       titles, facts, events, and influential people (ASSO records).
                       Requires ANTHROPIC_API_KEY env var or --api-key.
          --summary    Prints a human-readable summary of all exported data
                       (names, dates, titles, family, facts) to standard output.

        GEDZIP STRUCTURE (.zip / .gdz)
          gedcom.ged          GEDCOM 7 file (FILE tags use relative paths)
          media/<title>.jpg   Portrait image downloaded from Wikimedia
          media/<file>.jpg    Additional images (--allimages)

        EXAMPLES
          WikipediaScraper https://en.wikipedia.org/wiki/George_Washington
          WikipediaScraper --output presidents/washington.ged \\
              https://en.wikipedia.org/wiki/George_Washington
          WikipediaScraper --zip https://en.wikipedia.org/wiki/Elizabeth_II
          WikipediaScraper --zip --output royals/elizabeth.gdz \\
              https://en.wikipedia.org/wiki/Elizabeth_II
          WikipediaScraper --preflight --notes https://en.wikipedia.org/wiki/Napoleon
          WikipediaScraper --allimages https://en.wikipedia.org/wiki/Queen_Victoria
          WikipediaScraper --mappings  https://en.wikipedia.org/wiki/Napoleon
          WikipediaScraper --verbose --zip https://en.wikipedia.org/wiki/Napoleon
          WikipediaScraper --zip \\
              https://en.wikipedia.org/wiki/Queen_Victoria \\
              https://en.wikipedia.org/wiki/Prince_Albert
        """,
        version: "1.5.0"
    )

    // MARK: - Arguments & options

    @Argument(help: "One or more full URLs of Wikipedia articles.")
    var wikipediaURLs: [String]

    @Option(name: .shortAndLong,
            help: "Override the output file path (default: <ArticleTitle>.ged or .gdz in CWD).")
    var output: String?

    @Flag(name: .shortAndLong,
          help: "Print progress information to stderr.")
    var verbose: Bool = false

    @Flag(name: [.customLong("preflight"), .customShort("p")],
          help: "Write GEDCOM to standard output instead of a file.")
    var preflight: Bool = false

    @Flag(name: [.customLong("zip"), .customShort("z")],
          help: """
          Create a GEDZIP archive (default extension .zip; use --output to \
          specify .gdz or another extension) containing the GEDCOM file and \
          any portrait images, per GEDCOM 7 §3.2 GEDZIP specification.
          """)
    var zip: Bool = false

    @Flag(name: [.customLong("mappings"), .customShort("m")],
          help: "Print a field-mapping table (Wikipedia infobox → GEDCOM 7 tags) and exit.")
    var mappings: Bool = false

    @Flag(name: [.customLong("notes"), .customShort("n")],
          help: "Append each Wikipedia article section as a NOTE record on the individual.")
    var notes: Bool = false

    @Flag(name: [.customLong("allimages"), .customShort("a")],
          help: "Download all article images into the GEDZIP archive (implies --zip).")
    var allimages: Bool = false

    @Option(name: .customLong("config"),
            help: "Path to a .wikipediascraperrc config file (default: search CWD then HOME).")
    var configPath: String?

    @Flag(name: .customLong("nopeople"),
          help: "Only create GEDCOM records for the URLs passed on the command line; do not fetch referenced people.")
    var noPeople: Bool = false

    @Flag(name: .customLong("llm"),
          help: "Use Claude AI to extract additional names, titles, facts, events, and influential people from the article.")
    var llm: Bool = false

    @Option(name: .customLong("api-key"),
            help: "Anthropic API key for --llm (defaults to ANTHROPIC_API_KEY environment variable).")
    var apiKey: String?

    @Flag(name: [.customLong("summary"), .customShort("s")],
          help: "Print a human-readable summary of the exported data after writing the output file.")
    var summary: Bool = false

    // MARK: - Validation

    func validate() throws {
        if wikipediaURLs.isEmpty {
            throw ValidationError("At least one Wikipedia URL is required.")
        }
        let modes = [preflight, zip, mappings].filter { $0 }.count
        if modes > 1 {
            throw ValidationError("--preflight, --zip, and --mappings are mutually exclusive.")
        }
        if preflight, output != nil {
            throw ValidationError("--preflight writes to stdout; --output has no effect with --preflight.")
        }
        if allimages, preflight {
            throw ValidationError("--allimages requires writing a zip file; cannot be used with --preflight.")
        }
        if allimages, mappings {
            throw ValidationError("--allimages cannot be combined with --mappings.")
        }
        if summary, preflight {
            throw ValidationError("--summary cannot be combined with --preflight (both write to stdout).")
        }
    }

    // MARK: - Run

    func run() async throws {

        // --allimages implies zip mode
        let effectiveZip = zip || allimages

        // Load .wikipediascraperrc (--config path, or CWD / HOME search)
        let config = ScraperConfig.load(path: configPath, verbose: verbose)

        var persons:    [PersonData]             = []
        var mediaFiles: [(path: String, data: Data)] = []
        var firstPageTitle: String?

        for (index, wikipediaURL) in wikipediaURLs.enumerated() {

            let urlLabel = wikipediaURLs.count > 1 ? "[\(index + 1)/\(wikipediaURLs.count)] " : ""

            // ── 1. Resolve page title ──────────────────────────────────────
            if verbose { fputs("\(urlLabel)Resolving page title…\n", stderr) }
            let pageTitle = try WikipediaClient.pageTitle(from: wikipediaURL)
            if verbose { fputs("\(urlLabel)Page title: \(pageTitle)\n", stderr) }
            if firstPageTitle == nil { firstPageTitle = pageTitle }

            // ── 2. Fetch REST summary ──────────────────────────────────────
            if verbose { fputs("\(urlLabel)Fetching article summary…\n", stderr) }
            let summary = try await WikipediaClient.fetchSummary(pageTitle: pageTitle, verbose: verbose)

            // ── 3. Fetch wikitext ──────────────────────────────────────────
            if verbose { fputs("\(urlLabel)Fetching wikitext…\n", stderr) }
            let wikitext = try await WikipediaClient.fetchWikitext(pageTitle: pageTitle, verbose: verbose)
            if verbose { fputs("\(urlLabel)Wikitext: \(wikitext.count) characters\n", stderr) }

            // ── 4. Parse infobox ───────────────────────────────────────────
            if verbose { fputs("\(urlLabel)Parsing infobox…\n", stderr) }
            var (person, rawFields) = InfoboxParser.parse(wikitext: wikitext,
                                                          pageTitle: pageTitle,
                                                          verbose: verbose,
                                                          config: config)
            person.wikiURL     = wikipediaURL
            person.wikiTitle   = summary.title   // use canonical title (handles redirects)
            person.wikiExtract = summary.extract

            // Best image URL from REST summary, fallback to infobox-derived URL
            let imageSourceURL = summary.originalimage?.source
                              ?? summary.thumbnail?.source
                              ?? person.imageURL
            person.imageURL = imageSourceURL

            // ── 4b. LLM enrichment (--llm) ────────────────────────────────
            if llm {
                let key = apiKey ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
                if key.isEmpty {
                    fputs("Warning: --llm requires an Anthropic API key (--api-key or ANTHROPIC_API_KEY env var)\n", stderr)
                } else {
                    if verbose { fputs("\(urlLabel)Running LLM analysis…\n", stderr) }
                    do {
                        let analysis = try await LLMClient.analyze(
                            pageTitle: pageTitle,
                            wikitext:  wikitext,
                            extract:   summary.extract,
                            apiKey:    key,
                            verbose:   verbose)

                        // Store LLM data in separate fields — GEDCOMBuilder will cite
                        // Claude as the source and add notes to distinguish from infobox data.
                        let existingNames = Set(person.alternateNames)
                        person.llmAlternateNames  = analysis.alternateNames.filter { !existingNames.contains($0) }
                        person.llmTitles          = analysis.additionalTitles
                        person.llmFacts           = analysis.additionalFacts
                        person.llmEvents          = analysis.additionalEvents
                        person.influentialPeople  = analysis.influentialPeople
                    } catch {
                        fputs("Warning: LLM analysis failed for \(pageTitle): \(error.localizedDescription)\n", stderr)
                    }
                }
            }

            // ── Mappings mode (per URL) ────────────────────────────────────
            if mappings {
                let report = MappingsReporter.report(person: person,
                                                     rawFields: rawFields,
                                                     wikiURL: wikipediaURL)
                print(report, terminator: "")
                continue   // process remaining URLs
            }

            // ── 4b. Wikipedia sections (--notes) ──────────────────────────
            if notes {
                if verbose { fputs("\(urlLabel)Fetching article sections for --notes…\n", stderr) }
                do {
                    person.wikiSections = try await WikipediaClient.fetchSections(
                        pageTitle: pageTitle, verbose: verbose)
                    if verbose { fputs("\(urlLabel)Sections: \(person.wikiSections.count) found\n", stderr) }
                } catch {
                    fputs("Warning: Could not fetch article sections for \(pageTitle): \(error.localizedDescription)\n", stderr)
                }
            }

            // ── 5. Image handling ──────────────────────────────────────────
            let safeTitle = sanitize(pageTitle)

            // Portrait (zip or allimages mode)
            if effectiveZip, let imgURL = imageSourceURL {
                if verbose { fputs("\(urlLabel)Downloading portrait image for GEDZIP…\n", stderr) }
                do {
                    let (data, mime) = try await WikipediaClient.fetchImageData(from: imgURL, verbose: verbose)
                    person.imageData     = data
                    person.imageMimeType = mime
                    let ext       = imageExtension(mime: mime, url: imgURL)
                    let mediaPath = "media/\(safeTitle).\(ext)"
                    person.imageFilePath = mediaPath
                    mediaFiles.append((mediaPath, data))
                    if verbose { fputs("\(urlLabel)Portrait: \(data.count) bytes → \(mediaPath)\n", stderr) }
                } catch {
                    fputs("Warning: Could not download portrait for \(pageTitle): \(error.localizedDescription)\n", stderr)
                }
            }

            // Additional images (--allimages)
            if allimages {
                if verbose { fputs("\(urlLabel)Fetching all article image URLs…\n", stderr) }
                do {
                    let allImgInfos = try await WikipediaClient.fetchAllImageURLs(
                        pageTitle:    pageTitle,
                        excludingURL: imageSourceURL,
                        verbose:      verbose)
                    if verbose { fputs("\(urlLabel)Found \(allImgInfos.count) additional images\n", stderr) }

                    for imgInfo in allImgInfos {
                        if verbose { fputs("  Downloading \(imgInfo.title)…\n", stderr) }
                        do {
                            let (data, actualMime) = try await WikipediaClient.fetchImageData(
                                from: imgInfo.url, verbose: false)
                            // Use the extension from the File: title, not from MIME
                            let fileTitle = imgInfo.title.replacingOccurrences(of: "File:", with: "")
                            let origExt   = (fileTitle as NSString).pathExtension.lowercased()
                            let ext       = origExt.isEmpty ? imageExtension(mime: actualMime, url: imgInfo.url) : origExt
                            let nameNoExt = (fileTitle as NSString).deletingPathExtension
                            let baseName  = sanitize(nameNoExt)
                            let mediaPath = "media/\(baseName).\(ext)"
                            let caption   = nameNoExt.replacingOccurrences(of: "_", with: " ")
                            person.additionalMedia.append(AdditionalMedia(
                                filePath: mediaPath,
                                origURL:  imgInfo.url,
                                title:    caption.isEmpty ? nil : caption,
                                mimeType: actualMime))
                            mediaFiles.append((mediaPath, data))
                            if verbose { fputs("    \(data.count) bytes → \(mediaPath)\n", stderr) }
                        } catch {
                            fputs("Warning: Could not download \(imgInfo.title): \(error.localizedDescription)\n", stderr)
                        }
                    }
                } catch {
                    fputs("Warning: Could not fetch image list for \(pageTitle): \(error.localizedDescription)\n", stderr)
                }
            }

            persons.append(person)

            if verbose { printSummary(person: person) }
        }

        // Mappings mode exits here (all reports already printed above)
        if mappings { return }

        // ── Fetch referenced people (1 level deep, no recursion) ──────────
        if !mappings && !noPeople {
            // Collect canonical wikiTitles of already-fetched persons
            var fetchedTitles = Set(persons.compactMap { $0.wikiTitle })

            // Collect all referenced wiki titles from infoboxes
            var toFetch = Set<String>()
            for person in persons {
                for sp  in person.spouses  { if let wt = sp.wikiTitle  { toFetch.insert(wt) } }
                for ch  in person.children { if let wt = ch.wikiTitle  { toFetch.insert(wt) } }
                if let wt = person.father?.wikiTitle { toFetch.insert(wt) }
                if let wt = person.mother?.wikiTitle { toFetch.insert(wt) }
                for pr in person.parents   { if let wt = pr.wikiTitle  { toFetch.insert(wt) } }
                for pos in person.titledPositions {
                    if let wt = pos.predecessorWikiTitle { toFetch.insert(wt) }
                    if let wt = pos.successorWikiTitle   { toFetch.insert(wt) }
                }
                for ip in person.influentialPeople {
                    if let wt = ip.wikiTitle { toFetch.insert(wt) }
                }
            }
            toFetch.subtract(fetchedTitles)

            if !toFetch.isEmpty && verbose {
                fputs("Fetching \(toFetch.count) referenced person(s)…\n", stderr)
            }

            for wikiTitle in toFetch.sorted() {
                if verbose { fputs("  [ref] \(wikiTitle)\n", stderr) }
                do {
                    let summary  = try await WikipediaClient.fetchSummary(pageTitle: wikiTitle, verbose: verbose)
                    let wikitext = try await WikipediaClient.fetchWikitext(pageTitle: wikiTitle, verbose: verbose)

                    var (refPerson, _) = InfoboxParser.parse(wikitext: wikitext, pageTitle: wikiTitle, verbose: false,
                                                             config: config)
                    refPerson.wikiTitle   = summary.title   // canonical
                    let encodedTitle = wikiTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? wikiTitle
                    refPerson.wikiURL     = "https://en.wikipedia.org/wiki/\(encodedTitle.replacingOccurrences(of: " ", with: "_"))"
                    refPerson.wikiExtract = summary.extract
                    let refImageSourceURL = summary.originalimage?.source ?? summary.thumbnail?.source ?? refPerson.imageURL
                    refPerson.imageURL = refImageSourceURL

                    // Download portrait in zip mode
                    if effectiveZip, let imgURL = refImageSourceURL {
                        do {
                            let (data, mime) = try await WikipediaClient.fetchImageData(from: imgURL, verbose: false)
                            refPerson.imageData     = data
                            refPerson.imageMimeType = mime
                            let ext       = imageExtension(mime: mime, url: imgURL)
                            let safeT     = sanitize(summary.title)
                            let mediaPath = "media/\(safeT).\(ext)"
                            refPerson.imageFilePath = mediaPath
                            mediaFiles.append((mediaPath, data))
                        } catch {
                            // Portrait is optional
                        }
                    }

                    persons.append(refPerson)
                    fetchedTitles.insert(summary.title)
                } catch {
                    fputs("Warning: Could not fetch referenced person '\(wikiTitle)': \(error.localizedDescription)\n", stderr)
                }
            }
        }

        guard !persons.isEmpty else { return }

        // ── When --nopeople, strip all refs to people not on the command line ─
        // Only the explicitly-passed persons appear in the GEDCOM.  Family links
        // that point to another command-line person are kept; everything else is
        // removed so the builder does not generate stub INDI records.
        if noPeople {
            let knownTitles = Set(persons.compactMap { $0.wikiTitle })
            let isKnown: (String?) -> Bool = { knownTitles.contains($0 ?? "") }

            for i in persons.indices {
                persons[i].spouses  = persons[i].spouses.filter  { isKnown($0.wikiTitle) }
                persons[i].children = persons[i].children.filter { isKnown($0.wikiTitle) }
                persons[i].parents  = persons[i].parents.filter  { isKnown($0.wikiTitle) }
                if !isKnown(persons[i].father?.wikiTitle) { persons[i].father = nil }
                if !isKnown(persons[i].mother?.wikiTitle) { persons[i].mother = nil }

                // Clear pred/succ names and wiki titles for non-command-line people
                // so BuildContext does not allocate stub INDI IDs for them.
                // The EVEN NOTE text that mentions "Preceded by: …" is cleared too,
                // since those people won't exist in the file.
                for j in persons[i].titledPositions.indices {
                    if !isKnown(persons[i].titledPositions[j].predecessorWikiTitle) {
                        persons[i].titledPositions[j].predecessor          = nil
                        persons[i].titledPositions[j].predecessorWikiTitle = nil
                    }
                    if !isKnown(persons[i].titledPositions[j].successorWikiTitle) {
                        persons[i].titledPositions[j].successor            = nil
                        persons[i].titledPositions[j].successorWikiTitle   = nil
                    }
                }

                // Remove all influential-people references — they generate ASSO
                // records pointing to other individuals who won't be in the file.
                persons[i].influentialPeople = []
            }
        }

        // ── 6. Build GEDCOM ───────────────────────────────────────────────
        if verbose { fputs("Building GEDCOM 7.0…\n", stderr) }
        var builder = GEDCOMBuilder()
        let gedcom  = builder.build(persons: persons, verbose: verbose)

        if verbose {
            fputs("GEDCOM: \(gedcom.components(separatedBy: "\r\n").count) lines\n", stderr)
        }

        // ── 7. Output ─────────────────────────────────────────────────────
        let safeFirst = sanitize(firstPageTitle ?? "output")
        let defaultName = persons.count > 1 ? "\(safeFirst)_et_al" : safeFirst

        if preflight {
            // ── Preflight: stdout ────────────────────────────────────────
            print(gedcom, terminator: "")

        } else if effectiveZip {
            // ── ZIP: default extension is .zip unless --output says otherwise ──
            let destURL = resolveOutputURL(override: output,
                                           defaultName: defaultName,
                                           ext: "zip")
            if verbose { fputs("Creating GEDZIP: \(destURL.path)\n", stderr) }
            try GEDZIPBuilder.create(gedcom: gedcom,
                                     mediaFiles: mediaFiles,
                                     at: destURL)
            fputs("Written to \(destURL.path)\n", stderr)
            if verbose {
                fputs("GEDZIP contains: gedcom.ged", stderr)
                for m in mediaFiles { fputs(" + \(m.path)", stderr) }
                fputs("\n", stderr)
            }

        } else {
            // ── Default: .ged file ────────────────────────────────────────
            let destURL = resolveOutputURL(override: output,
                                           defaultName: defaultName,
                                           ext: "ged")
            guard let data = gedcom.data(using: .utf8) else {
                throw ScraperError.parseError("Failed to encode GEDCOM as UTF-8")
            }
            try data.write(to: destURL, options: .atomic)
            fputs("Written to \(destURL.path)\n", stderr)
        }

        // ── 8. Summary (--summary) ────────────────────────────────────────
        if summary {
            // Only summarise the primary persons (not stubs fetched as refs)
            let primaryCount = wikipediaURLs.count
            let primaryPersons = Array(persons.prefix(primaryCount))
            print(buildSummary(persons: primaryPersons))
        }
    }

    // MARK: - Helpers

    /// Build the output URL: use `override` path if given, otherwise
    /// `<defaultName>.<ext>` in the current working directory.
    private func resolveOutputURL(override: String?, defaultName: String, ext: String) -> URL {
        if let path = override {
            return URL(fileURLWithPath: path)
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return cwd.appendingPathComponent(defaultName).appendingPathExtension(ext)
    }

    /// Replace characters that are unsafe in filenames with underscores.
    private func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: #"[/\\:*?"<>|]"#, with: "_", options: .regularExpression)
         .replacingOccurrences(of: " ", with: "_")
    }

    /// Derive a short image file extension from MIME type or URL.
    private func imageExtension(mime: String?, url: String) -> String {
        switch (mime ?? "").lowercased() {
        case "image/png":  return "png"
        case "image/gif":  return "gif"
        case "image/webp": return "webp"
        default:
            if url.lowercased().hasSuffix(".png") { return "png" }
            return "jpg"
        }
    }

    // MARK: - Export summary (--summary)

    private func buildSummary(persons: [PersonData]) -> String {
        var out = ""
        let bar = String(repeating: "─", count: 60)

        for (idx, p) in persons.enumerated() {
            if idx > 0 { out += "\n" }
            out += "\(bar)\n"

            // ── Name ──────────────────────────────────────────────────────
            let displayName = p.wikiTitle ?? p.name ?? "(unknown)"
            out += "  \(displayName)\n"

            if !p.alternateNames.isEmpty {
                out += "  Also known as: \(p.alternateNames.joined(separator: " · "))\n"
            }
            if let bn = p.birthName {
                out += "  Birth name: \(bn)\n"
            }

            // ── Sex ───────────────────────────────────────────────────────
            switch p.sex {
            case .male:    out += "  Sex: Male\n"
            case .female:  out += "  Sex: Female\n"
            case .unknown: break
            }

            // ── Life events ───────────────────────────────────────────────
            out += "\n"
            if let b = p.birth {
                let date  = b.date.flatMap { $0.isEmpty ? nil : $0.gedcom } ?? "—"
                let place = b.place ?? ""
                out += "  Born:    \(date)\(place.isEmpty ? "" : "  \(place)")\n"
            }
            if let bp = p.baptism {
                let date  = bp.date.flatMap { $0.isEmpty ? nil : $0.gedcom } ?? "—"
                let place = bp.place ?? ""
                out += "  Baptism: \(date)\(place.isEmpty ? "" : "  \(place)")\n"
            }
            for sp in p.spouses {
                var line = "  Married: \(sp.name)"
                if let md = sp.marriageDate, !md.isEmpty { line += "  (\(md.gedcom))" }
                if let mp = sp.marriagePlace { line += "  \(mp)" }
                out += line + "\n"
            }
            if let d = p.death {
                let date  = d.date.flatMap { $0.isEmpty ? nil : $0.gedcom } ?? "—"
                let place = d.place ?? ""
                var line  = "  Died:    \(date)\(place.isEmpty ? "" : "  \(place)")"
                if let c = d.cause { line += "  (\(c))" }
                out += line + "\n"
            }
            if let bu = p.burial {
                let place = bu.place ?? ""
                let date  = bu.date.flatMap { $0.isEmpty ? nil : $0.gedcom }
                var line  = "  Buried:"
                if let d = date { line += "  \(d)" }
                if !place.isEmpty { line += "  \(place)" }
                out += line + "\n"
            }

            // ── Titles / positions ────────────────────────────────────────
            if !p.honorifics.isEmpty || !p.titledPositions.isEmpty {
                out += "\n"
                for h in p.honorifics { out += "  Title:    \(h)\n" }
                for pos in p.titledPositions {
                    var line = "  Title:    \(pos.title)"
                    let start = pos.startDate.flatMap { $0.isEmpty ? nil : $0.gedcom }
                    let end   = pos.endDate.flatMap   { $0.isEmpty ? nil : $0.gedcom }
                    if let s = start, let e = end { line += "  (\(s) – \(e))" }
                    else if let s = start          { line += "  (from \(s))" }
                    else if let e = end            { line += "  (to \(e))" }
                    out += line + "\n"
                }
            }

            // ── Family ────────────────────────────────────────────────────
            let fatherName = p.father?.name ?? p.parents.first?.name
            let motherName = p.mother?.name ?? (p.parents.count >= 2 ? p.parents[1].name : nil)
            if fatherName != nil || motherName != nil {
                out += "\n"
                if let f = fatherName { out += "  Father:  \(f)\n" }
                if let m = motherName { out += "  Mother:  \(m)\n" }
            }
            if !p.children.isEmpty {
                out += "  Children (\(p.children.count)): \(p.children.map(\.name).joined(separator: ", "))\n"
            }

            // ── Occupations ───────────────────────────────────────────────
            if !p.occupations.isEmpty {
                out += "\n"
                out += "  Occupations: \(p.occupations.joined(separator: ", "))\n"
            }

            // ── Custom events ─────────────────────────────────────────────
            if !p.customEvents.isEmpty {
                out += "\n"
                for evt in p.customEvents {
                    var line = "  Event:   \(evt.type)"
                    if let d = evt.date, !d.isEmpty { line += "  \(d.gedcom)" }
                    if let pl = evt.place { line += "  \(pl)" }
                    out += line + "\n"
                }
            }

            // ── Facts ─────────────────────────────────────────────────────
            if !p.personFacts.isEmpty {
                out += "\n"
                for f in p.personFacts {
                    out += "  \(f.type): \(f.value)\n"
                }
            }

            // ── Influential people (LLM) ──────────────────────────────────
            if !p.influentialPeople.isEmpty {
                out += "\n"
                out += "  Influential people:\n"
                for ip in p.influentialPeople {
                    var line = "    \(ip.relationship): \(ip.name)"
                    if let n = ip.note { line += " — \(n)" }
                    out += line + "\n"
                }
            }

            // ── Source ────────────────────────────────────────────────────
            if let url = p.wikiURL {
                out += "\n"
                out += "  Source: \(url)\n"
            }
        }
        out += "\(bar)\n"
        return out
    }

    // MARK: - Verbose progress summary

    private func printSummary(person: PersonData) {
        fputs("\n--- Person Summary ---\n", stderr)
        fputs("Name:       \(person.name ?? "(unknown)")\n", stderr)
        if let g = person.givenName { fputs("Given:      \(g)\n", stderr) }
        if let s = person.surname   { fputs("Surname:    \(s)\n", stderr) }
        fputs("Sex:        \(person.sex)\n", stderr)
        if let b = person.birth    { fputs("Birth:      \(b.date?.gedcom ?? "(no date)") \(b.place ?? "")\n", stderr) }
        if let d = person.death    { fputs("Death:      \(d.date?.gedcom ?? "(no date)") \(d.place ?? "")\n", stderr) }
        if let r = person.burial   { fputs("Burial:     \(r.place ?? "")\n", stderr) }
        if !person.honorifics.isEmpty { fputs("Titles:     \(person.honorifics.joined(separator: "; "))\n", stderr) }
        for pos in person.titledPositions {
            var dates = ""
            if let sd = pos.startDate, !sd.isEmpty { dates = " (from \(sd.gedcom))" }
            if let ed = pos.endDate,   !ed.isEmpty { dates += " to \(ed.gedcom)" }
            fputs("Position:   \(pos.title)\(dates)\n", stderr)
        }
        if !person.occupations.isEmpty {
            fputs("Occupation: \(person.occupations.joined(separator: ", "))\n", stderr)
        }
        if !person.spouses.isEmpty {
            fputs("Spouses:    \(person.spouses.map(\.name).joined(separator: ", "))\n", stderr)
        }
        if !person.children.isEmpty { fputs("Children:   \(person.children.count)\n", stderr) }
        if let f = person.father    { fputs("Father:     \(f.name)\n", stderr) }
        if let m = person.mother    { fputs("Mother:     \(m.name)\n", stderr) }
        if let url = person.imageURL { fputs("Image URL:  \(url)\n", stderr) }
        if let lp  = person.imageFilePath { fputs("Image path: \(lp) (in zip)\n", stderr) }
        fputs("----------------------\n", stderr)
    }
}

extension Sex: CustomStringConvertible {
    public var description: String {
        switch self {
        case .male:    return "Male"
        case .female:  return "Female"
        case .unknown: return "Unknown"
        }
    }
}
