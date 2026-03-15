import SwiftUI

// MARK: - Focused scene value key (lets Commands reach the active window's VM)

private struct PersonViewModelKey: FocusedValueKey {
    typealias Value = PersonViewModel
}

extension FocusedValues {
    var personViewModel: PersonViewModel? {
        get { self[PersonViewModelKey.self] }
        set { self[PersonViewModelKey.self] = newValue }
    }
}

// MARK: - App

@main
struct WikipediaScraperApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
            }
            .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 960, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            AppCommands()
        }

        Settings {
            LLMSettingsView()
        }
    }
}

// MARK: - Menu bar commands

private struct AppCommands: Commands {
    @FocusedValue(\.personViewModel) private var vm: PersonViewModel?

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Divider()
            Button("Export as GEDCOM…") {
                vm?.saveAsGED()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(vm?.hasData != true)

            Button("Export as ZIP…") {
                guard let vm else { return }
                Task { await vm.saveAsZip() }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(vm?.hasData != true)
        }
    }
}
