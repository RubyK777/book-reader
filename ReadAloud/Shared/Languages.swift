import Foundation
import Vision

/// Language options for the app. Two distinct axes (see DECISIONS.md #25):
///
/// - **Source language** — what's printed on a page. NOT restricted to a
///   hand-picked list: drawn from the languages Vision can actually recognize.
///   Auto-detected per page, correctable, and hintable before capture.
/// - **Native language** — the user's own language (the translation
///   destination). A global preference; uses the same broad set for now and,
///   when translation lands, is filtered by the Translation framework.
///
/// Hearing a language (TTS) and translating it are separately bounded — by
/// installed voices and by translation availability — and are surfaced where
/// they bite rather than used to hide a language here.
enum LanguageCatalog {
    /// BCP-47 codes Vision's `.accurate` text recognizer supports on this device.
    /// (The languages query is a deprecated Vision call, but there is no
    /// synchronous non-deprecated equivalent that returns the `.accurate` set.)
    static let recognitionCodes: [String] = {
        let codes = (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
            for: .accurate, revision: VNRecognizeTextRequest.currentRevision)) ?? []
        return codes.isEmpty ? fallbackCodes : codes
    }()

    /// Picker options `(display name, code)`, sorted by localized name.
    static let options: [(name: String, code: String)] = {
        recognitionCodes
            .map { (name(for: $0), $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    /// Localized display name for a BCP-47 code; falls back to the code itself.
    static func name(for code: String?) -> String {
        guard let code, !code.isEmpty else { return "Language not set" }
        let locale = Locale.current
        if let full = locale.localizedString(forIdentifier: code), full != code { return full }
        let base = String(code.prefix(2))
        return locale.localizedString(forLanguageCode: base) ?? code
    }

    /// Best guess at the user's native language, for the default setting.
    static var deviceDefaultNative: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    /// Safety net if Vision reports nothing (shouldn't happen on device).
    private static let fallbackCodes = [
        "en-US", "fr-FR", "es-ES", "de-DE", "it-IT", "pt-BR", "nl-NL",
        "zh-Hans", "zh-Hant", "ja-JP", "ko-KR", "ru-RU", "uk-UA", "ar-SA", "th-TH", "vi-VN",
    ]
}
