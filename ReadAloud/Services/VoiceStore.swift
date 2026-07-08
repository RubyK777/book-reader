import AVFoundation

/// Per-language TTS voice preference (AUDIO_DESIGN §6, PHASE3 §4).
///
/// The system default for a language is often the low-quality "compact" voice;
/// this lets the user pick a better installed voice per language and remembers
/// it. Playback resolution ends in the same primary-subtag matching used to
/// list voices, so a stored choice and the fallback can never disagree.
enum VoiceStore {
    private static func key(_ languageCode: String) -> String { "voiceID.\(languageCode)" }

    static func voiceID(for languageCode: String) -> String? {
        UserDefaults.standard.string(forKey: key(languageCode))
    }

    static func setVoiceID(_ id: String?, for languageCode: String) {
        let defaults = UserDefaults.standard
        if let id { defaults.set(id, forKey: key(languageCode)) }
        else { defaults.removeObject(forKey: key(languageCode)) }
    }

    /// Installed voices whose language shares `languageCode`'s primary subtag
    /// ("fr" matches fr-FR, fr-CA…). Exact-region matches first, then higher
    /// quality, then name — so `"zh-Hans"` still finds the zh-CN voices.
    static func voices(for languageCode: String) -> [AVSpeechSynthesisVoice] {
        let base = String(languageCode.prefix(2)).lowercased()
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix(base) }
            .sorted { a, b in
                let aExact = a.language.caseInsensitiveCompare(languageCode) == .orderedSame
                let bExact = b.language.caseInsensitiveCompare(languageCode) == .orderedSame
                if aExact != bExact { return aExact }
                if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
                return a.name < b.name
            }
    }

    /// The voice playback should use: the stored choice if still installed,
    /// else the system default for the language, else the best subtag match.
    static func resolvedVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        if let id = voiceID(for: languageCode),
           let stored = AVSpeechSynthesisVoice(identifier: id) {
            return stored
        }
        return AVSpeechSynthesisVoice(language: languageCode) ?? voices(for: languageCode).first
    }

    /// A short sentence to preview a voice with, in that language.
    static func sampleText(for languageCode: String) -> String {
        switch String(languageCode.prefix(2)).lowercased() {
        case "fr": "Le soleil se couche sur la mer."
        case "es": "El sol se pone sobre el mar."
        case "de": "Die Sonne versinkt im Meer."
        case "it": "Il sole tramonta sul mare."
        case "pt": "O sol se põe sobre o mar."
        case "ja": "太陽が海に沈みます。"
        case "ko": "해가 바다 위로 집니다."
        case "zh": "太阳正落在海面上。"
        default: "The sun sets over the sea."
        }
    }
}

extension AVSpeechSynthesisVoiceQuality {
    /// Human-readable quality tier for the voice picker.
    var label: String {
        switch self {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        case .default: "Standard"
        @unknown default: "Standard"
        }
    }
}
