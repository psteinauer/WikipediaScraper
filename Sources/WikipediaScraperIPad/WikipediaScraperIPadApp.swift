#if os(iOS)
import SwiftUI

@main
struct WikipediaScraperIPadApp: App {
    var body: some Scene {
        WindowGroup {
            iPadContentView()
        }
    }
}

#else

// macOS compilation stub — provides the required entry point so
// `swift build` succeeds on macOS. Never actually runs on macOS.
@main
struct WikipediaScraperIPadApp {
    static func main() {}
}

#endif
