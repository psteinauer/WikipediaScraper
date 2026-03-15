import Foundation
import Combine

/// Shared, persistent Claude AI settings.
/// Changes are written to UserDefaults immediately and observed by
/// both the main-window UI and the macOS Settings / iPad settings sheet.
public final class LLMSettings: ObservableObject {

    public static let shared = LLMSettings()

    @Published public var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }
    @Published public var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: Keys.apiKey) }
    }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        apiKey    = UserDefaults.standard.string(forKey: Keys.apiKey) ?? ""
    }

    private enum Keys {
        static let enabled = "llm_enabled"
        static let apiKey  = "anthropic_api_key"
    }
}
