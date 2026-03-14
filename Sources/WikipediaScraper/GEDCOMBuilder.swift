// GEDCOMBuilder.swift — Build GEDCOM 7.0 compatible with Mac Family Tree 11
//
// GEDCOM 7 compliance notes:
//   - All HUSB/WIFE/CHIL tags reference real INDI xrefs (no placeholders)
//   - Stub INDI records created for all referenced family members
//   - Multimedia uses FILE <url> (no base64 embedding)
//   - One OCCU tag per occupation value
//   - No CHAR tag (UTF-8 is mandatory and implicit in GEDCOM 7)
//   - SEX omitted when unknown (not all apps handle SEX U)
//   - CONT used for lines exceeding 255 characters
//   - SOUR.WWW for top-level source URL; SOUR citation PAGE for specific article URL
//   - ASSO + RELA for predecessor/successor (influential persons)

import Foundation

// MARK: - Assoc types

private struct AssocLink {
    var indiID: String
    var rela:   String   // "Predecessor" or "Successor"
    var note:   String?  // context, e.g. "as Queen of the United Kingdom"
}

private struct AssocStub {
    var indiID: String
    var name:   String
}

// MARK: - Build context (pre-computed record IDs)

private struct BuildContext {
    let mainIndiID: String
    let sourID:     String
    var objeID:     String? = nil
    var additionalObjeIDs: [String] = []

    // Related INDI xrefs
    var spouseIndiIDs:   [String] = []
    var childrenIndiIDs: [String] = []
    var fatherIndiID:    String?  = nil
    var motherIndiID:    String?  = nil

    // FAM xrefs
    var spouseFamIDs:   [String] = []
    var childOnlyFamID: String?  = nil
    var parentFamID:    String?  = nil

    // Full-person tracking (parallel arrays)
    var spouseIsFullPerson:  [Bool] = []   // parallel to spouseIndiIDs
    var childIsFullPerson:   [Bool] = []   // parallel to childrenIndiIDs
    var fatherIsFullPerson:  Bool   = false
    var motherIsFullPerson:  Bool   = false
    var spouseIsNewFam:      [Bool] = []   // true = this context creates the FAM record
    var parentFamIsNew:      Bool   = true // true = this context creates the parent FAM record

    // Influential persons (ASSO)
    var assocLinks: [AssocLink] = []
    var assocStubs: [AssocStub] = []

    init(from person: PersonData, sourID: String,
         personRegistry: [String: String],
         familyRegistry: inout [String: String],
         nextI: inout Int, nextF: inout Int, nextO: inout Int) {

        // Main INDI ID — look up in personRegistry first
        self.mainIndiID = personRegistry[person.wikiTitle ?? ""]
                       ?? personRegistry[person.name ?? ""]
                       ?? { let id = "@I\(nextI)@"; nextI += 1; return id }()
        self.sourID = sourID

        // Spouses — look up in registry, create/find FAM via familyRegistry
        for spouse in person.spouses {
            let spouseID: String
            let isFull: Bool
            if let wt = spouse.wikiTitle, !wt.isEmpty, let id = personRegistry[wt] {
                spouseID = id; isFull = true
            } else if !spouse.name.isEmpty, let id = personRegistry[spouse.name] {
                spouseID = id; isFull = true
            } else {
                spouseID = "@I\(nextI)@"; nextI += 1; isFull = false
            }
            spouseIndiIDs.append(spouseID)
            spouseIsFullPerson.append(isFull)

            // FAM deduplication
            let sortedPair = [mainIndiID, spouseID].sorted().joined(separator: "+")
            if let existingFam = familyRegistry[sortedPair] {
                spouseFamIDs.append(existingFam)
                spouseIsNewFam.append(false)
            } else {
                let famID = "@F\(nextF)@"; nextF += 1
                familyRegistry[sortedPair] = famID
                spouseFamIDs.append(famID)
                spouseIsNewFam.append(true)
            }
        }

        // Children — look up in registry
        for child in person.children {
            let childID: String
            let isFull: Bool
            if let wt = child.wikiTitle, !wt.isEmpty, let id = personRegistry[wt] {
                childID = id; isFull = true
            } else if !child.name.isEmpty, let id = personRegistry[child.name] {
                childID = id; isFull = true
            } else {
                childID = "@I\(nextI)@"; nextI += 1; isFull = false
            }
            childrenIndiIDs.append(childID)
            childIsFullPerson.append(isFull)
        }

        // If children but no spouse: extra FAMS
        if person.spouses.isEmpty && !person.children.isEmpty {
            childOnlyFamID = "@F\(nextF)@"; nextF += 1
        }

        // Parent family — look up in registry, use familyRegistry for FAM dedup
        let fatherRef = person.father ?? person.parents.first
        let motherRef = person.mother ?? (person.parents.count >= 2 ? person.parents[1] : nil)
        let hasParents = fatherRef != nil || motherRef != nil

        if hasParents {
            var fid: String? = nil
            var fFull = false
            if let fr = fatherRef {
                if let wt = fr.wikiTitle, !wt.isEmpty, let id = personRegistry[wt] {
                    fid = id; fFull = true
                } else if !fr.name.isEmpty, let id = personRegistry[fr.name] {
                    fid = id; fFull = true
                } else {
                    fid = "@I\(nextI)@"; nextI += 1
                }
            }
            var mid: String? = nil
            var mFull = false
            if let mr = motherRef {
                if let wt = mr.wikiTitle, !wt.isEmpty, let id = personRegistry[wt] {
                    mid = id; mFull = true
                } else if !mr.name.isEmpty, let id = personRegistry[mr.name] {
                    mid = id; mFull = true
                } else {
                    mid = "@I\(nextI)@"; nextI += 1
                }
            }

            fatherIndiID = fid
            motherIndiID = mid
            fatherIsFullPerson = fFull
            motherIsFullPerson = mFull

            // FAM deduplication for parent family
            let a = fid ?? "_nil_"
            let b = mid ?? "_nil_"
            let sortedParentPair = [a, b].sorted().joined(separator: "+")
            if let existingFam = familyRegistry[sortedParentPair] {
                parentFamID = existingFam
                parentFamIsNew = false
            } else {
                parentFamID = "@F\(nextF)@"; nextF += 1
                familyRegistry[sortedParentPair] = parentFamID!
                parentFamIsNew = true
            }
        }

        // Predecessors and successors → ASSO (influential persons)
        var seenNames: [String: String] = [:]
        for pos in person.titledPositions {
            for (name, rela) in [(pos.predecessor, "Predecessor"),
                                 (pos.successor,   "Successor")] {
                guard let n = name, !n.isEmpty else { continue }
                if seenNames[n] == nil {
                    seenNames[n] = "@I\(nextI)@"; nextI += 1
                    assocStubs.append(AssocStub(indiID: seenNames[n]!, name: n))
                }
                assocLinks.append(AssocLink(
                    indiID: seenNames[n]!,
                    rela:   rela,
                    note:   pos.title.isEmpty ? nil : "as \(pos.title)"))
            }
        }

        // Multimedia — portrait
        if person.imageURL != nil || person.imageFilePath != nil {
            objeID = "@O\(nextO)@"; nextO += 1
        }
        for _ in person.additionalMedia {
            additionalObjeIDs.append("@O\(nextO)@"); nextO += 1
        }
    }
}

// MARK: - Builder

struct GEDCOMBuilder {
    private var lines: [String] = []

    // Convenience: single-person entry point (keeps existing call sites working)
    mutating func build(person: PersonData, verbose: Bool) -> String {
        build(persons: [person], verbose: verbose)
    }

    mutating func build(persons: [PersonData], verbose: Bool) -> String {
        lines = []

        // ── Allocate source IDs ────────────────────────────────────────────────
        var sourIDs: [String: String] = [:]
        var nextS = 1
        for person in persons {
            let base = baseURL(from: person.wikiURL ?? "")
            if sourIDs[base] == nil { sourIDs[base] = "@S\(nextS)@"; nextS += 1 }
        }

        // ── Pre-allocate main INDI IDs for all persons ─────────────────────────
        // Build personRegistry before constructing contexts so cross-references
        // between persons in the list resolve to the correct pre-allocated IDs.
        var personRegistry: [String: String] = [:]  // wikiTitle/name → mainIndiID
        var nextI = 1, nextF = 1, nextO = 1
        for person in persons {
            let id = "@I\(nextI)@"; nextI += 1
            if let wt = person.wikiTitle, !wt.isEmpty { personRegistry[wt] = id }
            // Also register by display name as fallback (don't overwrite a wiki-title match)
            if let nm = person.name, !nm.isEmpty, personRegistry[nm] == nil { personRegistry[nm] = id }
        }

        // ── Build contexts with shared registries ──────────────────────────────
        var familyRegistry: [String: String] = [:]   // sorted-pair key → famID
        var contexts: [BuildContext] = []
        for person in persons {
            let base = baseURL(from: person.wikiURL ?? "")
            let sID  = sourIDs[base] ?? "@S1@"
            contexts.append(BuildContext(from: person, sourID: sID,
                                          personRegistry: personRegistry,
                                          familyRegistry: &familyRegistry,
                                          nextI: &nextI, nextF: &nextF, nextO: &nextO))
        }

        // ── Write records ──────────────────────────────────────────────────────
        writeHeader(persons: persons)

        for (person, ctx) in zip(persons, contexts) {
            writeMainIndividual(person: person, ctx: ctx)
            writeSpouseStubs(person: person, ctx: ctx)
            writeChildrenStubs(person: person, ctx: ctx)
            writeParentStubs(person: person, ctx: ctx)
            writeFamilies(person: person, ctx: ctx)
            writeAssocStubs(ctx: ctx)
        }

        // One SOUR per unique base URL
        for (base, sID) in sourIDs.sorted(by: { $0.value < $1.value }) {
            writeSource(baseURL: base, sourID: sID)
        }

        for (person, ctx) in zip(persons, contexts) {
            if let oid = ctx.objeID { writeMultimedia(person: person, objeID: oid) }
            writeAdditionalMedia(person: person, ctx: ctx)
        }

        writeTrailer()
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: HEAD

    private mutating func writeHeader(persons: [PersonData]) {
        line(0, "HEAD")
        line(1, "GEDC")
        line(2, "VERS 7.0")
        line(1, "LANG en")
        line(1, "SOUR WikipediaScraper")
        line(2, "VERS 1.0")
        line(2, "NAME WikipediaScraper")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "d MMM yyyy"
        let ds = formatter.string(from: Date()).uppercased()
        line(1, "DATE \(ds)")
        formatter.dateFormat = "HH:mm:ss"
        line(2, "TIME \(formatter.string(from: Date()))")
        let titles = persons.compactMap { $0.wikiTitle }.joined(separator: ", ")
        if !titles.isEmpty {
            line(1, "NOTE Generated from Wikipedia: \(titles)")
        }
    }

    // MARK: Main INDI

    private mutating func writeMainIndividual(person: PersonData, ctx: BuildContext) {
        line(0, "\(ctx.mainIndiID) INDI")

        // Helper: strip GEDCOM /…/ markers and collapse whitespace for comparison
        let normaliseName: (String) -> String = {
            $0.replacingOccurrences(of: "/", with: "")
              .components(separatedBy: .whitespaces).filter { !$0.isEmpty }
              .joined(separator: " ")
        }

        let given = person.givenName ?? ""
        let surn  = person.surname   ?? ""

        // 1. Primary name — Wikipedia article title
        //    Falls back to infobox name if wikiTitle is not set.
        let primaryName = person.wikiTitle ?? person.name ?? ""
        if !primaryName.isEmpty {
            line(1, "NAME \(primaryName)")
            // GIVN / SURN from infobox if available; otherwise split the title
            if !given.isEmpty || !surn.isEmpty {
                if !given.isEmpty { line(2, "GIVN \(given)") }
                if !surn.isEmpty  { line(2, "SURN \(surn)") }
            } else {
                let (g, s) = splitGivenSurname(primaryName)
                if !g.isEmpty { line(2, "GIVN \(g)") }
                if !s.isEmpty { line(2, "SURN \(s)") }
            }
        }

        // 2. Infobox-structured name as additional NAME (if different from primary)
        //    Formatted as "Given /Surname/" for genealogy-app indexing.
        let infoName: String?
        if !given.isEmpty && !surn.isEmpty {
            infoName = "\(given) /\(surn)/"
        } else if !given.isEmpty {
            infoName = given
        } else if !surn.isEmpty {
            infoName = "/\(surn)/"
        } else {
            infoName = person.name
        }
        if let inf = infoName, !inf.isEmpty,
           normaliseName(inf) != normaliseName(primaryName) {
            line(1, "NAME \(inf)")
            if !given.isEmpty { line(2, "GIVN \(given)") }
            if !surn.isEmpty  { line(2, "SURN \(surn)") }
        }

        // 3. Birth name
        if let bn = person.birthName, !bn.isEmpty,
           normaliseName(bn) != normaliseName(primaryName) {
            line(1, "NAME \(bn)")
            line(2, "TYPE birth")
        }

        // 4. Other alternate names
        for alt in person.alternateNames {
            line(1, "NAME \(alt)")
            line(2, "TYPE aka")
        }

        // Sex — only write when known
        switch person.sex {
        case .male:    line(1, "SEX M")
        case .female:  line(1, "SEX F")
        case .unknown: break
        }

        // Life events
        if let e = person.birth   { writeEvent("BIRT", e, 1, ctx.sourID) }
        if let e = person.death   { writeEvent("DEAT", e, 1, ctx.sourID) }
        if let e = person.burial  { writeEvent("BURI", e, 1, ctx.sourID) }
        if let e = person.baptism { writeEvent("BAPM", e, 1, ctx.sourID) }

        // Honorifics — simple titles without date range
        for title in person.honorifics {
            line(1, "TITL \(title)")
            line(2, "SOUR \(ctx.sourID)")
        }

        // Titled positions — EVEN TYPE "Nobility title" (shows in timeline)
        for pos in person.titledPositions {
            line(1, "EVEN \(pos.title)")
            line(2, "TYPE Nobility title")
            let dp = titledPositionDate(pos)
            if !dp.isEmpty { line(2, "DATE \(dp)") }
            if let place = pos.place { line(2, "PLAC \(place)") }
            var noteItems: [String] = []
            if let p = pos.predecessor { noteItems.append("Preceded by: \(p)") }
            if let s = pos.successor   { noteItems.append("Succeeded by: \(s)") }
            if let n = pos.note        { noteItems.append(n) }
            if !noteItems.isEmpty { line(2, "NOTE \(noteItems.joined(separator: ". "))") }
            line(2, "SOUR \(ctx.sourID)")
        }

        // Custom events — EVEN with TYPE
        for evt in person.customEvents {
            line(1, "EVEN")
            line(2, "TYPE \(evt.type)")
            if let d = evt.date, !d.isEmpty { line(2, "DATE \(d.gedcom)") }
            if let p = evt.place            { line(2, "PLAC \(p)") }
            if let n = evt.note             { line(2, "NOTE \(n)") }
            line(2, "SOUR \(ctx.sourID)")
        }

        // Person facts — FACT with TYPE
        for fact in person.personFacts {
            line(1, "FACT \(fact.value)")
            line(2, "TYPE \(fact.type)")
            line(2, "SOUR \(ctx.sourID)")
        }

        // Occupations
        let allOccu: [String] = person.occupations
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for occ in allOccu {
            line(1, "OCCU \(occ)")
            line(2, "SOUR \(ctx.sourID)")
        }

        // Nationality / Religion
        if let n = person.nationality { line(1, "NATI \(n)") }
        if let r = person.religion    { line(1, "RELI \(r)") }

        // Associations — predecessor/successor as influential persons (ASSO)
        for asso in ctx.assocLinks {
            line(1, "ASSO \(asso.indiID)")
            line(2, "RELA \(asso.rela)")
            if let n = asso.note { line(2, "NOTE \(n)") }
            line(2, "SOUR \(ctx.sourID)")
        }

        // Wikipedia article sections — one NOTE per section (--notes)
        for section in person.wikiSections {
            line(1, "NOTE \(section.title)")
            for para in section.text.components(separatedBy: "\n") {
                let p = para.trimmingCharacters(in: .whitespacesAndNewlines)
                if !p.isEmpty { line(2, "CONT \(p)") }
            }
        }

        // FAMS — one per spouse family
        for famID in ctx.spouseFamIDs { line(1, "FAMS \(famID)") }
        if let f = ctx.childOnlyFamID { line(1, "FAMS \(f)") }

        // FAMC — family where main person is the child
        if let f = ctx.parentFamID { line(1, "FAMC \(f)") }

        // Source citation — PAGE is the specific article URL
        line(1, "SOUR \(ctx.sourID)")
        if let url = person.wikiURL {
            line(2, "PAGE \(url)")
        } else if let t = person.wikiTitle {
            line(2, "PAGE Wikipedia article: \(t)")
        }
        // Include article extract as DATA.TEXT in the citation
        if let ex = person.wikiExtract {
            let excerpt = String(ex.prefix(500)).replacingOccurrences(of: "\n", with: " ")
            line(2, "DATA")
            line(3, "TEXT \(excerpt)")
        }

        // Multimedia links — portrait + additional images
        if let oid = ctx.objeID { line(1, "OBJE \(oid)") }
        for oid in ctx.additionalObjeIDs { line(1, "OBJE \(oid)") }
    }

    // MARK: Spouse stubs

    private mutating func writeSpouseStubs(person: PersonData, ctx: BuildContext) {
        let spouseSex: Sex = person.sex == .male   ? .female
                           : person.sex == .female ? .male
                           : .unknown

        for (i, spouse) in person.spouses.enumerated() {
            guard i < ctx.spouseIndiIDs.count else { continue }
            guard !ctx.spouseIsFullPerson[i] else { continue }   // skip full persons
            let indi = ctx.spouseIndiIDs[i]
            let fam  = ctx.spouseFamIDs[i]

            line(0, "\(indi) INDI")
            let (g, s) = splitGivenSurname(spouse.name)
            line(1, "NAME \(gedcomName(given: g, surname: s, full: spouse.name))")
            if !g.isEmpty { line(2, "GIVN \(g)") }
            if !s.isEmpty { line(2, "SURN \(s)") }
            switch spouseSex {
            case .male:    line(1, "SEX M")
            case .female:  line(1, "SEX F")
            case .unknown: break
            }
            line(1, "FAMS \(fam)")
        }
    }

    // MARK: Children stubs

    private mutating func writeChildrenStubs(person: PersonData, ctx: BuildContext) {
        let childFamID = ctx.spouseFamIDs.first ?? ctx.childOnlyFamID

        for (i, child) in person.children.enumerated() {
            guard i < ctx.childrenIndiIDs.count else { continue }
            guard !ctx.childIsFullPerson[i] else { continue }   // skip full persons
            let indi = ctx.childrenIndiIDs[i]

            line(0, "\(indi) INDI")
            let (g, s) = splitGivenSurname(child.name)
            line(1, "NAME \(gedcomName(given: g, surname: s, full: child.name))")
            if !g.isEmpty { line(2, "GIVN \(g)") }
            if !s.isEmpty { line(2, "SURN \(s)") }
            if let f = childFamID { line(1, "FAMC \(f)") }
        }
    }

    // MARK: Parent stubs

    private mutating func writeParentStubs(person: PersonData, ctx: BuildContext) {
        guard let pfam = ctx.parentFamID else { return }

        let fatherRef = person.father ?? person.parents.first
        if let fr = fatherRef, let fid = ctx.fatherIndiID, !ctx.fatherIsFullPerson {
            line(0, "\(fid) INDI")
            let (g, s) = splitGivenSurname(fr.name)
            line(1, "NAME \(gedcomName(given: g, surname: s, full: fr.name))")
            if !g.isEmpty { line(2, "GIVN \(g)") }
            if !s.isEmpty { line(2, "SURN \(s)") }
            line(1, "SEX M")
            line(1, "FAMS \(pfam)")
        }

        let motherRef = person.mother ?? (person.parents.count >= 2 ? person.parents[1] : nil)
        if let mr = motherRef, let mid = ctx.motherIndiID, !ctx.motherIsFullPerson {
            line(0, "\(mid) INDI")
            let (g, s) = splitGivenSurname(mr.name)
            line(1, "NAME \(gedcomName(given: g, surname: s, full: mr.name))")
            if !g.isEmpty { line(2, "GIVN \(g)") }
            if !s.isEmpty { line(2, "SURN \(s)") }
            line(1, "SEX F")
            line(1, "FAMS \(pfam)")
        }
    }

    // MARK: FAM records

    private mutating func writeFamilies(person: PersonData, ctx: BuildContext) {
        let personIsHusband = person.sex != .female

        for (i, spouse) in person.spouses.enumerated() {
            guard i < ctx.spouseFamIDs.count, i < ctx.spouseIndiIDs.count else { continue }
            guard ctx.spouseIsNewFam[i] else { continue }   // only write FAM once

            let famID    = ctx.spouseFamIDs[i]
            let spouseID = ctx.spouseIndiIDs[i]

            line(0, "\(famID) FAM")
            if personIsHusband {
                line(1, "HUSB \(ctx.mainIndiID)")
                line(1, "WIFE \(spouseID)")
            } else {
                line(1, "HUSB \(spouseID)")
                line(1, "WIFE \(ctx.mainIndiID)")
            }

            if let md = spouse.marriageDate, !md.isEmpty {
                line(1, "MARR")
                line(2, "DATE \(md.gedcom)")
                if let mp = spouse.marriagePlace { line(2, "PLAC \(mp)") }
                line(2, "SOUR \(ctx.sourID)")
            }

            if let dd = spouse.divorceDate, !dd.isEmpty {
                line(1, "DIV")
                line(2, "DATE \(dd.gedcom)")
            }

            if i == 0 {
                for childID in ctx.childrenIndiIDs { line(1, "CHIL \(childID)") }
            }

            line(1, "SOUR \(ctx.sourID)")
        }

        if let cof = ctx.childOnlyFamID {
            line(0, "\(cof) FAM")
            if personIsHusband { line(1, "HUSB \(ctx.mainIndiID)") }
            else               { line(1, "WIFE \(ctx.mainIndiID)") }
            for childID in ctx.childrenIndiIDs { line(1, "CHIL \(childID)") }
            line(1, "SOUR \(ctx.sourID)")
        }

        if let pfam = ctx.parentFamID, ctx.parentFamIsNew {   // only write parent FAM once
            line(0, "\(pfam) FAM")
            if let fid = ctx.fatherIndiID { line(1, "HUSB \(fid)") }
            if let mid = ctx.motherIndiID { line(1, "WIFE \(mid)") }
            line(1, "CHIL \(ctx.mainIndiID)")
            line(1, "SOUR \(ctx.sourID)")
        }
    }

    // MARK: ASSO stubs (predecessor / successor influential persons)

    private mutating func writeAssocStubs(ctx: BuildContext) {
        for stub in ctx.assocStubs {
            line(0, "\(stub.indiID) INDI")
            let (g, s) = splitGivenSurname(stub.name)
            line(1, "NAME \(gedcomName(given: g, surname: s, full: stub.name))")
            if !g.isEmpty { line(2, "GIVN \(g)") }
            if !s.isEmpty { line(2, "SURN \(s)") }
        }
    }

    // MARK: SOUR — one record per unique base URL (Web source with WWW tag)

    private mutating func writeSource(baseURL: String, sourID: String) {
        let name      = sourceName(for: baseURL)
        let publisher = sourcePublisher(for: baseURL)

        line(0, "\(sourID) SOUR")
        line(1, "TITL \(name)")
        line(1, "AUTH \(name) contributors")
        line(1, "PUBL \(publisher)")
        line(1, "WWW \(baseURL)")
        let df = DateFormatter()
        df.locale     = Locale(identifier: "en_US")
        df.dateFormat = "d MMM yyyy"
        line(1, "DATE \(df.string(from: Date()).uppercased())")
    }

    // MARK: OBJE

    private mutating func writeMultimedia(person: PersonData, objeID: String) {
        guard let filePath = person.imageFilePath ?? person.imageURL else { return }

        let ref = person.imageMimeType ?? person.imageURL ?? filePath
        let format: String
        switch ref.lowercased() {
        case let s where s.contains("image/png")  || s.hasSuffix(".png"):  format = "PNG"
        case let s where s.contains("image/gif")  || s.hasSuffix(".gif"):  format = "GIF"
        case let s where s.contains("image/webp") || s.hasSuffix(".webp"): format = "WEBP"
        default: format = "JPEG"
        }

        line(0, "\(objeID) OBJE")
        line(1, "FILE \(filePath)")
        line(2, "FORM \(format)")
        if let t = person.wikiTitle { line(2, "TITL Portrait of \(t)") }
    }

    // MARK: Additional OBJE records (--allimages)

    private mutating func writeAdditionalMedia(person: PersonData, ctx: BuildContext) {
        for (i, media) in person.additionalMedia.enumerated() {
            guard i < ctx.additionalObjeIDs.count else { break }
            let oid = ctx.additionalObjeIDs[i]

            let format: String
            switch (media.mimeType ?? "").lowercased() {
            case let s where s.contains("image/png"):  format = "PNG"
            case let s where s.contains("image/webp"): format = "WEBP"
            default: format = "JPEG"
            }

            line(0, "\(oid) OBJE")
            line(1, "FILE \(media.filePath)")
            line(2, "FORM \(format)")
            if let t = media.title { line(2, "TITL \(t)") }
        }
    }

    // MARK: TRLR

    private mutating func writeTrailer() { line(0, "TRLR") }

    // MARK: Event helper

    private mutating func writeEvent(_ tag: String, _ event: PersonEvent,
                                     _ level: Int, _ sourID: String) {
        let hasDate  = event.date  != nil && !event.date!.isEmpty
        let hasPlace = event.place != nil

        if hasDate || hasPlace || event.note != nil || event.cause != nil {
            line(level, tag)
            if let d = event.date,  !d.isEmpty { line(level+1, "DATE \(d.gedcom)") }
            if let p = event.place             { line(level+1, "PLAC \(p)") }
            if let c = event.cause             { line(level+1, "CAUS \(c)") }
            if let n = event.note              { line(level+1, "NOTE \(n)") }
            line(level+1, "SOUR \(sourID)")
        } else {
            line(level, "\(tag) Y")
            line(level+1, "SOUR \(sourID)")
        }
    }

    private func titledPositionDate(_ pos: TitledPosition) -> String {
        let start = pos.startDate.flatMap { $0.isEmpty ? nil : $0.gedcom }
        let end   = pos.endDate.flatMap   { $0.isEmpty ? nil : $0.gedcom }
        switch (start, end) {
        case let (s?, e?): return "FROM \(s) TO \(e)"
        case let (s?, nil): return "FROM \(s)"
        case let (nil, e?): return "TO \(e)"
        case (nil, nil): return ""
        }
    }

    // MARK: Source URL helpers

    private func baseURL(from urlString: String) -> String {
        guard let url    = URL(string: urlString),
              let scheme = url.scheme,
              let host   = url.host
        else { return urlString.isEmpty ? "https://en.wikipedia.org/" : urlString }
        return "\(scheme)://\(host)/"
    }

    private func sourceName(for baseURL: String) -> String {
        if baseURL.contains("wikipedia.org") { return "Wikipedia" }
        return URL(string: baseURL)?.host ?? baseURL
    }

    private func sourcePublisher(for baseURL: String) -> String {
        if baseURL.contains("wikipedia.org") { return "Wikimedia Foundation" }
        return URL(string: baseURL)?.host ?? baseURL
    }

    // MARK: Name helpers

    private func splitGivenSurname(_ name: String) -> (String, String) {
        if let s = name.firstIndex(of: "/"), let e = name.lastIndex(of: "/"), s != e {
            let surn  = String(name[name.index(after: s)..<e])
            let given = name[name.startIndex..<s].trimmingCharacters(in: .whitespaces)
            return (given, surn)
        }
        let tokens = name.components(separatedBy: " ").filter { !$0.isEmpty }
        guard tokens.count >= 2 else { return (name, "") }
        return (tokens.dropLast().joined(separator: " "), tokens.last!)
    }

    private func gedcomName(given: String, surname: String, full: String) -> String {
        if given.isEmpty && surname.isEmpty { return full }
        if surname.isEmpty { return given }
        return "\(given) /\(surname)/"
    }

    // MARK: Line writer (GEDCOM 7: max 255 bytes per line, CONT for overflow)

    private mutating func line(_ level: Int, _ content: String) {
        let full = "\(level) \(content)"
        guard full.utf8.count > 255 else { lines.append(full); return }

        var firstBytes = Array(full.utf8.prefix(255))
        while !firstBytes.isEmpty, (firstBytes.last! & 0xC0) == 0x80 { firstBytes.removeLast() }
        let firstLine = String(bytes: firstBytes, encoding: .utf8) ?? String(full.prefix(255))
        lines.append(firstLine)

        var remaining = String(full.utf8.dropFirst(firstBytes.count)) ?? ""
        let contPrefix = "\(level + 1) CONT "
        let maxCont    = 255 - contPrefix.utf8.count
        while !remaining.isEmpty {
            var chunkBytes = Array(remaining.utf8.prefix(maxCont))
            while !chunkBytes.isEmpty, (chunkBytes.last! & 0xC0) == 0x80 { chunkBytes.removeLast() }
            if chunkBytes.isEmpty { break }
            let chunk = String(bytes: chunkBytes, encoding: .utf8) ?? ""
            lines.append(contPrefix + chunk)
            guard let next = String(remaining.utf8.dropFirst(chunkBytes.count)) else { break }
            remaining = next
        }
    }
}

private extension String {
    init?(_ substring: String.UTF8View.SubSequence) {
        self.init(bytes: Array(substring), encoding: .utf8)
    }
}
