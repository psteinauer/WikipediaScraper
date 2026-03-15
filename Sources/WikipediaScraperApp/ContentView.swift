import SwiftUI
import AppKit
import WikipediaScraperSharedUI

struct ContentView: View {
    @StateObject private var vm = PersonViewModel()
    @State private var sidebarTab: SidebarTab = .people
    @State private var selectedSourceID: UUID? = nil
    @State private var showingAddURL = false

    enum SidebarTab: String, CaseIterable {
        case people  = "People"
        case sources = "Sources"
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detailContent
                .navigationTitle(detailTitle)
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
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {

        // Leading: Settings / AI indicator
        ToolbarItem(placement: .navigation) {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: LLMSettings.shared.isEnabled ? "wand.and.stars" : "gearshape")
                    .symbolRenderingMode(.hierarchical)
            }
            .help(LLMSettings.shared.isEnabled
                  ? "AI Analysis is enabled — click to configure"
                  : "Open Settings (⌘,)")
        }

        // Centre: URL chip row (takes all available space in the title area)
        ToolbarItem(placement: .principal) {
            urlToolbarField
        }

        // Fetch options — icon toggles grouped together
        ToolbarItem(placement: .automatic) {
            fetchOptionToggles
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

    // MARK: - URL toolbar field

    private var urlToolbarField: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                        .foregroundStyle(.tertiary)
                        .imageScale(.small)
                        .padding(.leading, 2)

                    ForEach(vm.urls, id: \.self) { url in
                        URLChip(urlString: url) { vm.removeURL(url) }
                    }

                    Button {
                        showingAddURL = true
                    } label: {
                        Image(systemName: "plus")
                            .imageScale(.small)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.borderless)
                    .help("Add a Wikipedia article URL")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .frame(minWidth: 200, maxWidth: 540)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
                }
        }
    }

    // MARK: - Option toggles

    private var fetchOptionToggles: some View {
        ControlGroup {
            Toggle(isOn: $vm.useNotes) {
                Label("Notes", systemImage: "doc.plaintext")
            }
            .help("Include Wikipedia article sections as GEDCOM notes")

            Toggle(isOn: $vm.useAllImages) {
                Label("All Images", systemImage: "photo.stack")
            }
            .help("Download all article images into the ZIP export")

            Toggle(isOn: $vm.noPeople) {
                Label("Main Person Only", systemImage: "person.fill.badge.minus")
            }
            .help("Export only the main person — exclude family member stubs")
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
                Text(name)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "person.badge.clock")
                    .foregroundStyle(.tertiary)
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
                icon: "person.text.rectangle",
                title: vm.hasData ? "No person selected" : "No person loaded",
                detail: vm.hasData
                    ? "Select a person from the sidebar"
                    : "Click + in the toolbar to add Wikipedia articles, then press ⌘↩"
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
                icon: "doc.text.magnifyingglass",
                title: vm.hasData ? "No source selected" : "No sources yet",
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
                .font(.title2)
                .fontWeight(.medium)
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
