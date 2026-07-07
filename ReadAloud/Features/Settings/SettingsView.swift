import SwiftUI

/// Minimal settings this milestone — native language.
/// Playback speed lives only on the Reader (0.5–2.0×); full settings land later.
struct SettingsView: View {
    @AppStorage("nativeLanguage") private var nativeLanguage = LanguageCatalog.deviceDefaultNative

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
            }
            .navigationTitle("Settings")
        }
    }
}
