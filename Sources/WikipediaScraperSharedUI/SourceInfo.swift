import Foundation

// MARK: - SourceInfo

public struct SourceInfo: Identifiable {
    public static let wikipediaID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    public static let claudeAIID  = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    public enum SourceType { case wikipedia, claudeAI }

    public let id: UUID
    public let type: SourceType
    public let name: String
    public let icon: String
    public let description: String
    public let citedByNames: [String]

    public init(id: UUID, type: SourceType, name: String, icon: String,
                description: String, citedByNames: [String]) {
        self.id            = id
        self.type          = type
        self.name          = name
        self.icon          = icon
        self.description   = description
        self.citedByNames  = citedByNames
    }
}
