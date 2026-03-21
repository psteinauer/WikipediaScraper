#if os(iOS)
import SwiftUI
import UserNotifications

@main
struct WikipediaScraperIPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            iPhoneContentView()
                .task {
                    _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound])
                }
        }
    }
}

#else

// macOS compilation stub — provides the required entry point so
// `swift build` succeeds on macOS. Never actually runs on macOS.
@main
struct WikipediaScraperIPhoneApp {
    static func main() {}
}

#endif
