import SwiftUI

/// Minimal settings this milestone — native language + speech rate.
/// Full settings land in a later wave.
struct SettingsView: View {
    @AppStorage("nativeLanguage") private var nativeLanguage = LanguageCatalog.deviceDefaultNative
    @AppStorage("speechRate") private var speechRate = 0.5

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Native language", selection: $nativeLanguage) {
                        ForEach(LanguageCatalog.options, id: \.code) { language in
                            Text(language.name).tag(language.code)
                        }
                    }
                } footer: {
                    Text("The language you read fluently. Pages are translated into it; the source language of each book is detected automatically when you scan.")
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
