import AppKit

/// NSApplicationDelegate that registers this app as a macOS Services provider.
///
/// When another app (e.g. Safari) invokes the "Add to Wikipedia to GEDCOM"
/// service, `addURLFromService(_:userData:error:)` is called.  It re-routes
/// the request through the app's own `wikipedia-gedcom://` URL scheme so that
/// the SwiftUI `onOpenURL` handler in ContentView handles it uniformly.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register self as the services provider so macOS routes
        // NSServices invocations to the methods below.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// Intercept URL-scheme opens here so that SwiftUI never sees the event.
    /// If SwiftUI's `onOpenURL` were used instead, `WindowGroup` would create
    /// a new window each time a URL arrives while the app is already running.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            urls.forEach { URLRouter.shared.route($0) }
        }
    }

    /// Prevent SwiftUI from opening a new window when the app is re-activated
    /// (e.g. clicking the Dock icon while it is already running).
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        return false
    }

    /// Called when the user invokes "Add to Wikipedia to GEDCOM" from the
    /// Services menu or the share sheet in Safari / Chrome / Finder.
    ///
    /// The selector name must match the `NSMessage` value in Info.plist
    /// (`addURLFromService`), giving the full ObjC selector
    /// `addURLFromService:userData:error:`.
    @objc func addURLFromService(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        // Prefer a native URL type; fall back to a plain string pasted.
        let urlString: String?
        if let url = pboard.string(forType: .URL), !url.isEmpty {
            urlString = url
        } else if let str = pboard.string(forType: .string), !str.isEmpty {
            urlString = str
        } else {
            urlString = nil
        }

        guard let raw = urlString,
              let encoded = raw.addingPercentEncoding(
                  withAllowedCharacters: .urlQueryAllowed),
              let appURL = URL(string: "wikipedia-gedcom://add?url=\(encoded)")
        else { return }

        // Open via our own URL scheme — ContentView.onOpenURL handles it.
        NSWorkspace.shared.open(appURL)
    }
}
