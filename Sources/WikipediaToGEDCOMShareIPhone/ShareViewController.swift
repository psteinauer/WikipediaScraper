import UIKit
import UniformTypeIdentifiers

private let appGroupSuite = "group.com.psteinauer.WikipediaToGEDCOM"
private let pendingURLKey  = "pending_share_url"

/// iPhone Share Extension.
///
/// Presents Add/Cancel buttons. Tapping Add stores the URL in the App Group
/// and opens the host app by walking the responder chain to UIApplication
/// and calling app.open() — the correct approach for Share Extension sandboxes.
final class ShareViewController: UIViewController {

    private var resolvedURL: URL?

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
        let b = UIButton(configuration: cfg)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let cancelButton: UIButton = {
        var cfg = UIButton.Configuration.plain()
        cfg.title = "Cancel"
        let b = UIButton(configuration: cfg)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        addButton.isEnabled = false
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
            buttonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])

        extractURL { [weak self] url in
            DispatchQueue.main.async {
                self?.resolvedURL = url
                self?.urlLabel.text = url?.absoluteString ?? "No URL found"
                self?.addButton.isEnabled = url != nil
            }
        }
    }

    // MARK: - Actions

    @objc private func didTapAdd() {
        guard let url = resolvedURL else { return }
        openMainApp(with: url)
    }

    @objc private func didTapCancel() {
        extensionContext?.cancelRequest(withError: NSError(
            domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil))
    }

    // MARK: - Open host app

    private func openMainApp(with url: URL) {
        // Cache in App Group so the host app can pick it up on activation.
        UserDefaults(suiteName: appGroupSuite)?.set(url.absoluteString, forKey: pendingURLKey)

        let encoded = url.absoluteString
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let deepLink = URL(string: "wikipedia-gedcom://add?url=\(encoded)")!

        // Walk the responder chain to UIApplication.
        // Extensions cannot call UIApplication.shared directly, but UIApplication
        // is reachable via the chain and app.open() works from there.
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(deepLink)
                break
            }
            responder = r.next
        }

        extensionContext?.completeRequest(returningItems: nil)
    }

    // MARK: - URL extraction

    private func extractURL(completion: @escaping (URL?) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first(where: {
                  $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
              })
        else {
            completion(nil); return
        }

        provider.loadItem(forTypeIdentifier: UTType.url.identifier) { data, _ in
            DispatchQueue.main.async {
                completion(data as? URL)
            }
        }
    }
}
