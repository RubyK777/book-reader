import AppIntents

/// What slice of the saved deck a widget instance draws from. Beyond being a
/// useful choice, giving the widget an `AppIntentConfiguration` (vs the old
/// `StaticConfiguration`) is what makes multiple instances **independent**: each
/// placed widget gets its own configuration + timeline, so shuffling one no
/// longer reloads the others, and two widgets can show different cards
/// (DECISIONS #66).
enum WidgetCategory: String, AppEnum {
    case all, words, phrases, sentences

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Show" }

    static var caseDisplayRepresentations: [WidgetCategory: DisplayRepresentation] {
        [.all: "Everything",
         .words: "Words",
         .phrases: "Phrases",
         .sentences: "Sentences"]
    }

    /// Does this saved card belong in the chosen slice? (`WidgetCard.type` is the
    /// raw AnnotationType string.)
    func matches(_ card: WidgetCard) -> Bool {
        switch self {
        case .all: true
        case .words: card.type == "word"
        case .phrases: card.type == "phrase"
        case .sentences: card.type == "sentence"
        }
    }
}

/// Per-widget configuration (the "Show" picker in the widget's edit sheet).
struct ReviewCardConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Review Card"
    static var description = IntentDescription("Pick what this widget draws from.")

    @Parameter(title: "Show", default: .all)
    var category: WidgetCategory
}
