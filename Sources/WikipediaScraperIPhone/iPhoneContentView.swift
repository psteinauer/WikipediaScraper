#if os(iOS)
import SwiftUI
import WikipediaScraperSharedUI

// MARK: - Settings sheet

private struct iPhoneLLMSettingsView: View {
    @ObservedObject private var llm = LLMSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("API Key") {
                        SecureField("sk-ant-…", text: $llm.apiKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.asciiCapable)
                    }
                } header: {
                    Label("Claude AI (Anthropic)", systemImage: "wand.and.stars")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Use the \u{201C}wand\u{201D} toolbar button to run AI Analysis on fetched articles. Results are stored separately in the GEDCOM and cited as \u{201C}Claude AI (Anthropic)\u{201D}.")
                        if llm.apiKey.isEmpty {
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

// MARK: - Navigation destination tag

private enum NavDest: Hashable {
    case person(UUID)
    case source(UUID)
}

// MARK: - Main content view

struct iPhoneContentView: View {
    @StateObject private var vm = iPhonePersonViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var contentTab: ContentTab = .people
    @State private var showingSettings = false
    @State private var showingAddURL   = false

    enum ContentTab: String, CaseIterable {
        case people  = "People"
        case sources = "Sources"
    }

    var body: some View {
        NavigationStack {
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
                tabPicker
                Divider()
                if contentTab == .people {
                    peopleList
                } else {
                    sourcesList
                }
            }
            .navigationTitle("Wikipedia to GEDCOM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { globalToolbar }
            .navigationDestination(for: NavDest.self) { dest in
                switch dest {
                case .person(let id):  personDetail(id: id)
                case .source(let id):  sourceDetail(id: id)
                }
            }
        }
        .task { await vm.fetchOnLaunch() }
        .onOpenURL { url in vm.handleOpenURL(url) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { vm.checkPendingShareURL() }
        }
        .sheet(isPresented: $showingSettings) { iPhoneLLMSettingsView() }
        .sheet(isPresented: $vm.showingAIProgress) {
            AIProgressSheet(
                entries:     $vm.aiProgressEntries,
                isPresented: $vm.showingAIProgress,
                isComplete:  vm.aiProgressEntries.allSatisfy { $0.isDone || $0.failed }
            )
        }
        .alert("Some Images Could Not Be Loaded", isPresented: Binding(
            get: { !vm.mediaWarnings.isEmpty },
            set: { if !$0 { vm.mediaWarnings = [] } }
        )) {
            Button("OK") { vm.mediaWarnings = [] }
        } message: {
            Text(vm.mediaWarnings.joined(separator: "\n"))
        }
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

    // MARK: - URL Bar

    private var urlBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)

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

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("", selection: $contentTab) {
            ForEach(ContentTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - People List

    private var peopleList: some View {
        List(vm.persons) { person in
            NavigationLink(value: NavDest.person(person.id)) {
                personRow(person)
            }
        }
        .listStyle(.plain)
        .overlay {
            if vm.persons.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 48, weight: .thin))
                        .foregroundStyle(.quaternary)
                    Text(vm.hasData ? "No people yet" : "No person loaded")
                        .foregroundStyle(.tertiary)
                        .font(.callout)
                    if !vm.hasData {
                        Text("Tap + to add a Wikipedia biography URL")
                            .foregroundStyle(.quaternary)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
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
        List(vm.sources) { source in
            NavigationLink(value: NavDest.source(source.id)) {
                Label(source.name, systemImage: source.icon)
            }
        }
        .listStyle(.plain)
        .overlay {
            if vm.sources.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48, weight: .thin))
                        .foregroundStyle(.quaternary)
                    Text("No sources yet")
                        .foregroundStyle(.tertiary)
                        .font(.callout)
                }
            }
        }
    }

    // MARK: - Detail Views

    @ViewBuilder
    private func personDetail(id: UUID) -> some View {
        if let binding = vm.personBinding(for: id) {
            ScrollView {
                PersonEditorView(person: binding)
                    .padding(.vertical, 8)
            }
            .navigationTitle(personDisplayName(binding.wrappedValue))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Export as GEDCOM…") { vm.saveAsGED() }
                        Button("Export as ZIP…") { Task { await vm.saveAsZip() } }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!vm.hasData)
                }
            }
            .onAppear { vm.selectedPersonID = id }
        }
    }

    @ViewBuilder
    private func sourceDetail(id: UUID) -> some View {
        if let source = vm.sources.first(where: { $0.id == id }) {
            SourceDetailView(source: source)
                .navigationTitle(source.name)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var globalToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
            }
        }
        ToolbarItem(placement: .navigationBarLeading) {
            if vm.isAnalyzing {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await vm.analyzeWithLLM() }
                } label: {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(vm.hasData ? Color.accentColor : Color.secondary.opacity(0.3))
                }
                .disabled(!vm.hasData || vm.isLoading)
            }
        }
    }
}

#Preview {
    iPhoneContentView()
}
#endif
