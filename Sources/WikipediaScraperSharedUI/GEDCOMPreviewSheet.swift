import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - GEDCOMPreviewSheet

/// Full-screen sheet that renders a GEDCOM file as scrollable, selectable monospace text.
/// Provides Copy and Save buttons.
public struct GEDCOMPreviewSheet: View {
    public let gedcom: String
    public let filename: String
    @Environment(\.dismiss) private var dismiss

    // Font size: 10–20 pt, default 12
    @State private var fontSize: CGFloat = 12

    private let minFontSize: CGFloat = 8
    private let maxFontSize: CGFloat = 24

    public init(gedcom: String, filename: String) {
        self.gedcom   = gedcom
        self.filename = filename
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            gedcomBody
        }
        #if os(macOS)
        .frame(minWidth: 700, idealWidth: 860, minHeight: 500, idealHeight: 680)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(filename)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(lineCount) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Font-size controls
            HStack(spacing: 2) {
                Button { fontSize = max(minFontSize, fontSize - 1) } label: {
                    Image(systemName: "minus")
                        .frame(width: 20, height: 20)
                }
                .disabled(fontSize <= minFontSize)
                .buttonStyle(.borderless)
                .help("Decrease font size")

                Text("\(Int(fontSize)) pt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36, alignment: .center)
                    .monospacedDigit()

                Button { fontSize = min(maxFontSize, fontSize + 1) } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                }
                .disabled(fontSize >= maxFontSize)
                .buttonStyle(.borderless)
                .help("Increase font size")
            }
            .padding(.horizontal, 4)

            Divider().frame(height: 20)

            copyButton
            #if os(macOS)
            saveButton
            #endif
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Body

    private var gedcomBody: some View {
        ScrollView(.vertical) {
            Text(gedcom)
                .font(.system(size: fontSize, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(14)
        }
        .background(gedcomBackground)
    }

    #if os(macOS)
    private var gedcomBackground: Color { Color(NSColor.textBackgroundColor) }
    #else
    private var gedcomBackground: Color { Color(UIColor.systemBackground) }
    #endif

    // MARK: - Buttons

    private var copyButton: some View {
        Button {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(gedcom, forType: .string)
            #else
            UIPasteboard.general.string = gedcom
            #endif
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .controlSize(.small)
        .help("Copy GEDCOM to clipboard")
    }

    #if os(macOS)
    private var saveButton: some View {
        Button {
            let panel = NSSavePanel()
            panel.allowedContentTypes  = [.init(filenameExtension: "ged") ?? .plainText]
            panel.nameFieldStringValue = filename
            panel.canCreateDirectories = true
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                try? gedcom.write(to: url, atomically: true, encoding: .utf8)
            }
        } label: {
            Label("Save…", systemImage: "square.and.arrow.down")
        }
        .controlSize(.small)
        .help("Save GEDCOM file…")
    }
    #endif

    // MARK: - Helpers

    private var lineCount: Int {
        gedcom.components(separatedBy: "\n").count
    }
}
