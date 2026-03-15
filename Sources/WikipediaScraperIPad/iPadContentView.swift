#if os(iOS)
import SwiftUI
import WikipediaScraperSharedUI

// MARK: - Claude AI Settings Sheet (iPad)

private struct iPadLLMSettingsView: View {
    @ObservedObject private var llm = LLMSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable AI Analysis", isOn: $llm.isEnabled)
                    if llm.isEnabled {
                        LabeledContent("API Key") {
                            SecureField("sk-ant-…", text: $llm.apiKey)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.asciiCapable)
                        }
                    }
                } header: {
                    Label("Claude AI (Anthropic)", systemImage: "wand.and.stars")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("When enabled, Claude AI analyses each article to extract alternate names, titles, facts, events, and influential people. Results are stored separately in the GEDCOM and cited as \u{201C}Claude AI (Anthropic)\u{201D}.")
                        if llm.isEnabled && llm.apiKey.isEmpty {
                            Label("An Anthropic API key is required.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .padding(.top, 2)
                        }
                    }
                    .font(.footnote)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Main content view

struct iPadContentView: View {
    @StateObject private var vm = iPadPersonViewModel()
    @State private var showingSettings = false
    @State private var showingAddURL = false
    @State private var sidebarTab: SidebarTab = .people
    @State private var selectedSourceID: UUID? = nil

    enum SidebarTab: String, CaseIterable {
        case people  = "People"
        case sources = "Sources"
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            NavigationSplitView {
                sidebarContent
                    .navigationSplitViewColumnWidth(min: 200, ideal: 260)
            } detail: {
                detailContent
                    .navigationTitle(detailTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { detailToolbar }
            }
        }
        .toolbar { globalToolbar }
        .sheet(isPresented: $showingSettings) { iPadLLMSettingsView() }
        .fileExporter(
            isPresented:     $vm.isExportingGED,
            document:         vm.gedDocument,
            contentType:      .plainText,
            defaultFilename:  vm.exportFilename + ".ged"
        ) { vm.handleExportResult($0) }
        .fileExporter(
            isPresented:     $vm.isExportingZip,
            document:         vm.zipDocument,
            contentType:      .zip,
            defaultFilename:  vm.exportFilename + ".zip"
        ) { vm.handleExportResult($0) }
    }

    // MARK: - Top Bar (spans full width above split view)

    private var topBar: some View {
        VStack(spacing: 0) {
            urlBar
            Divider()
            FetchOptionsView(
                useNotes:     $vm.useNotes,
                useAllImages: $vm.useAllImages,
                noPeople:     $vm.noPeople
            )
            .background(Color(uiColor: .secondarySystemBackground))
            if let err = vm.errorMessage {
                Divider()
                errorBanner(message: err)
            }
            Divider()
        }
    }

    // MARK: - URL Bar

    private var urlBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)

            // Scrollable chip list
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.urls, id: \.self) { url in
                        URLChip(urlString: url) { vm.removeURL(url) }
                    }
                    Button {
                        showingAddURL = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .imageScale(.large)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity)

            fetchControl
                .frame(minWidth: 30, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .sheet(isPresented: $showingAddURL) {
            AddURLSheet { url in vm.addURL(url) }
        }
    }

    @ViewBuilder
    private var fetchControl: some View {
        if vm.isLoading {
            ProgressView().controlSize(.regular)
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
                    .foregroundStyle(vm.urls.isEmpty ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tint))
            }
            .disabled(vm.urls.isEmpty)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
            if sidebarTab == .people {
                peopleList
            } else {
                sourcesList
            }
        }
    }

    // MARK: - People List

    private var peopleList: some View {
        List(vm.persons, selection: $vm.selectedPersonID) { person in
            personRow(person)
        }
        .listStyle(.sidebar)
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
                ScrollView {
                    PersonEditorView(person: binding)
                        .padding(.vertical, 8)
                }
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
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.quaternary)
            Text(vm.hasData ? "No person selected" : "No person loaded")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text(vm.hasData
                 ? "Select a person from the sidebar"
                 : "Paste a Wikipedia biography URL above and tap Return")
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptySourceState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64, weight: .thin))
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
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Detail title

    private var detailTitle: String {
        switch sidebarTab {
        case .people:
            if let id = vm.selectedPersonID,
               let p = vm.persons.first(where: { $0.id == id }) {
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

    // MARK: - Toolbars

    @ToolbarContentBuilder
    private var globalToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button { showingSettings = true } label: {
                Image(systemName: LLMSettings.shared.isEnabled ? "wand.and.stars" : "gearshape")
            }
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Export as GEDCOM…") { vm.saveAsGED() }
                Button("Export as ZIP…")    { Task { await vm.saveAsZip() } }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(!vm.hasData)
        }
    }
}

#Preview {
    iPadContentView()
}
#endif
