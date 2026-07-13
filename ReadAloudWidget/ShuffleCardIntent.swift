import AppIntents

/// Interactive shuffle: tapping the widget's shuffle button runs this intent,
/// after which WidgetKit reloads **only the tapped widget's** timeline — which
/// picks a fresh random card. It deliberately does NOT reload all timelines, so
/// other widget instances stay independent. Runs in the widget process (no app
/// launch); the reload does the work, so `perform` has nothing else to do.
struct ShuffleCardIntent: AppIntent {
    static var title: LocalizedStringResource = "Shuffle card"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        .result()
    }
}
