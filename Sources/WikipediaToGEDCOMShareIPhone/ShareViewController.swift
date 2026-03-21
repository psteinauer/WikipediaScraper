import UIKit
import UserNotifications
import UniformTypeIdentifiers

private let appGroupSuite = "group.com.psteinauer.WikipediaToGEDCOM"
private let pendingURLKey  = "pending_share_url"

/// iPhone Share Extension view controller.
///
/// Mirrors the macOS extension UX: shows the resolved URL with Add/Cancel
/// buttons. Tapping Add opens the host app via `wikipedia-gedcom://add?url=…`
/// (using the responder-chain trick that works from Share Extensions), and
/// also stashes the URL in App Group UserDefaults as a fallback for when the
/// system blocks the URL-scheme open.
final class ShareViewController: UIViewController {

    // MARK: - State

    private var resolvedURLString: String?

    // MARK: - UI

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "Add to Wikipedia to GEDCOM"
        l.font = .preferredFont(forTextStyle: .headline)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let urlLabel: UILabel = {
        let l = UILabel()
        l.text = "Resolving URL…"
        l.font = .preferredFont(forTextStyle: .subheadline)
        l.textColor = .secondaryLabel
        l.numberOfLines = 2
        l.lineBreakMode = .byTruncatingMiddle
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let addButton: UIButton = {
        var cfg = UIButton.Configuration.filled()
        cfg.title = "Add"
        cfg.cornerStyle = .medium
        return UIButton(configuration: cfg)
    }()

    private let cancelButton: UIButton = {
        var cfg = UIButton.Configuration.plain()
        cfg.title = "Cancel"
        return UIButton(configuration: cfg)
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        addButton.isEnabled = false
        addButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.addTarget(self, action: #selector(didTapAdd), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)

        let buttonStack = UIStackView(arrangedSubviews: [cancelButton, addButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(urlLabel)
        view.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            urlLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            urlLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            urlLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            buttonStack.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: 20),
            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            buttonStack.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])

        extractURL { [weak self] urlString in
            DispatchQueue.main.async {
                self?.resolvedURLString = urlString
                self?.urlLabel.text = urlString ?? "No URL found"
                self?.addButton.isEnabled = urlString != nil
            }
        }
    }

    // MARK: - Actions

    @objc private func didTapAdd() {
        guard let raw = resolvedURLString,
              let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              URL(string: "wikipedia-gedcom://add?url=\(encoded)") != nil
        else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        // Stash in App Group so the host app picks it up when it activates.
        if let defaults = UserDefaults(suiteName: appGroupSuite) {
            defaults.set(raw, forKey: pendingURLKey)
            defaults.synchronize()
        }

        // Post an immediate local notification. iOS Share Extensions cannot
        // programmatically foreground the host app, so this gives the user a
        // tap target that brings the app to the foreground and triggers import.
        let content = UNMutableNotificationContent()
        content.title = "Wikipedia to GEDCOM"
        content.body = "Tap to import the article"
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)

        extensionContext?.completeRequest(returningItems: nil)
    }

    @objc private func didTapCancel() {
        extensionContext?.cancelRequest(withError: NSError(
            domain: NSCocoaErrorDomain,
            code: NSUserCancelledError,
            userInfo: nil))
    }


    // MARK: - URL extraction

    private func extractURL(completion: @escaping (String?) -> Void) {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            completion(nil); return
        }
        let providers = items.flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty else { completion(nil); return }

        tryLoadURL(from: providers, typeIDs: [UTType.url.identifier, "public.url"]) { url in
            if let url {
                completion(url)
            } else {
                self.tryLoadText(from: providers, completion: completion)
            }
        }
    }

    private func tryLoadURL(from providers: [NSItemProvider],
                            typeIDs: [String],
                            completion: @escaping (String?) -> Void) {
        for provider in providers {
            for typeID in typeIDs where provider.hasItemConformingToTypeIdentifier(typeID) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in completion(url?.absoluteString) }
                return
            }
        }
        completion(nil)
    }

    private func tryLoadText(from providers: [NSItemProvider],
                             completion: @escaping (String?) -> Void) {
        for provider in providers
        where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadObject(ofClass: NSString.self) { str, _ in completion(str as? String) }
            return
        }
        completion(nil)
    }
}
