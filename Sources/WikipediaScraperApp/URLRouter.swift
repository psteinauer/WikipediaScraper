import Foundation

/// Routes `wikipedia-gedcom://` URL-scheme events to the active window's handler.
///
/// Because `AppDelegate.application(_:open:)` may fire before ContentView has
/// appeared (on cold launch), any URL received before a handler is registered
/// is queued and replayed immediately when `register(handler:)` is called.
@MainActor
final class URLRouter {
    static let shared = URLRouter()
    private init() {}

    private var handler: ((URL) -> Void)?
    private var pending: URL?

    /// Called by ContentView on appear to start receiving URL events.
    func register(handler: @escaping (URL) -> Void) {
        self.handler = handler
        if let url = pending {
            pending = nil
            handler(url)
        }
    }

    /// Called by AppDelegate when the OS delivers a URL to the app.
    func route(_ url: URL) {
        if let handler {
            handler(url)
        } else {
            pending = url
        }
    }
}
