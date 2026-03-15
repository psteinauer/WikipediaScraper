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
        HStack(spacing: 12) {
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
        ScrollView([.horizontal, .vertical]) {
            Text(gedcom)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
