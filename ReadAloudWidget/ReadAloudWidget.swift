import WidgetKit
import SwiftUI

/// Home-screen widget: how many cards are ready to review, plus a phrase to
/// remember. Reads the App Group snapshot the app writes (`SharedStore`) — no
/// SwiftData in the widget. Tapping opens the app.
struct DueEntry: TimelineEntry {
    let date: Date
    let dueCount: Int
    let phrase: String?
    let translation: String?
}

struct ReadAloudProvider: TimelineProvider {
    func placeholder(in context: Context) -> DueEntry {
        DueEntry(date: Date(), dueCount: 3, phrase: "à tout à l'heure", translation: "see you soon")
    }

    func getSnapshot(in context: Context, completion: @escaping (DueEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DueEntry>) -> Void) {
        // The app reloads timelines on every change; this is just a safety refresh.
        let refresh = Calendar.current.date(byAdding: .hour, value: 2, to: Date())
            ?? Date().addingTimeInterval(7200)
        completion(Timeline(entries: [current()], policy: .after(refresh)))
    }

    private func current() -> DueEntry {
        DueEntry(date: Date(),
                 dueCount: SharedStore.dueCount(),
                 phrase: SharedStore.phrase(),
                 translation: SharedStore.phraseTranslation())
    }
}

struct ReadAloudWidgetEntryView: View {
    var entry: DueEntry
    @Environment(\.widgetFamily) private var family

    /// Approximate the app's ink-blue accent (the widget can't see app tokens).
    private let ink = Color(red: 0.17, green: 0.23, blue: 0.44)

    var body: some View {
        switch family {
        case .systemSmall: small
        default: medium
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(ink)
            Spacer()
            Text("\(entry.dueCount)")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(dueLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(ink)
                Spacer()
                Text("\(entry.dueCount)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text(dueLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Remember")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if let phrase = entry.phrase, !phrase.isEmpty {
                    Text(phrase)
                        .font(.headline)
                        .fontDesign(.serif)
                        .lineLimit(3)
                    if let translation = entry.translation, !translation.isEmpty {
                        Text(translation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else {
                    Text("Save a word while you read — it shows up here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var dueLabel: String {
        entry.dueCount == 1 ? "card ready" : "cards ready"
    }
}

struct ReadAloudWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReadAloudReviewWidget", provider: ReadAloudProvider()) { entry in
            ReadAloudWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Review")
        .description("Cards ready to review, and a phrase to remember.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ReadAloudWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadAloudWidget()
    }
}
