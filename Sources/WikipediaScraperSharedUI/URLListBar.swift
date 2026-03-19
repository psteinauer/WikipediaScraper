import SwiftUI
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
        guard let u = URL(string: urlString) else { return urlString }
        // Wikipedia: /wiki/Article_Title
        if u.path.hasPrefix("/wiki/") {
            let raw = String(u.path.dropFirst("/wiki/".count))
            return (raw.removingPercentEncoding ?? raw).replacingOccurrences(of: "_", with: " ")
        }
        // Other sites: use ?id= query param if present
        if let id = URLComponents(url: u, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "id" })?.value, !id.isEmpty {
            return id
        }
        // Fallback: show hostname
        return u.host ?? urlString
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
        #if os(macOS)
        .background {
            if #available(macOS 26.0, *) {
                // Liquid Glass — the chip looks like a frosted glass pill
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
                    }
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.30), lineWidth: 0.5)
                    }
            }
        }
        #else
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.30), lineWidth: 0.5)
                }
        }
        #endif
    }
}

// MARK: - Add URL Sheet

public struct AddURLSheet: View {
    public let onAdd: (String) -> Void

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
                Text("Add Person Page")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // ── URL entry ─────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 12) {
                TextField("https://en.wikipedia.org/wiki/… or other supported URL", text: $addressText)
                    .textFieldStyle(.roundedBorder)
#if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()
                    .onSubmit { submit() }

                // Supported sources hint
                VStack(alignment: .leading, spacing: 4) {
                    Text("Supported sources:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("• Wikipedia — https://en.wikipedia.org/wiki/…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("• BritRoyals — https://www.britroyals.com/kings.asp?id=…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)

            Spacer()

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
        .frame(width: 480, height: 180)
    }

    private func submit() {
        let trimmed = addressText
            .trimmingCharacters(in: CharacterSet(charactersIn: ",").union(.whitespaces))
        guard !trimmed.isEmpty else { return }
        guard let url = URL(string: trimmed), ScraperRegistry.canScrape(url) else {
            errorMessage = "Not a supported person page URL"
            return
        }
        onAdd(trimmed)
        dismiss()
    }
}
