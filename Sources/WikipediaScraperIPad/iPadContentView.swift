#if os(iOS)
import SwiftUI
import WikipediaScraperSharedUI

struct iPadContentView: View {
    @StateObject private var vm = iPadPersonViewModel()

    var body: some View {
        VStack(spacing: 0) {
            urlBar
            Divider()
            if let err = vm.errorMessage {
                errorBanner(message: err)
            }
            mainContent
        }
        .navigationTitle(vm.hasData ? vm.person.wikiTitle : "Wikipedia to GEDCOM")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        // GEDCOM export sheet
        .fileExporter(
            isPresented:     $vm.isExportingGED,
            document:         vm.gedDocument,
            contentType:      .plainText,
            defaultFilename:  vm.exportFilename + ".ged"
        ) { vm.handleExportResult($0) }
        // ZIP export sheet
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

            TextField("Paste a Wikipedia article URL…", text: $vm.urlString)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .onSubmit { Task { await vm.fetch() } }
                .disabled(vm.isLoading)

            Group {
                if vm.isLoading {
                    ProgressView()
                        .controlSize(.regular)
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
                            .foregroundStyle(vm.urlString.isEmpty ? .quaternary : .tint)
                    }
                    .disabled(vm.urlString.isEmpty)
                }
            }
            .frame(minWidth: 30, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
        Divider()
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if vm.hasData {
            ScrollView {
                PersonEditorView(person: $vm.person)
                    .padding(.vertical, 8)
            }
        } else if vm.isLoading {
            VStack {
                Spacer()
                ProgressView("Fetching from Wikipedia…")
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.quaternary)
            Text("No person loaded")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text("Paste a Wikipedia biography URL above and tap Return")
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
    NavigationStack {
        iPadContentView()
    }
}
#endif
