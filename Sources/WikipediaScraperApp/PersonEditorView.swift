import SwiftUI
import WikipediaScraperCore

// MARK: - EventSectionContent

struct EventSectionContent: View {
    @Binding var event: EditableEvent
    var showCause: Bool = false

    var body: some View {
        LabeledContent("Date") {
            TextField("e.g. 24 MAY 1819", text: $event.date)
        }
        LabeledContent("Place") {
            TextField("City, Country", text: $event.place)
        }
        if showCause {
            LabeledContent("Cause") {
                TextField("Cause of death", text: $event.cause)
            }
        }
        LabeledContent("Note") {
            TextField("Additional note", text: $event.note)
        }
    }
}

// MARK: - MediaThumbnail

private struct MediaThumbnail: View {
    let urlString: String
    var width: CGFloat = 72
    var height: CGFloat = 90

    var body: some View {
        Group {
            if let url = URL(string: urlString), !urlString.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderIcon("photo.badge.exclamationmark")
                    case .empty:
                        ProgressView().controlSize(.small)
                    @unknown default:
                        placeholderIcon("photo")
                    }
                }
            } else {
                placeholderIcon("photo")
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
        }
    }

    private func placeholderIcon(_ name: String) -> some View {
        ZStack {
            Color(NSColor.unemphasizedSelectedContentBackgroundColor)
            Image(systemName: name)
                .foregroundStyle(.tertiary)
                .imageScale(.large)
        }
    }
}

// MARK: - PersonEditorView

struct PersonEditorView: View {
    @Binding var person: EditablePerson

    var body: some View {
        Form {
            identitySection
            mediaSection
            birthSection
            deathSection
            burialSection
            baptismSection
            titledPositionsSection
            customEventsSection
            personFactsSection
            honorificsSection
            spousesSection
            childrenSection
            parentsSection
            occupationsSection
            otherSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Identity

    private var identitySection: some View {
        Section("Identity") {
            LabeledContent("Wikipedia Title") {
                Text(person.wikiTitle.isEmpty ? "—" : person.wikiTitle)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            LabeledContent("Given Name") {
                TextField("Given name(s)", text: $person.givenName)
            }
            LabeledContent("Surname") {
                TextField("Family name", text: $person.surname)
            }
            LabeledContent("Birth Name") {
                TextField("Name at birth (if different)", text: $person.birthName)
            }
            LabeledContent("Sex") {
                Picker("", selection: $person.sex) {
                    Text("Unknown").tag(Sex.unknown)
                    Text("Male").tag(Sex.male)
                    Text("Female").tag(Sex.female)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
            }
        }
    }

    // MARK: - Media

    private var mediaSection: some View {
        Section("Media") {
            // Primary image
            HStack(alignment: .top, spacing: 14) {
                MediaThumbnail(urlString: person.imageURL, width: 72, height: 90)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Primary Image")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://upload.wikimedia.org/…", text: $person.imageURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)

            // Additional media items
            ForEach($person.additionalMedia) { $item in
                HStack(alignment: .top, spacing: 14) {
                    MediaThumbnail(urlString: item.url, width: 56, height: 70)

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Image URL", text: $item.url)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        TextField("Caption (optional)", text: $item.caption)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        person.additionalMedia.removeAll { $0.id == item.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }

            Button {
                person.additionalMedia.append(EditableMediaItem())
            } label: {
                Label("Add Media", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Life Events

    private var birthSection: some View {
        Section("Birth") {
            EventSectionContent(event: $person.birth)
        }
    }

    private var deathSection: some View {
        Section("Death") {
            EventSectionContent(event: $person.death, showCause: true)
        }
    }

    private var burialSection: some View {
        Section("Burial") {
            EventSectionContent(event: $person.burial)
        }
    }

    private var baptismSection: some View {
        Section("Baptism") {
            EventSectionContent(event: $person.baptism)
        }
    }

    // MARK: - Titled Positions

    private var titledPositionsSection: some View {
        Section("Titled Positions") {
            ForEach($person.titledPositions) { $pos in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent("Title") {
                                TextField("e.g. Queen of the United Kingdom", text: $pos.title)
                            }
                            LabeledContent("From") {
                                TextField("Start date", text: $pos.startDate)
                            }
                            LabeledContent("To") {
                                TextField("End date", text: $pos.endDate)
                            }
                            LabeledContent("Place") {
                                TextField("Place", text: $pos.place)
                            }
                            LabeledContent("Preceded by") {
                                TextField("Predecessor's name", text: $pos.predecessor)
                            }
                            LabeledContent("Succeeded by") {
                                TextField("Successor's name", text: $pos.successor)
                            }
                            LabeledContent("Note") {
                                TextField("Note", text: $pos.note)
                            }
                        }
                        Button {
                            person.titledPositions.removeAll { $0.id == pos.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    Divider()
                }
            }
            Button {
                person.titledPositions.append(EditableTitledPosition())
            } label: {
                Label("Add Position", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Custom Events

    private var customEventsSection: some View {
        Section("Custom Events") {
            ForEach($person.customEvents) { $event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent("Event Type") {
                                TextField("e.g. Coronation, Inauguration", text: $event.type)
                            }
                            LabeledContent("Date") {
                                TextField("e.g. 28 JUN 1838", text: $event.date)
                            }
                            LabeledContent("Place") {
                                TextField("Place", text: $event.place)
                            }
                            LabeledContent("Note") {
                                TextField("Note", text: $event.note)
                            }
                        }
                        Button {
                            person.customEvents.removeAll { $0.id == event.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    Divider()
                }
            }
            Button {
                person.customEvents.append(EditableCustomEvent())
            } label: {
                Label("Add Event", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Person Facts

    private var personFactsSection: some View {
        Section("Facts") {
            ForEach($person.personFacts) { $fact in
                HStack(spacing: 8) {
                    TextField("Fact type (e.g. House, Award)", text: $fact.type)
                        .frame(maxWidth: 200)
                    Divider().frame(height: 18)
                    TextField("Value", text: $fact.value)
                    Button {
                        person.personFacts.removeAll { $0.id == fact.id }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                person.personFacts.append(EditablePersonFact())
            } label: {
                Label("Add Fact", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Honorifics

    private var honorificsSection: some View {
        Section("Honorifics & Titles") {
            ForEach(person.honorifics.indices, id: \.self) { index in
                HStack {
                    TextField("e.g. Sir, The Right Honourable", text: $person.honorifics[index])
                    Button {
                        person.honorifics.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                person.honorifics.append("")
            } label: {
                Label("Add Honorific", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Spouses

    private var spousesSection: some View {
        Section("Spouses") {
            ForEach($person.spouses) { $spouse in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent("Name") {
                                TextField("Spouse's full name", text: $spouse.name)
                            }
                            LabeledContent("Married") {
                                TextField("Marriage date", text: $spouse.marriageDate)
                            }
                            LabeledContent("At") {
                                TextField("Marriage place", text: $spouse.marriagePlace)
                            }
                            LabeledContent("Divorced") {
                                TextField("Divorce date (if applicable)", text: $spouse.divorceDate)
                            }
                        }
                        Button {
                            person.spouses.removeAll { $0.id == spouse.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    Divider()
                }
            }
            Button {
                person.spouses.append(EditableSpouse())
            } label: {
                Label("Add Spouse", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Children

    private var childrenSection: some View {
        Section("Children") {
            ForEach($person.children) { $child in
                HStack {
                    TextField("Child's full name", text: $child.name)
                    Button {
                        person.children.removeAll { $0.id == child.id }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                person.children.append(EditablePersonRef())
            } label: {
                Label("Add Child", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Parents

    private var parentsSection: some View {
        Section("Parents") {
            LabeledContent("Father") {
                TextField("Father's full name", text: $person.father)
            }
            LabeledContent("Mother") {
                TextField("Mother's full name", text: $person.mother)
            }
        }
    }

    // MARK: - Occupations

    private var occupationsSection: some View {
        Section("Occupations") {
            ForEach(person.occupations.indices, id: \.self) { index in
                HStack {
                    TextField("e.g. Monarch, Statesman", text: $person.occupations[index])
                    Button {
                        person.occupations.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                person.occupations.append("")
            } label: {
                Label("Add Occupation", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Other

    private var otherSection: some View {
        Section("Other") {
            LabeledContent("Nationality") {
                TextField("e.g. British", text: $person.nationality)
            }
            LabeledContent("Religion") {
                TextField("e.g. Church of England", text: $person.religion)
            }
        }
    }
}
