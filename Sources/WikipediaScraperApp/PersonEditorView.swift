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
            TextField("Place", text: $event.place)
        }
        if showCause {
            LabeledContent("Cause") {
                TextField("Cause of death", text: $event.cause)
            }
        }
        LabeledContent("Note") {
            TextField("Note", text: $event.note)
        }
    }
}

// MARK: - PersonEditorView

struct PersonEditorView: View {
    @Binding var person: EditablePerson

    var body: some View {
        Form {
            // MARK: Identity
            Section("Identity") {
                LabeledContent("Wikipedia Title") {
                    Text(person.wikiTitle.isEmpty ? "—" : person.wikiTitle)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Given Name") {
                    TextField("Given name", text: $person.givenName)
                }
                LabeledContent("Surname") {
                    TextField("Surname", text: $person.surname)
                }
                LabeledContent("Birth Name") {
                    TextField("Birth name / name at birth", text: $person.birthName)
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

            // MARK: Birth
            Section("Birth") {
                EventSectionContent(event: $person.birth, showCause: false)
            }

            // MARK: Death
            Section("Death") {
                EventSectionContent(event: $person.death, showCause: true)
            }

            // MARK: Burial
            Section("Burial") {
                EventSectionContent(event: $person.burial, showCause: false)
            }

            // MARK: Baptism
            Section("Baptism") {
                EventSectionContent(event: $person.baptism, showCause: false)
            }

            // MARK: Titled Positions
            Section("Titled Positions") {
                ForEach($person.titledPositions) { $pos in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                LabeledContent("Title") {
                                    TextField("Title", text: $pos.title)
                                }
                                LabeledContent("Start Date") {
                                    TextField("Start date", text: $pos.startDate)
                                }
                                LabeledContent("End Date") {
                                    TextField("End date", text: $pos.endDate)
                                }
                                LabeledContent("Place") {
                                    TextField("Place", text: $pos.place)
                                }
                                LabeledContent("Predecessor") {
                                    TextField("Predecessor", text: $pos.predecessor)
                                }
                                LabeledContent("Successor") {
                                    TextField("Successor", text: $pos.successor)
                                }
                                LabeledContent("Note") {
                                    TextField("Note", text: $pos.note)
                                }
                            }

                            Button {
                                person.titledPositions.removeAll { $0.id == pos.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
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

            // MARK: Custom Events
            Section("Custom Events") {
                ForEach($person.customEvents) { $event in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                LabeledContent("Type") {
                                    TextField("Event type", text: $event.type)
                                }
                                LabeledContent("Date") {
                                    TextField("Date", text: $event.date)
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
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
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

            // MARK: Person Facts
            Section("Person Facts") {
                ForEach($person.personFacts) { $fact in
                    HStack {
                        TextField("Type", text: $fact.type)
                            .frame(maxWidth: 160)
                        TextField("Value", text: $fact.value)

                        Button {
                            person.personFacts.removeAll { $0.id == fact.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
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

            // MARK: Honorifics
            Section("Honorifics") {
                ForEach(person.honorifics.indices, id: \.self) { index in
                    HStack {
                        TextField("Honorific", text: $person.honorifics[index])

                        Button {
                            person.honorifics.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
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

            // MARK: Spouses
            Section("Spouses") {
                ForEach($person.spouses) { $spouse in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                LabeledContent("Name") {
                                    TextField("Spouse's name", text: $spouse.name)
                                }
                                LabeledContent("Marriage Date") {
                                    TextField("Marriage date", text: $spouse.marriageDate)
                                }
                                LabeledContent("Marriage Place") {
                                    TextField("Marriage place", text: $spouse.marriagePlace)
                                }
                                LabeledContent("Divorce Date") {
                                    TextField("Divorce date", text: $spouse.divorceDate)
                                }
                            }

                            Button {
                                person.spouses.removeAll { $0.id == spouse.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
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

            // MARK: Children
            Section("Children") {
                ForEach($person.children) { $child in
                    HStack {
                        TextField("Child's name", text: $child.name)

                        Button {
                            person.children.removeAll { $0.id == child.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
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

            // MARK: Parents
            Section("Parents") {
                LabeledContent("Father") {
                    TextField("Father's name", text: $person.father)
                }
                LabeledContent("Mother") {
                    TextField("Mother's name", text: $person.mother)
                }
            }

            // MARK: Occupations
            Section("Occupations") {
                ForEach(person.occupations.indices, id: \.self) { index in
                    HStack {
                        TextField("Occupation", text: $person.occupations[index])

                        Button {
                            person.occupations.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
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

            // MARK: Other
            Section("Other") {
                LabeledContent("Nationality") {
                    TextField("", text: $person.nationality)
                }
                LabeledContent("Religion") {
                    TextField("", text: $person.religion)
                }
            }
        }
        .formStyle(.grouped)
    }
}
