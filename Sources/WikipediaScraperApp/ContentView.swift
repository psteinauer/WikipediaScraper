import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var vm = PersonViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // URL input bar
            HStack(spacing: 8) {
                TextField("Wikipedia article URL…", text: $vm.urlString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await vm.fetch() }
                    }

                Button("Fetch") {
                    Task { await vm.fetch() }
                }
                .disabled(vm.isLoading || vm.urlString.isEmpty)

                if vm.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                }
            }
            .padding(12)

            Divider()

            // Error banner
            if let errorMessage = vm.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))

                Divider()
            }

            // Main content area
            if vm.hasData {
                ScrollView {
                    PersonEditorView(person: $vm.person)
                        .padding(.vertical, 8)
                }
            } else if !vm.isLoading {
                Spacer()
                Text("Enter a Wikipedia URL above and click Fetch")
                    .foregroundStyle(.secondary)
                    .font(.title3)
                Spacer()
            } else {
                Spacer()
                ProgressView("Fetching…")
                Spacer()
            }

            Divider()

            // Bottom toolbar
            HStack(spacing: 12) {
                Spacer()

                if let status = vm.statusMessage {
                    Text(status)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                }

                Button("Save as .ged") {
                    vm.saveAsGED()
                }
                .disabled(!vm.hasData)

                Button("Save as .zip") {
                    Task { await vm.saveAsZip() }
                }
                .disabled(!vm.hasData)
            }
            .padding(10)
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 700)
}
