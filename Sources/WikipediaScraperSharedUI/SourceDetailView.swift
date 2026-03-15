import SwiftUI

public struct SourceDetailView: View {
    public let source: SourceInfo

    public init(source: SourceInfo) {
        self.source = source
    }

    public var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: source.icon)
                        .font(.system(size: 36, weight: .thin))
                        .foregroundStyle(.secondary)
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.name)
                            .font(.headline)
                        Text(source.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            if !source.citedByNames.isEmpty {
                Section("Cited By") {
                    ForEach(source.citedByNames, id: \.self) { name in
                        Label(name, systemImage: "person.circle")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
