import SwiftUI
import SwiftData
import WidgetKit

/// Root tabs.
enum AppTab: Hashable {
    case library, saved, review, notes, settings
}

/// App-wide navigation state, injected via `.environment`.
@Observable
final class AppRouter {
    var tab: AppTab = .library
    var libraryPath = NavigationPath()
    var isScanFlowPresented = false

    /// Number of items due for review; drives the Review tab badge.
    private(set) var dueCount = 0

    @MainActor
    func recomputeDueCount(in context: ModelContext) {
        dueCount = SRSEngine.dueCount(in: context)
        updateWidgetSnapshot(in: context)
    }

    /// Refresh the home-screen widget's card deck: encode recent saved items
    /// (word/phrase/sentence + meaning + note) into the App Group and reload
    /// timelines. The widget shows one at a time and shuffles between them.
    @MainActor
    private func updateWidgetSnapshot(in context: ModelContext) {
        var descriptor = FetchDescriptor<Annotation>(sortBy: [SortDescriptor(\.savedAt, order: .reverse)])
        descriptor.fetchLimit = 40
        let annotations = (try? context.fetch(descriptor)) ?? []

        var cards: [WidgetCard] = annotations.map { annotation in
            let contextLine = annotation.contextSentence == annotation.text ? nil : annotation.contextSentence
            return WidgetCard(
                text: annotation.text,
                meaning: annotation.translation.nonBlank
                    ?? annotation.userNote.nonBlank
                    ?? annotation.sentence?.translatedText,
                note: annotation.userExample.nonBlank ?? contextLine,
                type: annotation.type.rawValue,
                languageName: LanguageCatalog.name(for: annotation.languageCode))
        }

        // Starred (bookmarked) sentences from the Reader — shown on medium/large.
        var seen = Set(cards.map(\.text))
        let bookmarked = (try? context.fetch(
            FetchDescriptor<Sentence>(predicate: #Predicate { $0.isBookmarked }))) ?? []
        for sentence in bookmarked where !seen.contains(sentence.text) {
            seen.insert(sentence.text)
            cards.append(WidgetCard(
                text: sentence.text,
                meaning: sentence.translatedText.nonBlank,
                note: nil,
                type: AnnotationType.sentence.rawValue,
                languageName: LanguageCatalog.name(for: sentence.page?.book?.languageCode ?? "en-US")))
        }
        SharedStore.writeCards(cards)
        // Each widget instance picks its own random card from this deck.
        WidgetCenter.shared.reloadAllTimelines()
    }
}
