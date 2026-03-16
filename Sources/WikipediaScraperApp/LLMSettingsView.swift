import SwiftUI
import WikipediaScraperSharedUI

struct LLMSettingsView: View {
    @ObservedObject private var llm = LLMSettings.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("API Key") {
                    HStack(spacing: 6) {
                        SecureField("sk-ant-…", text: $llm.apiKey)
                            .textFieldStyle(.squareBorder)
                        if !llm.apiKey.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .imageScale(.small)
                        }
                    }
                }
                .help("Your Anthropic API key — get one at console.anthropic.com")
            } header: {
                Label("Claude AI (Anthropic)", systemImage: "wand.and.stars")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use the \u{201C}wand\u{201D} toolbar button to run AI Analysis on fetched articles. AI-generated data is stored separately in the GEDCOM and cited as \u{201C}Claude AI (Anthropic)\u{201D}.")
                    if llm.apiKey.isEmpty {
                        Label("An API key is required to use AI Analysis.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .padding(.top, 2)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 320)
    }
}

#Preview {
    LLMSettingsView()
}
