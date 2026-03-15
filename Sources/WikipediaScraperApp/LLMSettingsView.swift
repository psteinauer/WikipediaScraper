import SwiftUI
import WikipediaScraperSharedUI

struct LLMSettingsView: View {
    @ObservedObject private var llm = LLMSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI Analysis", isOn: $llm.isEnabled)
                    .help("Use Claude AI to extract alternate names, titles, facts, events, and influential people from Wikipedia articles.")

                LabeledContent("API Key") {
                    HStack(spacing: 6) {
                        SecureField("sk-ant-…", text: $llm.apiKey)
                            .textFieldStyle(.squareBorder)
                            .frame(maxWidth: 300)
                        if !llm.apiKey.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .imageScale(.small)
                        }
                    }
                }
                .help("Your Anthropic API key. Get one at console.anthropic.com.")

            } header: {
                Label("Claude AI (Anthropic)", systemImage: "wand.and.stars")
                    .font(.headline)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LLM-generated data is stored separately in the GEDCOM file and cited as \u{201C}Claude AI (Anthropic)\u{201D} so it can be distinguished from Wikipedia infobox data.")
                    if llm.isEnabled && llm.apiKey.isEmpty {
                        Label("An API key is required to use AI Analysis.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                            .padding(.top, 2)
                    }
                }
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 220)
    }
}

#Preview {
    LLMSettingsView()
}
