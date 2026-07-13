import Foundation

/// A tiny snapshot shared with the widget process through the App Group. The
/// app writes it (on due-count recompute); the widget reads it. Deliberately
/// UserDefaults, not SwiftData — a widget needs a few values, not the store, so
/// this stays simple and robust (no schema/container coupling). This file is
/// compiled into BOTH the app and the widget target.
enum SharedStore {
    static let appGroup = "group.com.rubyhung.ReadAloud"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    private enum Key {
        static let dueCount = "dueCount"
        static let phrase = "phrase"
        static let phraseTranslation = "phraseTranslation"
        static let phraseLanguage = "phraseLanguage"
    }

    // MARK: Due count

    static func writeDueCount(_ count: Int) {
        defaults?.set(count, forKey: Key.dueCount)
    }

    static func dueCount() -> Int {
        defaults?.integer(forKey: Key.dueCount) ?? 0
    }

    // MARK: Phrase to remember

    static func writePhrase(_ text: String?, translation: String?, languageCode: String?) {
        defaults?.set(text, forKey: Key.phrase)
        defaults?.set(translation, forKey: Key.phraseTranslation)
        defaults?.set(languageCode, forKey: Key.phraseLanguage)
    }

    static func phrase() -> String? { defaults?.string(forKey: Key.phrase) }
    static func phraseTranslation() -> String? { defaults?.string(forKey: Key.phraseTranslation) }
    static func phraseLanguage() -> String? { defaults?.string(forKey: Key.phraseLanguage) }
}
