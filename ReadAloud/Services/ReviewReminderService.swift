import UserNotifications

/// A single, gentle local notification for when the next review cards come due
/// (docs/IMPROVEMENTS §engagement). Exactly one pending nudge at a time — never
/// daily streak pings (anti-gamification, DECISIONS #39). Pure wrapper over
/// `UNUserNotificationCenter`: no SwiftUI, no app models, no stored preference
/// (the enabled flag lives in the view layer and is passed in as behaviour).
enum ReviewReminderService {
    private static let identifier = "review-due-reminder"

    /// Ask once for permission to post the nudge. Returns whether it's allowed.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replace any pending reminder with one soft nudge at `date`. A nil or past
    /// date just cancels — if cards are already due, the app badge covers it and
    /// there's nothing to wait for. `sourceTitle` warms the copy when known.
    static func reschedule(at date: Date?, sourceTitle: String?) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let date, date > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Ready when you are"
        content.body = sourceTitle.map { "A few cards from \($0) are ready to review." }
            ?? "A few cards are ready to review."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(60, date.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// Drop any pending reminder (reminders turned off).
    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
