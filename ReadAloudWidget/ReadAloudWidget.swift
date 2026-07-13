import WidgetKit
import SwiftUI
import AppIntents

/// Home-screen review-card widget: a random saved word/phrase/sentence with its
/// meaning. Tap shuffle for another. Reads the App Group snapshot (`SharedStore`)
/// — no SwiftData in the widget. It's an **`AppIntentConfiguration`** widget, so
/// each placed instance has its own configuration (`ReviewCardConfiguration`) +
/// timeline: instances are independent (shuffling one leaves the others alone),
/// each picks its own random seed, and each can draw from a different slice
/// (DECISIONS #66).
struct CardEntry: TimelineEntry {
    let date: Date
    let cards: [WidgetCard]
    let seed: Int
    let category: WidgetCategory
}

struct ReadAloudProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CardEntry {
        CardEntry(date: Date(), cards: [WidgetCard(
            text: "à tout à l'heure", meaning: "see you soon",
            note: "À tout à l'heure ! On se voit ce soir.", type: "phrase", languageName: "French")],
            seed: 0, category: .all)
    }

    func snapshot(for configuration: ReviewCardConfiguration, in context: Context) async -> CardEntry {
        current(configuration.category)
    }

    func timeline(for configuration: ReviewCardConfiguration, in context: Context) async -> Timeline<CardEntry> {
        // One entry; a fresh random card comes on each reload (shuffle tap, or
        // when the app refreshes the deck). `.never` keeps the card steady until
        // then rather than auto-rotating.
        Timeline(entries: [current(configuration.category)], policy: .never)
    }

    private func current(_ category: WidgetCategory) -> CardEntry {
        CardEntry(date: Date(), cards: SharedStore.cards(),
                  seed: Int.random(in: 0 ..< 1_000_000), category: category)
    }
}

struct ReadAloudWidgetEntryView: View {
    var entry: CardEntry
    @Environment(\.widgetFamily) private var family

    /// Approximate the app's ink-blue accent (the widget can't see app tokens).
    private let ink = Color(red: 0.17, green: 0.23, blue: 0.44)

    /// Honor the widget's chosen slice first, then keep Small short (no full
    /// sentences). Each filter falls back to the wider pool if it would empty out.
    private var card: WidgetCard? {
        let all = entry.cards
        guard !all.isEmpty else { return nil }
        let chosen = all.filter { entry.category.matches($0) }
        var deck = chosen.isEmpty ? all : chosen
        if family == .systemSmall {
            let short = deck.filter { $0.type != "sentence" }
            if !short.isEmpty { deck = short }
        }
        return deck[abs(entry.seed) % deck.count]
    }

    var body: some View {
        if let card {
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
        AppIntentConfiguration(kind: "ReadAloudReviewWidget",
                               intent: ReviewCardConfiguration.self,
                               provider: ReadAloudProvider()) { entry in
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
