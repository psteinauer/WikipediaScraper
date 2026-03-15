import SwiftUI
import WebKit
import WikipediaScraperCore

// MARK: - URL Chip

/// A pill-shaped tag showing an article title, with an × remove button.
public struct URLChip: View {
    public let urlString: String
    public let onRemove: () -> Void

    public init(urlString: String, onRemove: @escaping () -> Void) {
        self.urlString = urlString
        self.onRemove  = onRemove
    }

    private var displayTitle: String {
        guard let u = URL(string: urlString), u.path.hasPrefix("/wiki/") else { return urlString }
        let raw = String(u.path.dropFirst("/wiki/".count))
        return (raw.removingPercentEncoding ?? raw).replacingOccurrences(of: "_", with: " ")
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(displayTitle)
                .font(.callout)
                .lineLimit(1)
                .layoutPriority(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .imageScale(.small)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.30), lineWidth: 0.5)
        }
    }
}

// MARK: - Web View Controller

/// Holds WKWebView state. The WKWebView itself is created lazily on the first
/// call to `load(_:)` so the sheet opens instantly with no web-process overhead.
public final class WebViewController: ObservableObject {
    /// Non-nil only after `load(_:)` has been called at least once.
    public private(set) var webView: WKWebView?
    /// Updated on every completed navigation (user link clicks, redirects, etc.)
    @Published public var loadedURL: String = ""
    @Published public var canGoBack: Bool = false
    @Published public var canGoForward: Bool = false

    private var navDelegate: _NavDelegate?

    public init() {}

    /// Creates the WKWebView the first time this is called, then loads the URL.
    public func load(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return }

        if webView == nil {
            let delegate = _NavDelegate()
            delegate.onUpdate = { [weak self] in self?.syncState() }
            let wv = WKWebView()
            wv.navigationDelegate = delegate
            navDelegate = delegate
            webView = wv
        }
        webView!.load(URLRequest(url: url))
    }

    public func goBack()    { webView?.goBack() }
    public func goForward() { webView?.goForward() }
    public func reload()    { webView?.reload() }

    private func syncState() {
        canGoBack    = webView?.canGoBack    ?? false
        canGoForward = webView?.canGoForward ?? false
        if let url = webView?.url?.absoluteString, url != "about:blank" {
            loadedURL = url
        }
    }
}

// Navigation delegate — private implementation detail.
private final class _NavDelegate: NSObject, WKNavigationDelegate {
    var onUpdate: (() -> Void)?
    func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) { onUpdate?() }
    func webView(_ webView: WKWebView, didFinish _: WKNavigation!)                     { onUpdate?() }
    func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError _: Error)   { onUpdate?() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) { onUpdate?() }
}

// MARK: - WebView Representable (cross-platform)

#if os(macOS)
struct WebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#else
struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif

// MARK: - Add URL Sheet

public struct AddURLSheet: View {
    public let onAdd: (String) -> Void

    @StateObject private var web = WebViewController()
    @State private var addressText: String = ""
    @State private var errorMessage: String? = nil
    @Environment(\.dismiss) private var dismiss

    public init(onAdd: @escaping (String) -> Void) {
        self.onAdd = onAdd
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ── Header ───────────────────────────────────────────────────
            HStack {
                Text("Add Wikipedia Article")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // ── Address bar + controls ────────────────────────────────────
            HStack(spacing: 8) {
                TextField("https://en.wikipedia.org/wiki/…", text: $addressText)
                    .textFieldStyle(.roundedBorder)
#if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()

                Button("Load") { loadURL() }
                    .disabled(addressText.trimmingCharacters(in: .whitespaces).isEmpty)

                // Nav buttons — only shown once webview has been created
                if web.webView != nil {
                    HStack(spacing: 2) {
                        Button { web.goBack() } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .disabled(!web.canGoBack)
                        .buttonStyle(.borderless)
                        .help("Back")

                        Button { web.goForward() } label: {
                            Image(systemName: "chevron.forward")
                        }
                        .disabled(!web.canGoForward)
                        .buttonStyle(.borderless)
                        .help("Forward")

                        Button { web.reload() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Reload")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // ── Web view (or placeholder) ─────────────────────────────────
            if let wv = web.webView {
                WebViewRepresentable(webView: wv)
            } else {
                webViewPlaceholder
            }

            Divider()

            // ── Footer ────────────────────────────────────────────────────
            HStack(spacing: 10) {
                if let err = errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Add") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(addressText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 720, minHeight: 540)
        // When the webview navigates (user clicks a link), sync the address bar.
        .onChange(of: web.loadedURL) { newURL in
            addressText = newURL
        }
    }

    private var webViewPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.quaternary)
            Text("Enter a Wikipedia URL above and click Load")
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadURL() {
        errorMessage = nil
        web.load(addressText)
    }

    private func submit() {
        let trimmed = addressText
            .trimmingCharacters(in: CharacterSet(charactersIn: ",").union(.whitespaces))
        guard !trimmed.isEmpty else { return }
        do {
            _ = try WikipediaClient.pageTitle(from: trimmed)
            onAdd(trimmed)
            dismiss()
        } catch {
            errorMessage = "Not a valid Wikipedia article URL"
        }
    }
}
