// MappingsReporter.swift — Show what Wikipedia infobox fields map to GEDCOM 7 structures

import Foundation

public struct MappingsReporter {

    // MARK: - Public entry point

    public static func report(
        person:    PersonData,
        rawFields: [String: String],
        wikiURL:   String?
    ) -> String {
        var out = ""
        let w = 78  // total ruler width

        out += ruler(w)
        out += "Wikipedia → GEDCOM 7 field mappings\n"
        if let url = wikiURL { out += "Source:  \(url)\n" }
        if let t = person.wikiTitle { out += "Article: \(t)\n" }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US"); df.dateFormat = "d MMM yyyy"
        out += "Date:    \(df.string(from: Date()).uppercased())\n"
        out += ruler(w)

        let col1 = 24  // field name column width
        let col2 = 26  // raw value column width
        // remainder goes to GEDCOM path

        out += padR("WIKIPEDIA FIELD", col1) + "  "
             + padR("RAW VALUE", col2) + "  "
             + "GEDCOM 7 STRUCTURE\n"
        out += ruler(w)

        var usedFields = Set<String>()
        var rows: [(wiki: String, raw: String, paths: [String])] = []

        func addRow(_ wikiKey: String, raw: String, paths: [String]) {
            usedFields.insert(wikiKey)
            rows.append((wikiKey, raw, paths))
        }

        // ── Name ──────────────────────────────────────────────────────────────
        let nameKey = firstPresent(["name", "full_name"], in: rawFields)
        let nameRaw = nameKey.flatMap { rawFields[$0] }
        // Always show name row (may come from page title when no name field exists)
        do {
            var paths: [String] = []
            let given = person.givenName ?? ""; let surn = person.surname ?? ""
            if !given.isEmpty || !surn.isEmpty {
                paths.append("@I1@ INDI.NAME \"\(given) /\(surn)/\"")
                if !given.isEmpty { paths.append("@I1@ INDI.NAME.GIVN \"\(given)\"") }
                if !surn.isEmpty  { paths.append("@I1@ INDI.NAME.SURN \"\(surn)\"") }
            } else if let full = person.name {
                paths.append("@I1@ INDI.NAME \"\(full)\"")
            }
            let displayKey = nameKey ?? "(page title)"
            let displayRaw = nameRaw ?? person.wikiTitle ?? ""
            if let nk = nameKey { usedFields.insert(nk) }
            rows.append((displayKey, truncate(displayRaw, col2), paths))
        }

        // Birth name
        if let nk = firstPresent(["birth_name"], in: rawFields), let nr = rawFields[nk],
           let bn = person.birthName {
            addRow(nk, raw: truncate(nr, 38),
                   paths: ["@I1@ INDI.NAME \"\(bn)\"",
                           "@I1@ INDI.NAME.TYPE birth"])
        }

        // Gender/sex
        if let nk = firstPresent(["gender","sex","pronouns"], in: rawFields), let nr = rawFields[nk] {
            let val: String
            switch person.sex {
            case .male:    val = "@I1@ INDI.SEX M"
            case .female:  val = "@I1@ INDI.SEX F"
            case .unknown: val = "(not written — sex undetermined)"
            }
            addRow(nk, raw: truncate(nr, 38), paths: [val])
        }

        // ── Birth ─────────────────────────────────────────────────────────────
        if let nk = firstPresent(["birth_date","date_of_birth","born"], in: rawFields),
           let nr = rawFields[nk] {
            let dateStr = person.birth?.date.flatMap { $0.isEmpty ? nil : $0.gedcom } ?? "(not parsed)"
            addRow(nk, raw: truncate(nr, 38),
                   paths: ["@I1@ INDI.BIRT.DATE \"\(dateStr)\"",
                           "@I1@ INDI.BIRT.SOUR @S1@"])
        }

        if let nk = firstPresent(["birth_place","place_of_birth","birthplace"], in: rawFields),
           let nr = rawFields[nk] {
            let placeStr = person.birth?.place ?? "(not parsed)"
            addRow(nk, raw: truncate(nr, 38),
                   paths: ["@I1@ INDI.BIRT.PLAC \"\(truncate(placeStr, 40))\""])
        }

        // ── Death ─────────────────────────────────────────────────────────────
        if let nk = firstPresent(["death_date","date_of_death","died"], in: rawFields),
           let nr = rawFields[nk] {
            let dateStr = person.death?.date.flatMap { $0.isEmpty ? nil : $0.gedcom } ?? "(not parsed)"
            addRow(nk, raw: truncate(nr, 38),
                   paths: ["@I1@ INDI.DEAT.DATE \"\(dateStr)\"",
                           "@I1@ INDI.DEAT.SOUR @S1@"])
        }

        if let nk = firstPresent(["death_place","place_of_death","deathplace"], in: rawFields),
           let nr = rawFields[nk] {
            let placeStr = person.death?.place ?? "(not parsed)"
            addRow(nk, raw: truncate(nr, 38),
                   paths: ["@I1@ INDI.DEAT.PLAC \"\(truncate(placeStr, 40))\""])
        }

        // ── Burial ────────────────────────────────────────────────────────────
        if let nk = firstPresent(["burial_place","resting_place","place_of_burial"], in: rawFields),
           let nr = rawFields[nk] {
            let placeStr = person.burial?.place ?? "(not parsed)"
            addRow(nk, raw: truncate(nr, 38),
                   paths: ["@I1@ INDI.BURI.PLAC \"\(truncate(placeStr, 40))\""])
        }

        // ── Baptism ───────────────────────────────────────────────────────────
        if let nk = firstPresent(["baptism_date","christening_date"], in: rawFields),
           let nr = rawFields[nk] {
            let dateStr = person.baptism?.date.flatMap { $0.isEmpty ? nil : $0.gedcom } ?? "(not parsed)"
            addRow(nk, raw: truncate(nr, 38),
                   paths: ["@I1@ INDI.BAPM.DATE \"\(dateStr)\""])
        }

        // ── Family: spouses ───────────────────────────────────────────────────
        let spouseKeys = ["spouse","spouses","partner","partners"]
        if let nk = firstPresent(spouseKeys, in: rawFields), let nr = rawFields[nk] {
            var paths: [String] = []
            var nextI = 2
            var nextF = 1
            for (i, sp) in person.spouses.enumerated() {
                let si = "@I\(nextI)@"; nextI += 1
                let fi = "@F\(nextF)@"; nextF += 1
                paths.append("@I1@ INDI.FAMS \(fi)")
                paths.append("\(si) INDI.NAME \"\(sp.name)\" (stub)")
                if let md = sp.marriageDate, !md.isEmpty {
                    paths.append("\(fi) FAM.MARR.DATE \"\(md.gedcom)\"")
                }
                if let mp = sp.marriagePlace {
                    paths.append("\(fi) FAM.MARR.PLAC \"\(mp)\"")
                }
                if i == 0 && !person.children.isEmpty {
                    // children go in this family
                    for ci in person.children.indices {
                        let cid = "@I\(nextI + ci)@"
                        paths.append("\(fi) FAM.CHIL \(cid)")
                    }
                }
            }
            if paths.isEmpty { paths.append("(no spouses parsed)") }
            addRow(nk, raw: truncate(nr, 38), paths: paths)
        }

        // ── Family: children ─────────────────────────────────────────────────
        if let nk = firstPresent(["children","issue","offspring"], in: rawFields),
           let nr = rawFields[nk], !person.children.isEmpty {
            // Compute offset — children INDI IDs come after spouses
            let spouseOffset = 2 + person.spouses.count
            let paths = person.children.enumerated().map { (i, child) in
                "@I\(spouseOffset + i)@ INDI.NAME \"\(child.name)\" (stub)"
            }
            addRow(nk, raw: truncate(nr, 38), paths: paths)
        }

        // ── Family: parents ───────────────────────────────────────────────────
        let parentFamOffset = person.spouses.count + (person.spouses.isEmpty && !person.children.isEmpty ? 1 : 0) + 1
        let childrenOffset  = 2 + person.spouses.count
        let parentIndiOffset = childrenOffset + person.children.count
        var parentFamWritten = false

        if let nk = firstPresent(["father"], in: rawFields), let nr = rawFields[nk],
           let fref = person.father {
            let pfam = "@F\(parentFamOffset)@"
            let fid  = "@I\(parentIndiOffset)@"
            addRow(nk, raw: truncate(nr, 38),
                   paths: ["@I1@ INDI.FAMC \(pfam)",
                           "\(pfam) FAM.HUSB \(fid)",
                           "\(fid) INDI.NAME \"\(fref.name)\" (stub)",
                           "\(fid) INDI.SEX M"])
            parentFamWritten = true
        }

        if let nk = firstPresent(["mother"], in: rawFields), let nr = rawFields[nk],
           let mref = person.mother {
            let pfam = "@F\(parentFamOffset)@"
            let mid  = "@I\(parentIndiOffset + (person.father != nil ? 1 : 0))@"
            addRow(nk, raw: truncate(nr, 38),
                   paths: [parentFamWritten ? "\(pfam) FAM.WIFE \(mid)" : "@I1@ INDI.FAMC \(pfam)",
                           "\(mid) INDI.NAME \"\(mref.name)\" (stub)",
                           "\(mid) INDI.SEX F"])
        }

        if let nk = firstPresent(["parents"], in: rawFields), let nr = rawFields[nk],
           !person.parents.isEmpty {
            addRow(nk, raw: truncate(nr, 38),
                   paths: person.parents.map { "@I\(parentIndiOffset)@ INDI.NAME \"\($0.name)\" (stub)" })
        }

        // ── Honorifics (simple TITL) ──────────────────────────────────────────
        let honorificKeys = ["title","titles","royal_title","noble_title","honorific_prefix",
                             "honorific_suffix","post_nominals","style","imperial_style"]
        if let nk = firstPresent(honorificKeys, in: rawFields), let nr = rawFields[nk],
           !person.honorifics.isEmpty {
            addRow(nk, raw: truncate(nr, 38),
                   paths: person.honorifics.map { "@I1@ INDI.TITL \"\($0)\"" })
        }

        // ── Titled positions (TITL + DATE FROM…TO) ────────────────────────────
        let reignKeys = ([""] + (1...10).map { String($0) }).compactMap { s -> String? in
            let k = "succession\(s)"; return rawFields[k] != nil ? k : nil
        }
        if !person.titledPositions.isEmpty {
            var paths: [String] = []
            for pos in person.titledPositions {
                var entry = "@I1@ INDI.TITL \"\(pos.title)\""
                if let sd = pos.startDate, !sd.isEmpty, let ed = pos.endDate, !ed.isEmpty {
                    entry += " DATE FROM \(sd.gedcom) TO \(ed.gedcom)"
                } else if let sd = pos.startDate, !sd.isEmpty {
                    entry += " DATE FROM \(sd.gedcom)"
                }
                paths.append(entry)
            }
            let displayKey = reignKeys.first ?? firstPresent(["office","office2"], in: rawFields) ?? "succession/office"
            let displayRaw = displayKey != "succession/office" ? truncate(rawFields[displayKey] ?? "", 38) : "(multiple)"
            if let k = reignKeys.first ?? firstPresent(["office","office2"], in: rawFields) { usedFields.insert(k) }
            rows.append((displayKey, displayRaw, paths))
        }

        // ── Custom events (EVEN TYPE) ─────────────────────────────────────────
        let coronationKeys = ([""] + (1...5).map { String($0) }).compactMap { s -> String? in
            let k = "coronation\(s)"; return rawFields[k] != nil ? k : nil
        }
        if !person.customEvents.isEmpty {
            let paths = person.customEvents.map { evt -> String in
                var s = "@I1@ INDI.EVEN TYPE \"\(evt.type)\""
                if let d = evt.date, !d.isEmpty { s += " DATE \(d.gedcom)" }
                return s
            }
            let displayKey = coronationKeys.first ?? "customEvents"
            let displayRaw = coronationKeys.first.flatMap { rawFields[$0] }.map { truncate($0, 38) } ?? "(parsed)"
            if let k = coronationKeys.first { usedFields.insert(k) }
            rows.append((displayKey, displayRaw, paths))
        }

        // ── Person facts (FACT TYPE) ──────────────────────────────────────────
        let factSourceKeys = ["house","dynasty","royal_house","party","branch","rank","awards"]
        if !person.personFacts.isEmpty {
            let paths = person.personFacts.map {
                "@I1@ INDI.FACT \"\($0.value)\" TYPE \"\($0.type)\""
            }
            let displayKey = firstPresent(factSourceKeys, in: rawFields) ?? "personFacts"
            let displayRaw = (firstPresent(factSourceKeys, in: rawFields)).flatMap { rawFields[$0] }
                              .map { truncate($0, 38) } ?? "(parsed)"
            for k in factSourceKeys { if rawFields[k] != nil { usedFields.insert(k) } }
            rows.append((displayKey, displayRaw, paths))
        }

        // ── Occupations ───────────────────────────────────────────────────────
        let occKeys = ["occupation","occupation(s)","profession","employer"]
        if let nk = firstPresent(occKeys, in: rawFields), let nr = rawFields[nk],
           !person.occupations.isEmpty {
            let allOcc = person.occupations
                .flatMap { $0.components(separatedBy: ",") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            addRow(nk, raw: truncate(nr, 38),
                   paths: allOcc.map { "@I1@ INDI.OCCU \"\($0)\"" })
        }

        // ── Nationality / Religion ─────────────────────────────────────────────
        if let nk = firstPresent(["nationality","citizenship","country"], in: rawFields),
           let nr = rawFields[nk], let n = person.nationality {
            addRow(nk, raw: truncate(nr, 38), paths: ["@I1@ INDI.NATI \"\(n)\""])
        }

        if let nk = firstPresent(["religion","faith"], in: rawFields), let nr = rawFields[nk],
           let r = person.religion {
            addRow(nk, raw: truncate(nr, 38), paths: ["@I1@ INDI.RELI \"\(r)\""])
        }

        // ── Image ─────────────────────────────────────────────────────────────
        if let nk = firstPresent(["image","photo","picture"], in: rawFields),
           let nr = rawFields[nk] {
            let urlVal = person.imageURL ?? "(URL not resolved)"
            addRow(nk, raw: truncate(nr, 38),
                   paths: ["@O1@ OBJE.FILE \"\(truncate(urlVal, 50))\"",
                           "@O1@ OBJE.FILE.FORM \(person.imageMimeType?.replacingOccurrences(of: "image/", with: "").uppercased() ?? "JPEG")",
                           "@I1@ INDI.OBJE @O1@"])
        }

        // ── Wikipedia source (always present) ─────────────────────────────────
        rows.append(("(source)", "(Wikipedia article)", [
            "@S1@ SOUR.TITL \"Wikipedia: \(person.wikiTitle ?? "")\"",
            "@S1@ SOUR.AUTH \"Wikipedia contributors\"",
            "@S1@ SOUR.PUBL \"Wikimedia Foundation\"",
            "@S1@ SOUR.NOTE <article URL>",
            "INDI.SOUR @S1@   (on all events)"
        ]))

        // ── Render rows ───────────────────────────────────────────────────────
        for row in rows {
            let firstPath = row.paths.first ?? ""
            out += padR(row.wiki, col1) + "  "
                 + padR(row.raw,  col2) + "  "
                 + firstPath + "\n"
            for path in row.paths.dropFirst() {
                out += String(repeating: " ", count: col1 + col2 + 4)
                     + path + "\n"
            }
        }

        // ── Unmapped fields ───────────────────────────────────────────────────
        let unmapped = rawFields.keys
            .filter { !usedFields.contains($0) }
            .sorted()

        if !unmapped.isEmpty {
            out += ruler(w)
            out += "INFOBOX FIELDS PRESENT BUT NOT MAPPED TO GEDCOM:\n"
            // Wrap in columns of ~3
            let cols = 3
            for i in stride(from: 0, to: unmapped.count, by: cols) {
                let chunk = unmapped[i..<min(i+cols, unmapped.count)]
                out += "  " + chunk.map { padR($0, 25) }.joined() + "\n"
            }
        }

        out += ruler(w)
        return out
    }

    // MARK: - Helpers

    private static func firstPresent(_ keys: [String], in dict: [String: String]) -> String? {
        keys.first { dict[$0] != nil }
    }

    private static func truncate(_ s: String, _ maxLen: Int) -> String {
        // Strip newlines for display
        let clean = s.replacingOccurrences(of: "\n", with: " ")
                     .replacingOccurrences(of: "\r", with: "")
                     .trimmingCharacters(in: .whitespaces)
        guard clean.count > maxLen else { return clean }
        return String(clean.prefix(maxLen - 1)) + "…"
    }

    private static func padR(_ s: String, _ width: Int) -> String {
        if s.count >= width { return String(s.prefix(width)) }
        return s + String(repeating: " ", count: width - s.count)
    }

    private static func ruler(_ w: Int) -> String {
        String(repeating: "─", count: w) + "\n"
    }
}
