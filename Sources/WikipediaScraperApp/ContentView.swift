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

// MARK: - Content view

struct ContentView: View {
    @StateObject private var vm = PersonViewModel()
    @State private var sidebarTab: SidebarTab = .people
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
                Image(systemName: LLMSettings.shared.isEnabled ? "wand.and.stars" : "gearshape")
                    .symbolRenderingMode(.hierarchical)
            }
            .help(LLMSettings.shared.isEnabled
                  ? "AI Analysis is enabled — click to configure"
                  : "Settings")
            .popover(isPresented: $showingSettings, arrowEdge: .top) {
                LLMSettingsView(
                    useNotes:     $vm.useNotes,
                    useAllImages: $vm.useAllImages,
                    noPeople:     $vm.noPeople
                )
            }
        }

        // Fetch / status indicator
        ToolbarItem(placement: .automatic) {
            fetchControl
        }

        // Export
        ToolbarItem(placement: .primaryAction) {
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
        }
    }

    // MARK: - Export menu

    private var exportMenu: some View {
        Menu {
            Button("Export as GEDCOM…") { vm.saveAsGED() }
            Button("Export as ZIP…")    { Task { await vm.saveAsZip() } }
            Divider()
            Button("Open in MacFamilyTree 11") { Task { await vm.openInMacFamilyTree() } }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(!vm.hasData)
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
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
        List(vm.persons, selection: $vm.selectedPersonID) { person in
            personRow(person)
        }
        .listStyle(.sidebar)
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

    @ViewBuilder
    private func personRow(_ person: EditablePerson) -> some View {
        let name = personDisplayName(person)
        if person.isStub {
            Label {
                Text(name).foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "person.badge.clock").foregroundStyle(.tertiary)
            }
        } else {
            Label {
                Text(name)
            } icon: {
                Image(systemName: person.sex == .female ? "person.circle.fill" : "person.circle")
                    .foregroundStyle(Color.accentColor)
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
            if let binding = vm.selectedPersonBinding() {
                PersonEditorView(person: binding)
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
            if let id = vm.selectedPersonID,
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
