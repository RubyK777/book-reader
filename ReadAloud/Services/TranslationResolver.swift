import Translation

/// The revealed meaning (translation) of a single item, shared by every
/// single-item translate surface (Review session, Saved detail). The Reader's
/// page-batch translation is a different shape and stays in `ReaderView`.
enum TranslationMeaning: Equatable {
    case none, translating, ready(String), unavailable
}

/// Pure translate helper (no SwiftUI, no app models): decide the initial
/// meaning + session config, and map a single-request session response to a
/// meaning. Each view keeps its own `.translationTask`; this removes the
/// duplicated decision/mapping logic (was copied in ReviewSession + SavedDetail).
enum TranslationResolver {
    /// Decide the starting meaning and whether a live translation is needed:
    /// reuse a stored translation, skip when source == native (nothing to
    /// translate), else translate live into the native language.
    static func begin(existing: String?, source: String, native: String)
        -> (meaning: TranslationMeaning, config: TranslationSession.Configuration?) {
        if let existing, !existing.isEmpty { return (.ready(existing), nil) }
        guard !source.hasSameBaseLanguage(as: native) else { return (.unavailable, nil) }
        return (.translating, TranslationSession.Configuration(
            source: Locale.Language(identifier: source),
            target: Locale.Language(identifier: native)))
    }

    /// Run a single-string translation and map the result to a meaning.
    @MainActor
    static func resolve(_ session: TranslationSession, text: String) async -> TranslationMeaning {
        do {
            let responses = try await session.translations(
                from: [TranslationSession.Request(sourceText: text)])
            if let translated = responses.first?.targetText, !translated.isEmpty {
                return .ready(translated)
            }
            return .unavailable
        } catch {
            return .unavailable
        }
    }
}
