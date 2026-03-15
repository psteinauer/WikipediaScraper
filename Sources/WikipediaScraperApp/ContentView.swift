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
        VStack(spacing: 0) {
            topBar
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
    }

    // MARK: - Top Bar (spans full window width)

    private var topBar: some View {
        VStack(spacing: 0) {
            urlBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            FetchOptionsView(
                useNotes:     $vm.useNotes,
                useAllImages: $vm.useAllImages,
                noPeople:     $vm.noPeople
            )
            .background(Color(NSColor.windowBackgroundColor))
            if let err = vm.errorMessage {
                Divider()
                errorBanner(message: err)
            }
            Divider()
        }
    }

    // MARK: - URL Bar

    private var urlBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .imageScale(.medium)

            // Scrollable chip list
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(vm.urls, id: \.self) { url in
                        URLChip(urlString: url) { vm.removeURL(url) }
                    }
                    // + button
                    Button {
                        showingAddURL = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .imageScale(.medium)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.borderless)
                    .help("Add a Wikipedia article URL")
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity)

            // Fetch / status
            Group {
                if vm.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if let status = vm.statusMessage {
                    Text(status)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                        .transition(.opacity.animation(.easeOut))
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
                }
            }
            .frame(minWidth: 22, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
                }
        }
        .sheet(isPresented: $showingAddURL) {
            AddURLSheet { url in vm.addURL(url) }
        }
    }

    // MARK: - Error Banner

    @ViewBuilder
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .foregroundStyle(.red)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss") { vm.errorMessage = nil }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.07))
    }

    // MARK: - Sidebar (tab picker + list only)

    private var sidebarContent: some View {
        VStack(spacing: 0) {
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
        .background(.background)
    }

    // MARK: - People List

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
                Text("No people yet")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func personRow(_ person: EditablePerson) -> some View {
        let name = personDisplayName(person)
        if person.isStub {
            Label(name, systemImage: "person.badge.clock")
                .foregroundStyle(.secondary)
        } else {
            Label(name, systemImage: person.sex == .female ? "person.circle.fill" : "person.circle")
        }
    }

    private func personDisplayName(_ person: EditablePerson) -> String {
        if !person.wikiTitle.isEmpty { return person.wikiTitle }
        let full = [person.givenName, person.surname]
            .filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "Unknown" : full
    }

    // MARK: - Sources List

    private var sourcesList: some View {
        List(vm.sources, selection: $selectedSourceID) { source in
            Label(source.name, systemImage: source.icon)
        }
        .listStyle(.sidebar)
        .overlay {
            if vm.sources.isEmpty {
                Text("No sources yet")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
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

    private var emptyPeopleState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.quaternary)
            Text(vm.hasData ? "No person selected" : "No person loaded")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text(vm.hasData
                 ? "Select a person from the sidebar"
                 : "Click + in the URL bar to add Wikipedia articles, then press ⌘↩")
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptySourceState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.quaternary)
            Text("No source selected")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text(vm.hasData
                 ? "Select a source from the sidebar"
                 : "Fetch a Wikipedia article to see its sources")
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Export as GEDCOM…") { vm.saveAsGED() }
                Button("Export as ZIP…") { Task { await vm.saveAsZip() } }
                Divider()
                Button("Open in MacFamilyTree 11") { Task { await vm.openInMacFamilyTree() } }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(!vm.hasData)
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 960, height: 720)
}
