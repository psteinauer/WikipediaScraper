import Foundation
import WikipediaScraperCore

// MARK: - EditableEvent

public struct EditableEvent: Identifiable {
    public var id = UUID()
    public var date: String = ""
    public var place: String = ""
    public var note: String = ""
    public var cause: String = ""

    public var allEmpty: Bool {
        date.isEmpty && place.isEmpty && note.isEmpty && cause.isEmpty
    }

    public func toPersonEvent() -> PersonEvent? {
        guard !allEmpty else { return nil }
        let parsedDate = date.isEmpty ? nil : DateParser.parse(date)
        return PersonEvent(
            date: parsedDate,
            place: place.isEmpty ? nil : place,
            note: note.isEmpty ? nil : note,
            cause: cause.isEmpty ? nil : cause
        )
    }

    public init() {}

    public init(from event: PersonEvent?) {
        guard let event = event else { return }
        self.date  = event.date?.gedcom ?? ""
        self.place = event.place ?? ""
        self.note  = event.note ?? ""
        self.cause = event.cause ?? ""
    }
}

// MARK: - EditableTitledPosition

public struct EditableTitledPosition: Identifiable {
    public var id = UUID()
    public var title: String = ""
    public var startDate: String = ""
    public var endDate: String = ""
    public var place: String = ""
    public var predecessor: String = ""
    public var successor: String = ""
    public var note: String = ""

    public func toTitledPosition() -> TitledPosition {
        TitledPosition(
            title: title,
            startDate: startDate.isEmpty ? nil : DateParser.parse(startDate),
            endDate:   endDate.isEmpty   ? nil : DateParser.parse(endDate),
            place:       place.isEmpty       ? nil : place,
            predecessor: predecessor.isEmpty ? nil : predecessor,
            predecessorWikiTitle: nil,
            successor:   successor.isEmpty   ? nil : successor,
            successorWikiTitle: nil,
            note: note.isEmpty ? nil : note
        )
    }

    public init() {}

    public init(from pos: TitledPosition) {
        self.title       = pos.title
        self.startDate   = pos.startDate?.gedcom ?? ""
        self.endDate     = pos.endDate?.gedcom   ?? ""
        self.place       = pos.place       ?? ""
        self.predecessor = pos.predecessor ?? ""
        self.successor   = pos.successor   ?? ""
        self.note        = pos.note        ?? ""
    }
}

// MARK: - EditableCustomEvent

public struct EditableCustomEvent: Identifiable {
    public var id = UUID()
    public var type: String = ""
    public var date: String = ""
    public var place: String = ""
    public var note: String = ""

    public func toCustomEvent() -> CustomEvent {
        CustomEvent(
            type:  type,
            date:  date.isEmpty  ? nil : DateParser.parse(date),
            place: place.isEmpty ? nil : place,
            note:  note.isEmpty  ? nil : note
        )
    }

    public init() {}

    public init(from event: CustomEvent) {
        self.type  = event.type
        self.date  = event.date?.gedcom ?? ""
        self.place = event.place ?? ""
        self.note  = event.note  ?? ""
    }
}

// MARK: - EditablePersonFact

public struct EditablePersonFact: Identifiable {
    public var id = UUID()
    public var type: String = ""
    public var value: String = ""

    public func toPersonFact() -> PersonFact { PersonFact(type: type, value: value) }

    public init() {}

    public init(from fact: PersonFact) {
        self.type  = fact.type
        self.value = fact.value
    }
}

// MARK: - EditableSpouse

public struct EditableSpouse: Identifiable {
    public var id = UUID()
    public var name: String = ""
    public var marriageDate: String = ""
    public var marriagePlace: String = ""
    public var divorceDate: String = ""

    public func toSpouseInfo() -> SpouseInfo {
        SpouseInfo(
            name:           name,
            wikiTitle:      nil,
            marriageDate:   marriageDate.isEmpty  ? nil : DateParser.parse(marriageDate),
            marriagePlace:  marriagePlace.isEmpty ? nil : marriagePlace,
            divorceDate:    divorceDate.isEmpty   ? nil : DateParser.parse(divorceDate)
        )
    }

    public init() {}

    public init(from spouse: SpouseInfo) {
        self.name          = spouse.name
        self.marriageDate  = spouse.marriageDate?.gedcom  ?? ""
        self.marriagePlace = spouse.marriagePlace         ?? ""
        self.divorceDate   = spouse.divorceDate?.gedcom   ?? ""
    }
}

// MARK: - EditablePersonRef

public struct EditablePersonRef: Identifiable {
    public var id = UUID()
    public var name: String = ""

    public func toPersonRef() -> PersonRef { PersonRef(name: name, wikiTitle: nil) }

    public init() {}

    public init(from ref: PersonRef) { self.name = ref.name }
}

// MARK: - EditableMediaItem

public struct EditableMediaItem: Identifiable {
    public var id = UUID()
    /// Remote URL used both to preview the image and as the source when building a ZIP.
    public var url: String = ""
    /// Human-readable caption written into the GEDCOM FILE/TITL tag.
    public var caption: String = ""

    public func toAdditionalMedia() -> AdditionalMedia {
        AdditionalMedia(
            filePath: url,
            origURL:  url.isEmpty     ? nil : url,
            title:    caption.isEmpty ? nil : caption,
            mimeType: nil
        )
    }

    public init() {}

    public init(from media: AdditionalMedia) {
        self.url     = media.origURL ?? media.filePath
        self.caption = media.title ?? ""
    }
}

// MARK: - EditablePerson

public struct EditablePerson {
    public var givenName: String = ""
    public var surname: String = ""
    public var birthName: String = ""
    public var sex: Sex = .unknown

    public var birth:   EditableEvent = EditableEvent()
    public var death:   EditableEvent = EditableEvent()
    public var burial:  EditableEvent = EditableEvent()
    public var baptism: EditableEvent = EditableEvent()

    public var titledPositions: [EditableTitledPosition] = []
    public var customEvents:    [EditableCustomEvent]    = []
    public var personFacts:     [EditablePersonFact]     = []
    public var honorifics:      [String]                 = []
    public var spouses:         [EditableSpouse]         = []
    public var children:        [EditablePersonRef]      = []
    public var father: String = ""
    public var mother: String = ""
    public var occupations: [String] = []
    public var nationality: String = ""
    public var religion: String = ""

    // ── Media ──────────────────────────────────────────────────────────────
    public var imageURL: String = ""
    public var additionalMedia: [EditableMediaItem] = []

    // ── Metadata (shown read-only) ─────────────────────────────────────────
    public var wikiTitle:   String = ""
    public var wikiURL:     String = ""
    public var wikiExtract: String = ""

    public init() {}

    public init(from p: PersonData) {
        self.givenName = p.givenName ?? ""
        self.surname   = p.surname   ?? ""
        self.birthName = p.birthName ?? ""
        self.sex       = p.sex

        self.birth   = EditableEvent(from: p.birth)
        self.death   = EditableEvent(from: p.death)
        self.burial  = EditableEvent(from: p.burial)
        self.baptism = EditableEvent(from: p.baptism)

        self.titledPositions = p.titledPositions.map { EditableTitledPosition(from: $0) }
        self.customEvents    = p.customEvents.map    { EditableCustomEvent(from: $0) }
        self.personFacts     = p.personFacts.map     { EditablePersonFact(from: $0) }
        self.honorifics      = p.honorifics
        self.spouses         = p.spouses.map         { EditableSpouse(from: $0) }
        self.children        = p.children.map        { EditablePersonRef(from: $0) }
        self.father          = p.father?.name ?? ""
        self.mother          = p.mother?.name ?? ""
        self.occupations     = p.occupations
        self.nationality     = p.nationality ?? ""
        self.religion        = p.religion    ?? ""

        self.imageURL        = p.imageURL ?? ""
        self.additionalMedia = p.additionalMedia.map { EditableMediaItem(from: $0) }

        self.wikiTitle   = p.wikiTitle   ?? ""
        self.wikiURL     = p.wikiURL     ?? ""
        self.wikiExtract = p.wikiExtract ?? ""
    }

    public func toPersonData() -> PersonData {
        let fullName: String
        if givenName.isEmpty && surname.isEmpty {
            fullName = wikiTitle
        } else {
            fullName = [givenName, surname].filter { !$0.isEmpty }.joined(separator: " ")
        }

        var p = PersonData()
        p.name            = fullName.isEmpty ? nil : fullName
        p.givenName       = givenName.isEmpty ? nil : givenName
        p.surname         = surname.isEmpty   ? nil : surname
        p.birthName       = birthName.isEmpty ? nil : birthName
        p.sex             = sex
        p.birth           = birth.toPersonEvent()
        p.death           = death.toPersonEvent()
        p.burial          = burial.toPersonEvent()
        p.baptism         = baptism.toPersonEvent()
        p.titledPositions = titledPositions.map { $0.toTitledPosition() }
        p.customEvents    = customEvents.map    { $0.toCustomEvent() }
        p.personFacts     = personFacts.map     { $0.toPersonFact() }
        p.honorifics      = honorifics
        p.spouses         = spouses.map         { $0.toSpouseInfo() }
        p.children        = children.map        { $0.toPersonRef() }
        p.father          = father.isEmpty ? nil : PersonRef(name: father, wikiTitle: nil)
        p.mother          = mother.isEmpty ? nil : PersonRef(name: mother, wikiTitle: nil)
        p.occupations     = occupations
        p.nationality     = nationality.isEmpty ? nil : nationality
        p.religion        = religion.isEmpty    ? nil : religion
        p.imageURL        = imageURL.isEmpty    ? nil : imageURL
        p.additionalMedia = additionalMedia.map { $0.toAdditionalMedia() }
        p.wikiURL         = wikiURL.isEmpty     ? nil : wikiURL
        p.wikiTitle       = wikiTitle.isEmpty   ? nil : wikiTitle
        p.wikiExtract     = wikiExtract.isEmpty ? nil : wikiExtract
        return p
    }
}
