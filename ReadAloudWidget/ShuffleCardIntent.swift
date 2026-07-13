import AppIntents
import WidgetKit

/// Interactive shuffle: tap the widget's shuffle button to draw another random
/// card. Writes a new index into the App Group and reloads the widget. Runs in
/// the widget process — no app launch (iOS 17 interactive widgets).
struct ShuffleCardIntent: AppIntent {
    static var title: LocalizedStringResource = "Shuffle card"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let count = SharedStore.cards().count
        if count > 1 {
            let current = SharedStore.cardIndex()
            var next = Int.random(in: 0 ..< count)
            if next == current { next = (next + 1) % count }   // never repeat the same card
            SharedStore.writeCardIndex(next)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
