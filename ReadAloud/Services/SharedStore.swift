import Foundation

/// One review card shown by the widget — a saved item and its meaning. Encoded
/// into the App Group so the widget can render without touching SwiftData.
struct WidgetCard: Codable, Hashable {
    let text: String        // the saved word / phrase / sentence
    let meaning: String?    // its translation or the user's note
    let note: String?       // an example or the context sentence (larger sizes)
    let type: String        // "word" / "phrase" / "sentence" / "grammar"
    let languageName: String
}

/// A tiny snapshot shared with the widget process through the App Group. The app
/// writes it (on due-count recompute); the widget reads it. Deliberately
/// UserDefaults, not SwiftData — a widget needs a few values, not the store, so
/// this stays simple and robust. Compiled into BOTH the app and widget target.
enum SharedStore {
    static let appGroup = "group.com.rubyhung.ReadAloud"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    private enum Key {
        static let cards = "reviewCards"
    }

    // MARK: Review cards

    static func writeCards(_ cards: [WidgetCard]) {
        let data = try? JSONEncoder().encode(cards)
        defaults?.set(data, forKey: Key.cards)
    }

    static func cards() -> [WidgetCard] {
        guard let data = defaults?.data(forKey: Key.cards),
              let cards = try? JSONDecoder().decode([WidgetCard].self, from: data) else { return [] }
        return cards
    }
}
