import Foundation
import AppKit
import UniformTypeIdentifiers
import WikipediaScraperCore

// MARK: - Editable Model Types

struct EditableEvent: Identifiable {
    var id = UUID()
    var date: String = ""
    var place: String = ""
    var note: String = ""
    var cause: String = ""

    var allEmpty: Bool {
        date.isEmpty && place.isEmpty && note.isEmpty && cause.isEmpty
    }

    func toPersonEvent() -> PersonEvent? {
        guard !allEmpty else { return nil }
        let parsedDate = date.isEmpty ? nil : DateParser.parse(date)
        return PersonEvent(
            date: parsedDate,
            place: place.isEmpty ? nil : place,
            note: note.isEmpty ? nil : note,
            cause: cause.isEmpty ? nil : cause
        )
    }

    init() {}

    init(from event: PersonEvent?) {
        guard let event = event else { return }
        self.date = event.date?.gedcom ?? ""
        self.place = event.place ?? ""
        self.note = event.note ?? ""
        self.cause = event.cause ?? ""
    }
}

struct EditableTitledPosition: Identifiable {
    var id = UUID()
    var title: String = ""
    var startDate: String = ""
    var endDate: String = ""
    var place: String = ""
    var predecessor: String = ""
    var successor: String = ""
    var note: String = ""

    func toTitledPosition() -> TitledPosition {
        TitledPosition(
            title: title,
            startDate: startDate.isEmpty ? nil : DateParser.parse(startDate),
            endDate: endDate.isEmpty ? nil : DateParser.parse(endDate),
            place: place.isEmpty ? nil : place,
            predecessor: predecessor.isEmpty ? nil : predecessor,
            predecessorWikiTitle: nil,
            successor: successor.isEmpty ? nil : successor,
            successorWikiTitle: nil,
            note: note.isEmpty ? nil : note
        )
    }

    init() {}

    init(from pos: TitledPosition) {
        self.title = pos.title
        self.startDate = pos.startDate?.gedcom ?? ""
        self.endDate = pos.endDate?.gedcom ?? ""
        self.place = pos.place ?? ""
        self.predecessor = pos.predecessor ?? ""
        self.successor = pos.successor ?? ""
        self.note = pos.note ?? ""
    }
}

struct EditableCustomEvent: Identifiable {
    var id = UUID()
    var type: String = ""
    var date: String = ""
    var place: String = ""
    var note: String = ""

    func toCustomEvent() -> CustomEvent {
        CustomEvent(
            type: type,
            date: date.isEmpty ? nil : DateParser.parse(date),
            place: place.isEmpty ? nil : place,
            note: note.isEmpty ? nil : note
        )
    }

    init() {}

    init(from event: CustomEvent) {
        self.type = event.type
        self.date = event.date?.gedcom ?? ""
        self.place = event.place ?? ""
        self.note = event.note ?? ""
    }
}

struct EditablePersonFact: Identifiable {
    var id = UUID()
    var type: String = ""
    var value: String = ""

    func toPersonFact() -> PersonFact {
        PersonFact(type: type, value: value)
    }

    init() {}

    init(from fact: PersonFact) {
        self.type = fact.type
        self.value = fact.value
    }
}

struct EditableSpouse: Identifiable {
    var id = UUID()
    var name: String = ""
    var marriageDate: String = ""
    var marriagePlace: String = ""
    var divorceDate: String = ""

    func toSpouseInfo() -> SpouseInfo {
        SpouseInfo(
            name: name,
            wikiTitle: nil,
            marriageDate: marriageDate.isEmpty ? nil : DateParser.parse(marriageDate),
            marriagePlace: marriagePlace.isEmpty ? nil : marriagePlace,
            divorceDate: divorceDate.isEmpty ? nil : DateParser.parse(divorceDate)
        )
    }

    init() {}

    init(from spouse: SpouseInfo) {
        self.name = spouse.name
        self.marriageDate = spouse.marriageDate?.gedcom ?? ""
        self.marriagePlace = spouse.marriagePlace ?? ""
        self.divorceDate = spouse.divorceDate?.gedcom ?? ""
    }
}

struct EditablePersonRef: Identifiable {
    var id = UUID()
    var name: String = ""

    func toPersonRef() -> PersonRef {
        PersonRef(name: name, wikiTitle: nil)
    }

    init() {}

    init(from ref: PersonRef) {
        self.name = ref.name
    }
}

// MARK: - EditablePerson

struct EditablePerson {
    var givenName: String = ""
    var surname: String = ""
    var birthName: String = ""
    var sex: Sex = .unknown

    var birth: EditableEvent = EditableEvent()
    var death: EditableEvent = EditableEvent()
    var burial: EditableEvent = EditableEvent()
    var baptism: EditableEvent = EditableEvent()

    var titledPositions: [EditableTitledPosition] = []
    var customEvents: [EditableCustomEvent] = []
    var personFacts: [EditablePersonFact] = []
    var honorifics: [String] = []
    var spouses: [EditableSpouse] = []
    var children: [EditablePersonRef] = []
    var father: String = ""
    var mother: String = ""
    var occupations: [String] = []
    var nationality: String = ""
    var religion: String = ""

    // Metadata (not editable in main form)
    var wikiTitle: String = ""
    var wikiURL: String = ""
    var wikiExtract: String = ""
    var imageURL: String = ""

    init() {}

    init(from p: PersonData) {
        self.givenName = p.givenName ?? ""
        self.surname = p.surname ?? ""
        self.birthName = p.birthName ?? ""
        self.sex = p.sex

        self.birth = EditableEvent(from: p.birth)
        self.death = EditableEvent(from: p.death)
        self.burial = EditableEvent(from: p.burial)
        self.baptism = EditableEvent(from: p.baptism)

        self.titledPositions = p.titledPositions.map { EditableTitledPosition(from: $0) }
        self.customEvents = p.customEvents.map { EditableCustomEvent(from: $0) }
        self.personFacts = p.personFacts.map { EditablePersonFact(from: $0) }
        self.honorifics = p.honorifics
        self.spouses = p.spouses.map { EditableSpouse(from: $0) }
        self.children = p.children.map { EditablePersonRef(from: $0) }
        self.father = p.father?.name ?? ""
        self.mother = p.mother?.name ?? ""
        self.occupations = p.occupations
        self.nationality = p.nationality ?? ""
        self.religion = p.religion ?? ""

        self.wikiTitle = p.wikiTitle ?? ""
        self.wikiURL = p.wikiURL ?? ""
        self.wikiExtract = p.wikiExtract ?? ""
        self.imageURL = p.imageURL ?? ""
    }

    func toPersonData() -> PersonData {
        let fullName: String
        if givenName.isEmpty && surname.isEmpty {
            fullName = wikiTitle
        } else {
            fullName = [givenName, surname].filter { !$0.isEmpty }.joined(separator: " ")
        }

        return PersonData(
            name: fullName.isEmpty ? nil : fullName,
            givenName: givenName.isEmpty ? nil : givenName,
            surname: surname.isEmpty ? nil : surname,
            birthName: birthName.isEmpty ? nil : birthName,
            alternateNames: [],
            sex: sex,
            birth: birth.toPersonEvent(),
            death: death.toPersonEvent(),
            burial: burial.toPersonEvent(),
            baptism: baptism.toPersonEvent(),
            titledPositions: titledPositions.map { $0.toTitledPosition() },
            customEvents: customEvents.map { $0.toCustomEvent() },
            personFacts: personFacts.map { $0.toPersonFact() },
            honorifics: honorifics,
            spouses: spouses.map { $0.toSpouseInfo() },
            children: children.map { $0.toPersonRef() },
            father: father.isEmpty ? nil : PersonRef(name: father, wikiTitle: nil),
            mother: mother.isEmpty ? nil : PersonRef(name: mother, wikiTitle: nil),
            parents: [],
            occupations: occupations,
            nationality: nationality.isEmpty ? nil : nationality,
            religion: religion.isEmpty ? nil : religion,
            imageURL: imageURL.isEmpty ? nil : imageURL,
            wikiURL: wikiURL.isEmpty ? nil : wikiURL,
            wikiTitle: wikiTitle.isEmpty ? nil : wikiTitle,
            wikiExtract: wikiExtract.isEmpty ? nil : wikiExtract
        )
    }
}

// MARK: - PersonViewModel

@MainActor
final class PersonViewModel: ObservableObject {
    @Published var urlString: String = ""
    @Published var person: EditablePerson = EditablePerson()
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var hasData: Bool = false
    @Published var statusMessage: String? = nil

    func fetch() async {
        errorMessage = nil
        statusMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let pageTitle = try WikipediaClient.pageTitle(from: urlString)

            async let summaryResult = WikipediaClient.fetchSummary(pageTitle: pageTitle, verbose: false)
            async let wikitextResult = WikipediaClient.fetchWikitext(pageTitle: pageTitle, verbose: false)

            let (summary, wikitext) = try await (summaryResult, wikitextResult)

            let (parsedPerson, _) = InfoboxParser.parse(
                wikitext: wikitext,
                pageTitle: pageTitle,
                verbose: false,
                config: nil
            )

            var editable = EditablePerson(from: parsedPerson)
            editable.wikiTitle = summary.title
            if editable.wikiURL.isEmpty {
                editable.wikiURL = urlString
            }
            if let extract = summary.extract, editable.wikiExtract.isEmpty {
                editable.wikiExtract = extract
            }
            if let thumb = summary.originalimage?.source, editable.imageURL.isEmpty {
                editable.imageURL = thumb
            } else if let thumb = summary.thumbnail?.source, editable.imageURL.isEmpty {
                editable.imageURL = thumb
            }

            self.person = editable
            self.hasData = true
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func saveAsGED() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ged") ?? .data]
        panel.nameFieldStringValue = person.wikiTitle.isEmpty ? "export" : sanitizeFilename(person.wikiTitle)
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true

        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let personData = self.person.toPersonData()
                    var builder = GEDCOMBuilder()
                    let gedcom = builder.build(persons: [personData], verbose: false)
                    try gedcom.write(to: url, atomically: true, encoding: .utf8)
                    self.statusMessage = "Saved GEDCOM to \(url.lastPathComponent)"
                } catch {
                    self.statusMessage = "Error saving: \(error.localizedDescription)"
                }
            }
        }
    }

    func saveAsZip() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.zip]
        panel.nameFieldStringValue = person.wikiTitle.isEmpty ? "export" : sanitizeFilename(person.wikiTitle)
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true

        let response = await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response)
            }
        }

        guard response == .OK, let url = panel.url else { return }

        do {
            var mediaFiles: [(Data, String)] = []

            if !person.imageURL.isEmpty {
                do {
                    let (imageData, filename) = try await WikipediaClient.fetchImageData(
                        from: person.imageURL,
                        verbose: false
                    )
                    mediaFiles.append((imageData, filename))
                } catch {
                    // Non-fatal: proceed without image
                    statusMessage = "Warning: could not fetch image — \(error.localizedDescription)"
                }
            }

            let personData = person.toPersonData()
            var builder = GEDCOMBuilder()
            let gedcom = builder.build(persons: [personData], verbose: false)

            try GEDZIPBuilder.create(gedcom: gedcom, mediaFiles: mediaFiles, at: url)
            statusMessage = "Saved ZIP to \(url.lastPathComponent)"
        } catch {
            statusMessage = "Error saving ZIP: \(error.localizedDescription)"
        }
    }

    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }
}
