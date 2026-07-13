import WidgetKit
import SwiftUI
import AppIntents

/// Home-screen review-card widget: a random saved word/phrase/sentence with its
/// meaning. Tap the shuffle button to switch to another card. Reads the App
/// Group snapshot the app writes (`SharedStore`) — no SwiftData in the widget.
struct CardEntry: TimelineEntry {
    let date: Date
    let card: WidgetCard?
}

struct ReadAloudProvider: TimelineProvider {
    func placeholder(in context: Context) -> CardEntry {
        CardEntry(date: Date(), card: WidgetCard(
            text: "à tout à l'heure", meaning: "see you soon",
            note: "À tout à l'heure ! On se voit ce soir.", type: "phrase", languageName: "French"))
    }

    func getSnapshot(in context: Context, completion: @escaping (CardEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CardEntry>) -> Void) {
        // Reloaded by the app on change and by the shuffle button; this is a
        // safety refresh only.
        let refresh = Calendar.current.date(byAdding: .hour, value: 4, to: Date())
            ?? Date().addingTimeInterval(14400)
        completion(Timeline(entries: [current()], policy: .after(refresh)))
    }

    private func current() -> CardEntry {
        CardEntry(date: Date(), card: SharedStore.currentCard())
    }
}

struct ReadAloudWidgetEntryView: View {
    var entry: CardEntry
    @Environment(\.widgetFamily) private var family

    /// Approximate the app's ink-blue accent (the widget can't see app tokens).
    private let ink = Color(red: 0.17, green: 0.23, blue: 0.44)

    var body: some View {
        if let card = entry.card {
            cardView(card)
        } else {
            emptyView
        }
    }

    private func cardView(_ card: WidgetCard) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.type.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ink)
                Spacer()
                shuffleButton
            }

            Spacer(minLength: 0)

            Text(card.text)
                .font(titleFont)
                .fontDesign(.serif)
                .lineLimit(family == .systemSmall ? 3 : 4)
                .minimumScaleFactor(0.7)

            if let meaning = card.meaning, !meaning.isEmpty {
                Text(meaning)
                    .font(family == .systemSmall ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(family == .systemSmall ? 2 : 3)
            }

            // Larger sizes add the note / example / context.
            if family != .systemSmall, let note = card.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(family == .systemLarge ? 4 : 2)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var shuffleButton: some View {
        Button(intent: ShuffleCardIntent()) {
            Image(systemName: "shuffle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Another card")
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "text.book.closed")
                .font(.title2)
                .foregroundStyle(ink)
            Text("Save a word while you read — it shows up here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var titleFont: Font {
        switch family {
        case .systemSmall: .title3.weight(.semibold)
        case .systemLarge: .largeTitle.weight(.semibold)
        default: .title2.weight(.semibold)
        }
    }
}

struct ReadAloudWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReadAloudReviewWidget", provider: ReadAloudProvider()) { entry in
            ReadAloudWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Review card")
        .description("A saved word to remember — tap shuffle for another.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ReadAloudWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadAloudWidget()
    }
}
