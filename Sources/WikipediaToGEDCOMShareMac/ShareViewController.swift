import Cocoa
import UniformTypeIdentifiers

/// macOS Share Extension view controller.
///
/// Shows a brief confirmation sheet with the shared URL, then opens the
/// containing app via `wikipedia-gedcom://add?url=…` when the user clicks Add.
final class ShareViewController: NSViewController {

    // MARK: - UI

    private let titleLabel: NSTextField = {
        let f = NSTextField(labelWithString: "Add to Wikipedia to GEDCOM")
        f.font = .boldSystemFont(ofSize: 13)
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }()

    private let urlLabel: NSTextField = {
        let f = NSTextField(labelWithString: "Resolving URL…")
        f.font = .systemFont(ofSize: 11)
        f.textColor = .secondaryLabelColor
        f.lineBreakMode = .byTruncatingTail
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }()

    private let addButton: NSButton = {
        let b = NSButton(title: "Add", target: nil, action: nil)
        b.bezelStyle = .rounded
        b.keyEquivalent = "\r"
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let cancelButton: NSButton = {
        let b = NSButton(title: "Cancel", target: nil, action: nil)
        b.bezelStyle = .rounded
        b.keyEquivalent = "\u{1B}"
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    // MARK: - State

    private var resolvedURLString: String?

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 90))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addButton.target   = self
        addButton.action   = #selector(didClickAdd)
        cancelButton.target = self
        cancelButton.action = #selector(didClickCancel)
        addButton.isEnabled = false

        let labelStack = NSStackView(views: [titleLabel, urlLabel])
        labelStack.orientation = .vertical
        labelStack.alignment   = .leading
        labelStack.spacing     = 3
        labelStack.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [cancelButton, addButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing     = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(labelStack)
        view.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            labelStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            labelStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            labelStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            buttonRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            buttonRow.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])

        extractURL { [weak self] urlString in
            DispatchQueue.main.async {
                self?.resolvedURLString = urlString
                self?.urlLabel.stringValue = urlString ?? "No URL found"
                self?.addButton.isEnabled  = urlString != nil
            }
        }
    }

    // MARK: - Actions

    @objc private func didClickAdd() {
        guard let raw = resolvedURLString,
              let encoded = raw.addingPercentEncoding(
                  withAllowedCharacters: .urlQueryAllowed),
              let appURL = URL(string: "wikipedia-gedcom://add?url=\(encoded)")
        else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        NSWorkspace.shared.open(appURL)
        extensionContext?.completeRequest(returningItems: nil)
    }

    @objc private func didClickCancel() {
        extensionContext?.cancelRequest(withError: NSError(
            domain: NSCocoaErrorDomain,
            code: NSUserCancelledError))
    }

    // MARK: - URL extraction

    private func extractURL(completion: @escaping (String?) -> Void) {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            completion(nil)
            return
        }

        let providers = items.flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty else {
            completion(nil)
            return
        }

        let urlTypes = [
            UTType.url.identifier,  // "public.url"
            "public.url",
        ]
        let textTypes = [
            UTType.plainText.identifier,
        ]

        // 1. Try URL types using loadObject — correctly bridges NSURL/URL on macOS.
        for provider in providers {
            for typeID in urlTypes where provider.hasItemConformingToTypeIdentifier(typeID) {
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, error in
                    if let url {
                        completion(url.absoluteString)
                    } else {
                        // loadObject failed — try legacy item loading.
                        self?.loadItemFallback(provider: provider,
                                               typeID: typeID,
                                               completion: completion)
                    }
                }
                return
            }
        }

        // 2. Plain text fallback.
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

    /// Legacy `loadItem` path — handles cases where `loadObject(ofClass: URL.self)`
    /// returns `nil` (can happen on older macOS with some share sources).
    private func loadItemFallback(
        provider: NSItemProvider,
        typeID: String,
        completion: @escaping (String?) -> Void
    ) {
        provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
            switch item {
            case let url  as URL:    completion(url.absoluteString)
            case let str  as String: completion(str)
            case let data as Data:   completion(String(data: data, encoding: .utf8))
            default:                 completion(nil)
            }
        }
    }
}
