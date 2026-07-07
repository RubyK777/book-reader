import Foundation

/// The nine languages ReadAloud supports. `code` is full BCP-47.
/// Shared by the scan flow, book form, and OCR review.
enum SupportedLanguage {
    static let all: [(name: String, code: String)] = [
        ("French", "fr-FR"),
        ("Spanish", "es-ES"),
        ("German", "de-DE"),
        ("Italian", "it-IT"),
        ("Portuguese", "pt-PT"),
        ("Japanese", "ja-JP"),
        ("Korean", "ko-KR"),
        ("Chinese (Simplified)", "zh-Hans"),
        ("English", "en-US"),
    ]

    /// Display name for a BCP-47 code; matches on the language subtag
    /// so "fr" resolves to "French". Falls back to a placeholder.
    static func name(for code: String?) -> String {
        guard let code else { return "Language not set" }
        if let exact = all.first(where: { $0.code == code }) { return exact.name }
        let base = String(code.prefix(2)).lowercased()
        if let loose = all.first(where: { $0.code.lowercased().hasPrefix(base) }) {
            return loose.name
        }
        return code
    }
}
