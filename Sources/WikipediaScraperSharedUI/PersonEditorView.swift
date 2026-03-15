import SwiftUI
import WikipediaScraperCore

// MARK: - Platform colour helpers

#if os(macOS)
import AppKit
private var separatorColor: Color    { Color(NSColor.separatorColor) }
private var thumbnailBGColor: Color  { Color(NSColor.unemphasizedSelectedContentBackgroundColor) }
#else
import UIKit
private var separatorColor: Color    { Color(UIColor.separator) }
private var thumbnailBGColor: Color  { Color(UIColor.secondarySystemBackground) }
#endif

// MARK: - FieldRow
//
// MacFamilyTree-style two-column field row: right-aligned label at a fixed
// width, content fills the remainder.  An optional inset divider separates
// rows; pass showDivider: false on the last row in a group.

private let editorLabelWidth: CGFloat = 120

private struct FieldRow<Content: View>: View {
    let label: String
    let showDivider: Bool
    let content: Content

    init(_ label: String, showDivider: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.label       = label
        self.showDivider = showDivider
        self.content     = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: editorLabelWidth, alignment: .trailing)
                content
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 7)
            if showDivider {
                Divider()
                    .padding(.leading, editorLabelWidth + 10)
            }
        }
    }
}

// MARK: - EventSectionContent

public struct EventSectionContent: View {
    @Binding public var event: EditableEvent
    public var showCause: Bool = false

    public init(event: Binding<EditableEvent>, showCause: Bool = false) {
        self._event    = event
        self.showCause = showCause
    }

    public var body: some View {
        FieldRow("Date")  { TextField("e.g. 24 MAY 1819", text: $event.date) }
        FieldRow("Place") { TextField("City, Country",    text: $event.place) }
        if showCause {
            FieldRow("Cause") { TextField("Cause of death", text: $event.cause) }
        }
        FieldRow("Note", showDivider: false) {
            TextField("Additional note", text: $event.note)
        }
    }
}

// MARK: - Image cache

/// Simple NSCache-backed singleton that stores decoded platform images.
/// NSCache is thread-safe; storing platform images avoids re-decoding on every hit.
private final class ImageCache {
    static let shared = ImageCache()

    private final class Box: NSObject {
        #if os(macOS)
        let image: NSImage
        init(_ img: NSImage) { image = img }
        var swiftUI: Image { Image(nsImage: image) }
        #else
        let image: UIImage
        init(_ img: UIImage) { image = img }
        var swiftUI: Image { Image(uiImage: image) }
        #endif
    }

    private let cache = NSCache<NSString, Box>()
    private init() { cache.countLimit = 300 }

    func get(_ url: String) -> Image? {
        cache.object(forKey: url as NSString)?.swiftUI
    }

    func store(_ data: Data, for url: String) {
        #if os(macOS)
        if let img = NSImage(data: data) {
            cache.setObject(Box(img), forKey: url as NSString)
        }
        #else
        if let img = UIImage(data: data) {
            cache.setObject(Box(img), forKey: url as NSString)
        }
        #endif
    }
}

// MARK: - MediaThumbnail

public struct MediaThumbnail: View {
    public let urlString: String
    public var width: CGFloat  = 72
    public var height: CGFloat = 90

    private enum Phase { case idle, loading, success(Image), failure }
    @State private var phase: Phase = .idle

    public init(urlString: String, width: CGFloat = 72, height: CGFloat = 90) {
        self.urlString = urlString
        self.width = width
        self.height = height
    }

    public var body: some View {
        Group {
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure:
                placeholderIcon("photo.badge.exclamationmark")
            case .loading, .idle:
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(separatorColor, lineWidth: 0.5)
        }
        // Re-runs whenever urlString changes or the view first appears.
        // SwiftUI cancels the prior task automatically when the id changes.
        .task(id: urlString) { await load() }
    }

    @MainActor
    private func load() async {
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            phase = .failure
            return
        }
        // Instant cache hit — no network round-trip needed.
        if let cached = ImageCache.shared.get(urlString) {
            phase = .success(cached)
            return
        }
        phase = .loading
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            // Guard against cancellation after the await resumes.
            try Task.checkCancellation()
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                phase = .failure
                return
            }
            ImageCache.shared.store(data, for: urlString)
            if let img = ImageCache.shared.get(urlString) {
                phase = .success(img)
            } else {
                phase = .failure
            }
        } catch is CancellationError {
            // Person changed before load finished — reset to idle so that if
            // we navigate back to this URL the task re-runs cleanly.
            phase = .idle
        } catch {
            phase = .failure
        }
    }

    private func placeholderIcon(_ name: String) -> some View {
        ZStack {
            thumbnailBGColor
            Image(systemName: name)
                .foregroundStyle(.tertiary)
                .imageScale(.large)
        }
    }
}

// MARK: - PrimaryImagePopover

private struct PrimaryImagePopover: View {
    @Binding var imageURL: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MediaThumbnail(urlString: imageURL, width: 160, height: 200)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 4) {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                Text("Primary Image").font(.caption2).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("URL").font(.caption2).foregroundStyle(.secondary)
                TextField("https://…", text: $imageURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
            }

            HStack {
                Spacer()
                Button(role: .destructive) { imageURL = "" } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .font(.callout)
            }
        }
        .padding(14)
        .frame(width: 240)
    }
}

// MARK: - PrimaryImageCell

private struct PrimaryImageCell: View {
    @Binding var imageURL: String
    @State private var showingPopover = false
    @State private var isHovered = false

    var body: some View {
        MediaThumbnail(urlString: imageURL, width: 88, height: 110)
            .overlay(alignment: .topLeading) {
                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.yellow)
                    .padding(3)
                    .background(.black.opacity(0.45))
                    .clipShape(Circle())
                    .padding(5)
            }
            .overlay {
                if isHovered {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .scaleEffect(isHovered ? 1.04 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isHovered)
            #if os(macOS)
            .onHover { hovering in
                isHovered = hovering
                if hovering { showingPopover = true }
            }
            .onTapGesture { showingPopover = true }
            #else
            .onTapGesture { showingPopover.toggle() }
            #endif
            .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
                PrimaryImagePopover(imageURL: $imageURL)
            }
    }
}

// MARK: - MediaItemPopover

private struct MediaItemPopover: View {
    @Binding var item: EditableMediaItem
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MediaThumbnail(urlString: item.url, width: 160, height: 200)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("URL").font(.caption2).foregroundStyle(.secondary)
                    TextField("https://…", text: $item.url)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        #if os(iOS)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Caption").font(.caption2).foregroundStyle(.secondary)
                    TextField("Optional caption", text: $item.caption)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
            }

            HStack {
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .font(.callout)
            }
        }
        .padding(14)
        .frame(width: 240)
    }
}

// MARK: - MediaGridCell

private struct MediaGridCell: View {
    @Binding var item: EditableMediaItem
    @Binding var isShowingPopover: Bool
    let onTap:    () -> Void   // macOS: tap opens the edit popover
    let onHover:  (Bool) -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        MediaThumbnail(urlString: item.url, width: 88, height: 110)
            .overlay(alignment: .bottom) {
                if !item.caption.isEmpty {
                    Text(item.caption)
                        .font(.system(size: 9))
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.55))
                        .foregroundStyle(.white)
                }
            }
            .overlay {
                if isHovered {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .scaleEffect(isHovered ? 1.04 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isHovered)
            #if os(macOS)
            .onHover { hovering in
                isHovered = hovering
                onHover(hovering)
            }
            .onTapGesture { onTap() }
            #else
            .onTapGesture { isShowingPopover.toggle() }
            #endif
            .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
                MediaItemPopover(item: $item, onRemove: onRemove)
            }
    }
}

// MARK: - EditorSection
//
// MacFamilyTree-style card: coloured SF Symbol + bold title header with a
// disclosure chevron.  When expanded, shows content inside a white (or dark)
// rounded-rectangle card with a subtle shadow and 0.5 pt border.

private struct EditorSection<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    let content: Content

    init(_ title: String, systemImage: String,
         isExpanded: Binding<Bool>,
         @ViewBuilder content: () -> Content) {
        self.title       = title
        self.systemImage = systemImage
        self._isExpanded = isExpanded
        self.content     = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button { isExpanded.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .foregroundStyle(Color.accentColor)
                        .imageScale(.small)
                        .frame(width: 20, alignment: .center)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.18), value: isExpanded)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            if isExpanded {
                Divider()
                content
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .transition(.opacity)
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
    }

    #if os(macOS)
    private var cardBackground: Color { Color(NSColor.controlBackgroundColor) }
    #else
    private var cardBackground: Color { Color(UIColor.secondarySystemGroupedBackground) }
    #endif
}

// MARK: - SubGroup
//
// Second-level collapsible group inside an EditorSection.
// The header sits flush with the section content; content is indented 18 pt.

private struct SubGroup<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    let content: Content

    init(title: String, systemImage: String,
         isExpanded: Binding<Bool>,
         @ViewBuilder content: () -> Content) {
        self.title       = title
        self.systemImage = systemImage
        self._isExpanded = isExpanded
        self.content     = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.15), value: isExpanded)
                        .frame(width: 10)
                    Label(title, systemImage: systemImage)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 7)

            if isExpanded {
                content
                    .padding(.leading, 18)
                    .padding(.bottom, 6)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - MediaGrid (unified: primary first with star, then additional)

private struct MediaGrid: View {
    @Binding var imageURL: String
    @Binding var items: [EditableMediaItem]

    @State private var popoverItemID: UUID? = nil

    private let columns = [GridItem(.adaptive(minimum: 88, maximum: 120), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            if !imageURL.isEmpty {
                PrimaryImageCell(imageURL: $imageURL)
            }
            ForEach($items) { $item in
                MediaGridCell(
                    item: $item,
                    isShowingPopover: Binding(
                        get: { popoverItemID == item.id },
                        set: { if !$0 { popoverItemID = nil } }
                    ),
                    onTap:    { popoverItemID = item.id },
                    onHover:  { hovering in if hovering { popoverItemID = item.id } },
                    onRemove: {
                        items.removeAll { $0.id == item.id }
                        popoverItemID = nil
                    }
                )
            }
        }
    }
}

// MARK: - PersonEditorView

public struct PersonEditorView: View {
    @Binding public var person: EditablePerson

    private static let topLevelSections = [
        "Name and Gender", "Events", "Facts", "Additional Names",
        "Media", "Notes", "Sources", "Other"
    ]

    @State private var expandedSections: Set<String> = {
        var s = Set(PersonEditorView.topLevelSections)
        s.formUnion([
            "Events.Birth", "Events.Death", "Events.Burial", "Events.Baptism",
            "Events.Spouses", "Events.TitledPositions", "Events.CustomEvents",
            "Facts.Honorifics", "Facts.Custom", "Facts.Occupations", "Facts.Attributes",
            "Other.Parents", "Other.Children",
        ])
        return s
    }()

    public init(person: Binding<EditablePerson>) {
        self._person = person
    }

    private func isExpanded(_ section: String) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(section) },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    #if os(macOS)
                    let optionDown = NSEvent.modifierFlags.contains(.option)
                    #else
                    let optionDown = false
                    #endif
                    if optionDown && PersonEditorView.topLevelSections.contains(section) {
                        if newValue {
                            expandedSections.formUnion(PersonEditorView.topLevelSections)
                        } else {
                            expandedSections.subtract(PersonEditorView.topLevelSections)
                        }
                    } else {
                        if newValue { expandedSections.insert(section) }
                        else        { expandedSections.remove(section) }
                    }
                }
            }
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    nameAndGenderSection
                    if !person.imageURL.isEmpty {
                        MediaThumbnail(urlString: person.imageURL, width: 84, height: 106)
                    }
                }
                eventsSection
                factsSection
                additionalNamesSection
                mediaSection
                notesSection
                sourcesSection
                otherSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - AI Generated label

    private var aiGeneratedLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "wand.and.stars").imageScale(.small)
            Text("AI Generated")
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    // MARK: - Name and Gender

    private var nameAndGenderSection: some View {
        EditorSection("Name and Gender", systemImage: "person.text.rectangle",
                      isExpanded: isExpanded("Name and Gender")) {
            FieldRow("Wikipedia Title") {
                Text(person.wikiTitle.isEmpty ? "—" : person.wikiTitle)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            FieldRow("Given Name") { TextField("Given name(s)", text: $person.givenName) }
            FieldRow("Surname")    { TextField("Family name",   text: $person.surname) }
            FieldRow("Sex", showDivider: false) {
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

    // MARK: - Events

    private var eventsSection: some View {
        EditorSection("Events", systemImage: "calendar.badge.clock",
                      isExpanded: isExpanded("Events")) {
            SubGroup(title: "Birth", systemImage: "calendar",
                     isExpanded: isExpanded("Events.Birth")) {
                EventSectionContent(event: $person.birth)
            }
            Divider()
            SubGroup(title: "Death", systemImage: "leaf",
                     isExpanded: isExpanded("Events.Death")) {
                EventSectionContent(event: $person.death, showCause: true)
            }
            Divider()
            SubGroup(title: "Burial", systemImage: "mappin",
                     isExpanded: isExpanded("Events.Burial")) {
                EventSectionContent(event: $person.burial)
            }
            Divider()
            SubGroup(title: "Baptism", systemImage: "drop.fill",
                     isExpanded: isExpanded("Events.Baptism")) {
                EventSectionContent(event: $person.baptism)
            }
            Divider()
            SubGroup(title: "Spouses", systemImage: "person.2",
                     isExpanded: isExpanded("Events.Spouses")) {
                ForEach($person.spouses) { $spouse in
                    FieldRow("Name")    { TextField("Spouse's full name",            text: $spouse.name) }
                    FieldRow("Married") { TextField("Marriage date",                 text: $spouse.marriageDate) }
                    FieldRow("At")      { TextField("Marriage place",                text: $spouse.marriagePlace) }
                    FieldRow("Divorced") { TextField("Divorce date (if applicable)", text: $spouse.divorceDate) }
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            person.spouses.removeAll { $0.id == spouse.id }
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                                .font(.caption).foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.bottom, 4)
                    Divider()
                }
                Button { person.spouses.append(EditableSpouse()) } label: {
                    Label("Add Spouse", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
            Divider()
            SubGroup(title: "Titled Positions", systemImage: "crown",
                     isExpanded: isExpanded("Events.TitledPositions")) {
                ForEach($person.titledPositions) { $pos in
                    FieldRow("Title")        { TextField("e.g. Queen of the United Kingdom", text: $pos.title) }
                    FieldRow("From")         { TextField("Start date",         text: $pos.startDate) }
                    FieldRow("To")           { TextField("End date",           text: $pos.endDate) }
                    FieldRow("Place")        { TextField("Place",              text: $pos.place) }
                    FieldRow("Preceded by")  { TextField("Predecessor's name", text: $pos.predecessor) }
                    FieldRow("Succeeded by") { TextField("Successor's name",   text: $pos.successor) }
                    FieldRow("Note")         { TextField("Note",               text: $pos.note) }
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            person.titledPositions.removeAll { $0.id == pos.id }
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                                .font(.caption).foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.bottom, 4)
                    Divider()
                }
                Button { person.titledPositions.append(EditableTitledPosition()) } label: {
                    Label("Add Position", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
            Divider()
            SubGroup(title: "Custom Events", systemImage: "calendar.badge.clock",
                     isExpanded: isExpanded("Events.CustomEvents")) {
                ForEach($person.customEvents) { $event in
                    FieldRow("Event Type") { TextField("e.g. Coronation, Inauguration", text: $event.type) }
                    FieldRow("Date")       { TextField("e.g. 28 JUN 1838",             text: $event.date) }
                    FieldRow("Place")      { TextField("Place",                         text: $event.place) }
                    FieldRow("Note")       { TextField("Note",                          text: $event.note) }
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            person.customEvents.removeAll { $0.id == event.id }
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                                .font(.caption).foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.bottom, 4)
                    Divider()
                }
                Button { person.customEvents.append(EditableCustomEvent()) } label: {
                    Label("Add Event", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
            if !person.llmEvents.isEmpty {
                Divider()
                aiGeneratedLabel
                ForEach(person.llmEvents, id: \.type) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.type).fontWeight(.medium).font(.subheadline)
                        if let date  = event.date  { Text(date.gedcom).font(.caption).foregroundStyle(.secondary) }
                        if let place = event.place { Text(place).font(.caption).foregroundStyle(.secondary) }
                        if let note  = event.note  { Text(note).font(.caption).foregroundStyle(.tertiary) }
                    }
                    .padding(.vertical, 5)
                    .padding(.leading, 22)
                    Divider().padding(.leading, 22)
                }
            }
        }
    }

    // MARK: - Facts

    private var factsSection: some View {
        EditorSection("Facts", systemImage: "list.bullet",
                      isExpanded: isExpanded("Facts")) {
            SubGroup(title: "Honorifics & Titles", systemImage: "textformat",
                     isExpanded: isExpanded("Facts.Honorifics")) {
                ForEach(person.honorifics.indices, id: \.self) { index in
                    HStack {
                        TextField("e.g. Sir, The Right Honourable",
                                  text: $person.honorifics[index])
                            .textFieldStyle(.plain)
                        Button { person.honorifics.remove(at: index) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 5)
                    Divider()
                }
                Button { person.honorifics.append("") } label: {
                    Label("Add Honorific", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
                if !person.llmTitles.isEmpty {
                    Divider()
                    aiGeneratedLabel
                    FieldRow("Additional Titles", showDivider: false) {
                        Text(person.llmTitles.joined(separator: ", "))
                            .foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            Divider()
            SubGroup(title: "Custom Facts", systemImage: "list.bullet",
                     isExpanded: isExpanded("Facts.Custom")) {
                ForEach($person.personFacts) { $fact in
                    HStack(spacing: 8) {
                        TextField("Type (e.g. House, Award)", text: $fact.type)
                            .textFieldStyle(.plain).frame(maxWidth: 160)
                        Text("·").foregroundStyle(.tertiary)
                        TextField("Value", text: $fact.value).textFieldStyle(.plain)
                        Button { person.personFacts.removeAll { $0.id == fact.id } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 5)
                    Divider()
                }
                Button { person.personFacts.append(EditablePersonFact()) } label: {
                    Label("Add Fact", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
                if !person.llmFacts.isEmpty {
                    Divider()
                    aiGeneratedLabel
                    ForEach(person.llmFacts, id: \.type) { fact in
                        FieldRow(fact.type, showDivider: false) {
                            Text(fact.value).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
            }
            Divider()
            SubGroup(title: "Occupations", systemImage: "briefcase",
                     isExpanded: isExpanded("Facts.Occupations")) {
                ForEach(person.occupations.indices, id: \.self) { index in
                    HStack {
                        TextField("e.g. Monarch, Statesman",
                                  text: $person.occupations[index])
                            .textFieldStyle(.plain)
                        Button { person.occupations.remove(at: index) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 5)
                    Divider()
                }
                Button { person.occupations.append("") } label: {
                    Label("Add Occupation", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
            Divider()
            SubGroup(title: "Attributes", systemImage: "tag",
                     isExpanded: isExpanded("Facts.Attributes")) {
                FieldRow("Nationality") { TextField("e.g. British",               text: $person.nationality) }
                FieldRow("Religion", showDivider: false) {
                    TextField("e.g. Church of England", text: $person.religion)
                }
            }
        }
    }

    // MARK: - Additional Names

    private var additionalNamesSection: some View {
        EditorSection("Additional Names", systemImage: "person.badge.plus",
                      isExpanded: isExpanded("Additional Names")) {
            FieldRow("Birth Name",
                     showDivider: !person.llmAlternateNames.isEmpty) {
                TextField("Name at birth (if different)", text: $person.birthName)
            }
            if !person.llmAlternateNames.isEmpty {
                aiGeneratedLabel
                FieldRow("Alternate Names", showDivider: false) {
                    Text(person.llmAlternateNames.joined(separator: ", "))
                        .foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Media

    private var mediaSection: some View {
        EditorSection("Media", systemImage: "photo",
                      isExpanded: isExpanded("Media")) {
            if !person.imageURL.isEmpty || !person.additionalMedia.isEmpty {
                MediaGrid(imageURL: $person.imageURL, items: $person.additionalMedia)
                    .padding(.vertical, 6)
            }
            Button { person.additionalMedia.append(EditableMediaItem()) } label: {
                Label("Add Image", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Notes

    @ViewBuilder
    private var notesSection: some View {
        if !person.wikiSections.isEmpty {
            EditorSection("Notes", systemImage: "doc.text",
                          isExpanded: isExpanded("Notes")) {
                ForEach(person.wikiSections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        if !section.title.isEmpty {
                            Text(section.title)
                                .font(.subheadline).fontWeight(.semibold)
                        }
                        Text(section.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        EditorSection("Sources", systemImage: "doc.badge.gearshape",
                      isExpanded: isExpanded("Sources")) {
            if !person.wikiTitle.isEmpty { wikiSourceRow }
            if hasLLMData {
                FieldRow("AI Analysis", showDivider: false) {
                    Label("Claude AI (Anthropic)", systemImage: "wand.and.stars")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var wikiSourceRow: some View {
        let encoded   = person.wikiTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? person.wikiTitle
        let urlString = "https://en.wikipedia.org/wiki/" + encoded
        if let url = URL(string: urlString) {
            FieldRow("Wikipedia", showDivider: hasLLMData) {
                Link(urlString, destination: url).lineLimit(1)
            }
        }
    }

    private var hasLLMData: Bool {
        !person.llmAlternateNames.isEmpty || !person.llmTitles.isEmpty
            || !person.llmFacts.isEmpty || !person.llmEvents.isEmpty
            || !person.influentialPeople.isEmpty
    }

    // MARK: - Other

    private var otherSection: some View {
        EditorSection("Other", systemImage: "ellipsis.circle",
                      isExpanded: isExpanded("Other")) {
            SubGroup(title: "Parents", systemImage: "person.circle",
                     isExpanded: isExpanded("Other.Parents")) {
                FieldRow("Father") { TextField("Father's full name", text: $person.father) }
                FieldRow("Mother", showDivider: false) {
                    TextField("Mother's full name", text: $person.mother)
                }
            }
            Divider()
            SubGroup(title: "Children", systemImage: "person.2.fill",
                     isExpanded: isExpanded("Other.Children")) {
                ForEach($person.children) { $child in
                    HStack {
                        TextField("Child's full name", text: $child.name)
                            .textFieldStyle(.plain)
                        Button { person.children.removeAll { $0.id == child.id } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 5)
                    Divider()
                }
                Button { person.children.append(EditablePersonRef()) } label: {
                    Label("Add Child", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
            if !person.influentialPeople.isEmpty {
                Divider()
                aiGeneratedLabel
                ForEach(person.influentialPeople, id: \.name) { influentialPerson in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(influentialPerson.name).fontWeight(.medium)
                            Text("· \(influentialPerson.relationship)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let note = influentialPerson.note {
                            Text(note).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.leading, 22)
                    Divider().padding(.leading, 22)
                }
            }
        }
    }
}
