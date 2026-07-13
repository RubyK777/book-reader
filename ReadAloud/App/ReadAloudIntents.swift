import AppIntents

/// Siri / Shortcuts entry points (DECISIONS #67). Both read/write only the App
/// Group snapshot (`SharedStore`) — no SwiftData in the intents — so "words due"
/// can answer without launching the app, and "start review" just raises a flag
/// the app consumes on activate. Fully offline, like everything else.

/// "How many words are due?" — answered from the count the app writes on every
/// activate; no app launch needed.
struct DueCountIntent: AppIntent {
    static var title: LocalizedStringResource = "Words Due to Review"
    static var description = IntentDescription(
        "How many saved words and sentences are ready to review.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let count = SharedStore.dueCount()
        let message: String = switch count {
        case 0: "You're all caught up — nothing due right now."
        case 1: "You have 1 item ready to review."
        default: "You have \(count) items ready to review."
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// "Start my review" — opens the app to the Review tab and begins a session.
struct StartReviewIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Review"
    static var description = IntentDescription(
        "Open ReadAloud and start reviewing your due cards.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        SharedStore.requestStartReview()   // RootView consumes this on activate
        return .result()
    }
}

/// Zero-config Siri phrases + Shortcuts actions for the two intents.
struct ReadAloudShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartReviewIntent(),
            phrases: ["Start my review in \(.applicationName)",
                      "Review with \(.applicationName)"],
            shortTitle: "Start Review",
            systemImageName: "brain.head.profile")
        AppShortcut(
            intent: DueCountIntent(),
            phrases: ["How many words are due in \(.applicationName)",
                      "What's due in \(.applicationName)"],
            shortTitle: "Words Due",
            systemImageName: "tray.full")
    }
}
