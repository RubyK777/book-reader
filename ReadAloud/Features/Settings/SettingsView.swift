import SwiftUI

/// Minimal settings this milestone — default language + speech rate.
/// Full settings land in a later wave.
struct SettingsView: View {
    @AppStorage("targetLanguage") private var targetLanguage = "fr-FR"
    @AppStorage("speechRate") private var speechRate = 0.5

    var body: some View {
        NavigationStack {
            Form {
                Section("Default Language") {
                    Picker("Language", selection: $targetLanguage) {
                        ForEach(SupportedLanguage.all, id: \.code) { language in
                            Text(language.name).tag(language.code)
                        }
                    }
                }

                Section("Playback") {
                    Stepper(value: $speechRate, in: 0.3...0.7, step: 0.05) {
                        Text("Speech rate: \(speechRate, format: .number.precision(.fractionLength(2)))")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
