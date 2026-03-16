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
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 820, minHeight: 560)
        }
        // Opt this scene completely out of SwiftUI's external URL event routing.
        // Without this, WindowGroup creates a new window every time a URL is
        // delivered (e.g. from the Share Extension). URL handling is done
        // entirely via AppDelegate.application(_:open:) + URLRouter instead.
        .handlesExternalEvents(matching: [])
        .defaultSize(width: 1040, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}
            AppCommands()
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
