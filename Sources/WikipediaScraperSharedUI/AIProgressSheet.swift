import SwiftUI

// MARK: - Data model

/// One entry per Wikipedia article being analysed by the AI.
public struct AIProgressEntry: Identifiable, Equatable {
    public let id   = UUID()
    public let title: String        // Wikipedia article title
    public var steps: [String]      // completed steps (shown as a log)
    public var isDone: Bool         // true when the API round-trip is finished
    public var failed: Bool         // true when an error occurred

    public init(title: String) {
        self.title = title
        self.steps = []
        self.isDone = false
        self.failed = false
    }
}

// MARK: - Sheet view

/// A sheet that shows real-time AI analysis progress for one or more articles.
public struct AIProgressSheet: View {
    @Binding public var entries: [AIProgressEntry]
    @Binding public var isPresented: Bool
    public var isComplete: Bool

    public init(
        entries:     Binding<[AIProgressEntry]>,
        isPresented: Binding<Bool>,
        isComplete:  Bool
    ) {
        self._entries     = entries
        self._isPresented = isPresented
        self.isComplete   = isComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(entries) { entry in
                            entryRow(entry)
                                .id(entry.id)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: entries) { _ in
                    if let last = entries.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            if !isComplete {
                Divider()
                footer
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 300, idealHeight: 420)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(Color.accentColor)
            Text("AI Analysis")
                .font(.headline)
            Spacer()
            if isComplete {
                Button("Done") { isPresented = false }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Per-article row

    @ViewBuilder
    private func entryRow(_ entry: AIProgressEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Article title + status icon
            HStack(spacing: 6) {
                Group {
                    if entry.failed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    } else if entry.isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    }
                }
                Text(entry.title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }

            // Step log
            if !entry.steps.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(entry.steps.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .top, spacing: 6) {
                            // Last step gets a spinner if not yet done
                            if !entry.isDone && !entry.failed && step == entry.steps.last {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                            } else {
                                Circle()
                                    .fill(Color.secondary.opacity(0.5))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                            }
                            Text(step)
                                .font(.caption)
                                .foregroundStyle(
                                    (entry.isDone || entry.failed) || step != entry.steps.last
                                    ? AnyShapeStyle(Color.secondary)
                                    : AnyShapeStyle(Color.primary)
                                )
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, 22)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            let active = entries.filter { !$0.isDone && !$0.failed }
            if active.count == 1, let e = active.first {
                Text("Analysing \(e.title)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if active.count > 1 {
                Text("Analysing \(active.count) articles…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Working…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
