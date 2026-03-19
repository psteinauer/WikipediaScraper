import SwiftUI
import AppKit
import WikipediaScraperSharedUI

// MARK: - Chip flow layout
//
// Lays out variable-width children left-to-right, wrapping to new rows as
// needed.  The container height grows to fit all rows; the width fills the
// available space (set by the parent).

private struct ChipFlowLayout: Layout {
    var hSpacing: CGFloat = 6
    var vSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(subviews: subviews, in: proposal.width ?? 0)
        return result.totalSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, in: bounds.width)
        for (subview, frame) in zip(subviews, result.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private struct LayoutResult {
        var frames: [CGRect]
        var totalSize: CGSize
    }

    private func layout(subviews: Subviews, in width: CGFloat) -> LayoutResult {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            // Wrap if this item would overflow (but never wrap the very first item on a row)
            if x > 0 && x + size.width > width {
                y         += rowHeight + vSpacing
                x          = 0
                rowHeight  = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x         += size.width + hSpacing
            rowHeight  = max(rowHeight, size.height)
        }

        return LayoutResult(
            frames:    frames,
            totalSize: CGSize(width: width, height: y + rowHeight)
        )
    }
}

// MARK: - Person row view
//
// Keeping .onDrag on the entire row competes with the List's click-to-select
// gesture on macOS — the drag recognizer can eat the mouseDown and prevent
// selection.  Moving the drag to a dedicated handle icon (shown on hover)
// gives .onDrag a tiny hit-target so normal clicks on the rest of the row
// always reach the List's selection handler.

private struct PersonRowView: View {
    let person:       EditablePerson
    let displayName:  String
    let dragProvider: () -> NSItemProvider

    @State private var isHovered = false

    var body: some View {
        if person.isStub {
            Label {
                Text(displayName).foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "person.badge.clock").foregroundStyle(.tertiary)
            }
        } else {
            Label {
                HStack(spacing: 0) {
                    Text(displayName)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    // Drag handle — visible on hover, not a tap target for selection.
                    Image(systemName: "arrow.up.doc")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                        .opacity(isHovered ? 1 : 0)
                        .padding(.leading, 6)
                        .onDrag { dragProvider() }
                }
            } icon: {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Content view

struct ContentView: View {
    @StateObject private var vm = PersonViewModel()
    @State private var sidebarTab: SidebarTab = .people
    // Local selection for List — @State so SwiftUI's reconciliation never writes to a
    // @Published property during the view update pass (which causes "Publishing changes
    // from within view updates" warnings).  Kept in sync with vm.selectedPersonID via onChange.
    @State private var selectedPersonID: UUID? = nil
    @State private var selectedSourceID: UUID? = nil
    @State private var showingAddURL    = false
    @State private var showingSettings  = false

    enum SidebarTab: String, CaseIterable {
        case people  = "People"
        case sources = "Sources"
    }

    var body: some View {
        VStack(spacing: 0) {
            urlBar
            Divider()
            NavigationSplitView {
                sidebarContent
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
            } detail: {
                detailContent
                    .navigationTitle(detailTitle)
            }
        }
        .task { await vm.fetchOnLaunch() }
        .onAppear { URLRouter.shared.register { url in vm.handleOpenURL(url) } }
        .toolbar { toolbarContent }
        .focusedValue(\.personViewModel, vm)
        .alert("Some Images Could Not Be Loaded", isPresented: Binding(
            get: { !vm.mediaWarnings.isEmpty },
            set: { if !$0 { vm.mediaWarnings = [] } }
        )) {
            Button("OK") { vm.mediaWarnings = [] }
        } message: {
            Text(vm.mediaWarnings.joined(separator: "\n"))
        }
        .sheet(isPresented: $showingAddURL) {
            AddURLSheet { url in vm.addURL(url) }
        }
        .sheet(isPresented: $vm.showingGEDCOMPreview) {
            if let gedcom = vm.gedcomPreviewText {
                GEDCOMPreviewSheet(
                    gedcom:   gedcom,
                    filename: vm.gedcomFilename
                )
            }
        }
        .sheet(isPresented: $vm.showingAIProgress) {
            AIProgressSheet(
                entries:     $vm.aiProgressEntries,
                isPresented: $vm.showingAIProgress,
                isComplete:  vm.aiProgressEntries.allSatisfy { $0.isDone || $0.failed }
            )
        }
    }

    // MARK: - URL bar (full-width, wrapping chip row)

    private var urlBar: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "globe")
                .foregroundStyle(.tertiary)
                .imageScale(.small)
                // Optically align the icon with the first row of chips
                .padding(.top, 5)

            ChipFlowLayout(hSpacing: 6, vSpacing: 6) {
                ForEach(vm.urls, id: \.self) { url in
                    URLChip(urlString: url) { vm.removeURL(url) }
                }
                // The + button is the last item in the flow so it is always
                // reachable — it wraps onto a new line when the row is full.
                addButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var addButton: some View {
        Button {
            showingAddURL = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .imageScale(.small)
                    .fontWeight(.semibold)
                if vm.urls.isEmpty {
                    Text("Add Article")
                        .font(.callout)
                }
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, vm.urls.isEmpty ? 6 : 4)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderless)
        .help("Add a Wikipedia article URL")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Leading: Settings popover
        ToolbarItem(placement: .navigation) {
            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .symbolRenderingMode(.hierarchical)
            }
            .help("Settings")
            .popover(isPresented: $showingSettings, arrowEdge: .top) {
                LLMSettingsView()
            }
        }

        // Fetch / status indicator — its own automatic item
        ToolbarItem(placement: .automatic) {
            fetchControl
        }

        // AI Analysis + drag handle + Export — explicit trailing group
        // so macOS sizes the oval for all three icons from the start.
        ToolbarItemGroup(placement: .primaryAction) {
            aiAnalysisControl
            documentDragHandle
            exportMenu
        }
    }

    // MARK: - Fetch control

    @ViewBuilder
    private var fetchControl: some View {
        if vm.isLoading {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                if let status = vm.statusMessage {
                    Text(status)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                        .transition(.opacity.animation(.easeOut))
                }
            }
        } else {
            Button {
                Task { await vm.fetch() }
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(vm.urls.isEmpty ? Color.secondary.opacity(0.3) : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .disabled(vm.urls.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Fetch Wikipedia articles (⌘↩)")
            .padding(.horizontal, 10)
        }
    }

    // MARK: - AI Analysis control

    @ViewBuilder
    private var aiAnalysisControl: some View {
        if vm.isAnalyzing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                if let status = vm.statusMessage {
                    Text(status)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                        .transition(.opacity.animation(.easeOut))
                }
            }
        } else {
            Button {
                Task { await vm.analyzeWithLLM() }
            } label: {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(vm.hasData ? Color.accentColor : Color.secondary.opacity(0.3))
            }
            .buttonStyle(.borderless)
            .disabled(!vm.hasData || vm.isLoading)
            .help("Run AI Analysis on fetched articles")
        }
    }

    // MARK: - Document drag handle

    @ViewBuilder
    private var documentDragHandle: some View {
        let tip = vm.documentHasImages
            ? "Drag to export as GEDZIP (.zip)"
            : "Drag to export as GEDCOM (.ged) or ZIP"
        Image(systemName: "arrow.up.doc.fill")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(vm.hasData ? Color.accentColor : Color.secondary.opacity(0.3))
            .padding(.horizontal, 10)
            .help(tip)
            .onDrag {
                guard vm.hasData else { return NSItemProvider() }
                return vm.dragItemProviderForDocument()
            }
    }

    // MARK: - Export menu

    private var exportMenu: some View {
        Menu {
            Button("Export as GEDCOM…") { vm.saveAsGED() }
            Button("Export as ZIP…")    { Task { await vm.saveAsZip() } }
            Divider()
            Button("Open in MacFamilyTree 11") { Task { await vm.openInMacFamilyTree() } }
            Divider()
            Button("View GEDCOM…") { vm.previewGEDCOM() }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(!vm.hasData)
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            FetchOptionsView(
                useNotes:     $vm.useNotes,
                useAllImages: $vm.useAllImages,
                noPeople:     $vm.noPeople
            )

            Divider()

            if let err = vm.errorMessage {
                errorBanner(message: err)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Picker("", selection: $sidebarTab) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            if sidebarTab == .people {
                peopleList
            } else {
                sourcesList
            }
        }
        .animation(.easeInOut(duration: 0.18), value: vm.errorMessage != nil)
        .background(.background)
    }

    // MARK: - Error banner

    @ViewBuilder
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .imageScale(.small)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                vm.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .imageScale(.small)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
    }

    // MARK: - People list

    private var peopleList: some View {
        List(vm.persons, selection: $selectedPersonID) { person in
            PersonRowView(
                person:       person,
                displayName:  personDisplayName(person),
                dragProvider: { vm.dragItemProvider(for: person) }
            )
        }
        .listStyle(.sidebar)
        // Sync local @State selection → VM.  This runs after the view update pass,
        // so mutating vm.selectedPersonID here does NOT cause "Publishing" warnings.
        // If the list clears selection (macOS re-click, or data change removing the
        // selected item), restore to the first non-stub person.
        .onChange(of: selectedPersonID) { newID in
            let resolved = newID ?? vm.persons.first(where: { !$0.isStub })?.id
            if vm.selectedPersonID != resolved { vm.selectedPersonID = resolved }
        }
        // Sync VM → local selection so programmatic selection (after fetch, merge,
        // rebuildStubs) is reflected in the List.
        .onChange(of: vm.selectedPersonID) { newID in
            if selectedPersonID != newID { selectedPersonID = newID }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first {
                Button(role: .destructive) {
                    vm.removePerson(id: id)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
        .overlay {
            if vm.persons.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 28, weight: .thin))
                        .foregroundStyle(.quaternary)
                    Text("No articles added")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func personDisplayName(_ person: EditablePerson) -> String {
        if !person.wikiTitle.isEmpty { return person.wikiTitle }
        let full = [person.givenName, person.surname]
            .filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "Unknown" : full
    }

    // MARK: - Sources list

    private var sourcesList: some View {
        List(vm.sources, selection: $selectedSourceID) { source in
            Label(source.name, systemImage: source.icon)
        }
        .listStyle(.sidebar)
        .overlay {
            if vm.sources.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28, weight: .thin))
                        .foregroundStyle(.quaternary)
                    Text("No sources yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        switch sidebarTab {
        case .people:
            if let id = selectedPersonID,
               vm.persons.contains(where: { $0.id == id }) {
                // Build the binding directly from the local selection so the detail view
                // updates in the same render pass as the sidebar, with no one-frame lag.
                PersonEditorView(person: Binding(
                    get: { vm.persons.first(where: { $0.id == id }) ?? EditablePerson() },
                    set: { newValue in
                        if let i = vm.persons.firstIndex(where: { $0.id == id }) {
                            vm.persons[i] = newValue
                        }
                    }
                ))
            } else {
                emptyPeopleState
            }
        case .sources:
            if let id = selectedSourceID,
               let source = vm.sources.first(where: { $0.id == id }) {
                SourceDetailView(source: source)
            } else {
                emptySourceState
            }
        }
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyPeopleState: some View {
        if #available(macOS 14.0, *) {
            ContentUnavailableView {
                Label(
                    vm.hasData ? "No Person Selected" : "No Articles Added",
                    systemImage: "person.text.rectangle"
                )
            } description: {
                Text(vm.hasData
                     ? "Select a person from the sidebar."
                     : "Add a Wikipedia biography URL with the + button, then press ⌘↩.")
            }
        } else {
            legacyEmptyView(
                icon:   "person.text.rectangle",
                title:  vm.hasData ? "No person selected" : "No person loaded",
                detail: vm.hasData
                    ? "Select a person from the sidebar"
                    : "Click + in the URL bar to add Wikipedia articles, then press ⌘↩"
            )
        }
    }

    @ViewBuilder
    private var emptySourceState: some View {
        if #available(macOS 14.0, *) {
            ContentUnavailableView {
                Label(
                    vm.hasData ? "No Source Selected" : "No Sources Yet",
                    systemImage: "doc.text.magnifyingglass"
                )
            } description: {
                Text(vm.hasData
                     ? "Select a source from the sidebar."
                     : "Fetch a Wikipedia article to see its sources.")
            }
        } else {
            legacyEmptyView(
                icon:   "doc.text.magnifyingglass",
                title:  vm.hasData ? "No source selected" : "No sources yet",
                detail: vm.hasData
                    ? "Select a source from the sidebar"
                    : "Fetch a Wikipedia article to see its sources"
            )
        }
    }

    private func legacyEmptyView(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.quaternary)
            Text(title)
                .font(.title2).fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text(detail)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Detail title

    private var detailTitle: String {
        switch sidebarTab {
        case .people:
            if let id = selectedPersonID,
               let p = vm.persons.first(where: { $0.id == id }),
               !personDisplayName(p).isEmpty {
                return personDisplayName(p)
            }
            return "Wikipedia to GEDCOM"
        case .sources:
            if let id = selectedSourceID,
               let s = vm.sources.first(where: { $0.id == id }) {
                return s.name
            }
            return "Sources"
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1040, height: 740)
}
