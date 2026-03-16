import UIKit
import UniformTypeIdentifiers

/// Minimal Share Extension view controller for iPadOS.
///
/// Immediately extracts the shared URL and opens the containing app via
/// `wikipedia-gedcom://add?url=<encoded-url>`.
final class ShareViewController: UIViewController {

    // MARK: - View

    private let label: UILabel = {
        let l = UILabel()
        l.text = "Adding to Wikipedia to GEDCOM…"
        l.font = .preferredFont(forTextStyle: .body)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(label)
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
        spinner.startAnimating()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        extractURL { [weak self] urlString in
            DispatchQueue.main.async {
                guard let self else { return }
                if let urlString,
                   let encoded = urlString.addingPercentEncoding(
                       withAllowedCharacters: .urlQueryAllowed),
                   let appURL = URL(string: "wikipedia-gedcom://add?url=\(encoded)") {
                    self.extensionContext?.open(appURL) { _ in
                        self.extensionContext?.completeRequest(returningItems: nil)
                    }
                } else {
                    self.extensionContext?.completeRequest(returningItems: nil)
                }
            }
        }
    }

    // MARK: - URL extraction

    private func extractURL(completion: @escaping (String?) -> Void) {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            completion(nil)
            return
        }

        // Collect all providers across all input items.
        let providers = items.flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty else {
            completion(nil)
            return
        }

        // Type identifiers to try, in priority order.
        let urlTypes = [
            UTType.url.identifier,          // "public.url"
            "public.url",                   // explicit fallback
        ]
        let textTypes = [
            UTType.plainText.identifier,    // "public.plain-text"
        ]

        // 1. Try URL types using the modern loadObject API (handles NSURL bridging).
        for provider in providers {
            for typeID in urlTypes where provider.hasItemConformingToTypeIdentifier(typeID) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url {
                        completion(url.absoluteString)
                    } else {
                        // loadObject failed — fall through to text fallback
                        completion(nil)
                    }
                }
                return
            }
        }

        // 2. Try plain-text (some share sources send URL as a string).
        for provider in providers {
            for typeID in textTypes where provider.hasItemConformingToTypeIdentifier(typeID) {
                provider.loadObject(ofClass: NSString.self) { str, _ in
                    completion(str as? String)
                }
                return
            }
        }

        completion(nil)
    }
}
