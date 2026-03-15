import SwiftUI

/// Compact options strip shown below the URL bar in both the macOS and iPadOS apps.
/// LLM toggle and API key are managed by LLMSettings.shared (persistent).
/// The remaining three options are per-session bindings from the view model.
public struct FetchOptionsView: View {

    @Binding public var useNotes:     Bool
    @Binding public var useAllImages: Bool
    @Binding public var noPeople:     Bool

    @ObservedObject private var llm = LLMSettings.shared

    public init(
        useNotes:     Binding<Bool>,
        useAllImages: Binding<Bool>,
        noPeople:     Binding<Bool>
    ) {
        _useNotes     = useNotes
        _useAllImages = useAllImages
        _noPeople     = noPeople
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            optionsRow
            if llm.isEnabled {
                apiKeyRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .animation(.easeInOut(duration: 0.18), value: llm.isEnabled)
    }

    // MARK: - Options row

    private var optionsRow: some View {
        #if os(macOS)
        HStack(spacing: 16) {
            optionToggle("wand.and.stars",         "AI Analysis",      "Enrich with Claude AI (LLM)",                       $llm.isEnabled)
            optionToggle("doc.plaintext",           "Notes",            "Include Wikipedia sections as GEDCOM notes",        $useNotes)
            optionToggle("photo.stack",             "All Images",       "Download all article images into ZIP export",        $useAllImages)
            optionToggle("person.fill.badge.minus", "Main Person Only", "Export only the searched person, no family stubs",  $noPeople)
            Spacer()
        }
        #else
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                optionToggle("wand.and.stars",         "AI Analysis",      nil, $llm.isEnabled)
                optionToggle("doc.plaintext",           "Notes",            nil, $useNotes)
                optionToggle("photo.stack",             "All Images",       nil, $useAllImages)
                optionToggle("person.fill.badge.minus", "Main Person Only", nil, $noPeople)
            }
            .padding(.vertical, 2)
        }
        #endif
    }

    // MARK: - API key row (shown only when AI Analysis is on)

    private var apiKeyRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "key.horizontal")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("Anthropic API key (sk-ant-…)", text: $llm.apiKey)
                .font(.caption)
                #if os(macOS)
                .textFieldStyle(.squareBorder)
                #else
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                #endif
        }
        .padding(.top, 5)
    }

    // MARK: - Per-platform toggle builder

    @ViewBuilder
    private func optionToggle(
        _ icon:    String,
        _ label:   String,
        _ tooltip: String?,
        _ binding: Binding<Bool>
    ) -> some View {
        #if os(macOS)
        Toggle(isOn: binding) {
            Label(label, systemImage: icon).font(.callout)
        }
        .toggleStyle(.checkbox)
        .ifLet(tooltip) { view, tip in view.help(tip) }
        #else
        Toggle(isOn: binding) {
            Label(label, systemImage: icon).font(.caption)
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .buttonBorderShape(.capsule)
        #endif
    }
}

// MARK: - Convenience modifier

private extension View {
    @ViewBuilder
    func ifLet<T>(_ value: T?, transform: (Self, T) -> some View) -> some View {
        if let value { transform(self, value) } else { self }
    }
}
