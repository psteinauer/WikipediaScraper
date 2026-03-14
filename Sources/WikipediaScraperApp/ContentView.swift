import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var vm = PersonViewModel()

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
        .toolbar { toolbarContent }
        .focusedValue(\.personViewModel, vm)
    }

    // MARK: - URL Bar

    private var urlBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .imageScale(.medium)

            TextField("Paste a Wikipedia article URL…", text: $vm.urlString)
                .textFieldStyle(.plain)
                .onSubmit { Task { await vm.fetch() } }
                .disabled(vm.isLoading)

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
                            .foregroundStyle(vm.urlString.isEmpty ? Color.secondary.opacity(0.3) : Color.accentColor)
                    }
                    .buttonStyle(.borderless)
                    .disabled(vm.urlString.isEmpty)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.quaternary)
            Text("No person loaded")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text("Paste a Wikipedia biography URL above and press Return or ⌘↩")
                .foregroundStyle(.tertiary)
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
                Button("Export as ZIP…") { Task { await vm.saveAsZip() } }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(!vm.hasData)
        }
    }
}

#Preview {
    NavigationStack {
        ContentView()
    }
    .frame(width: 960, height: 720)
}
