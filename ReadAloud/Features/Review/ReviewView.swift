import SwiftUI
import SwiftData

/// Review resting screen — three states (PHASE3_DESIGN §2):
///  (a) items due → "N due" + Start session,
///  (b) deck exists but nothing due → next-due date,
///  (c) empty deck → cross-promo to the Reader.
struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router

    // The full deck, reactive to bookmark/save changes — drives states (b)/(c).
    @Query(filter: #Predicate<Sentence> { $0.isBookmarked })
    private var bookmarkedSentences: [Sentence]
    @Query private var savedWords: [SavedWord]

    @State private var due: [ReviewItem] = []
    @State private var isSessionPresented = false
    @State private var sessionItems: [ReviewItem] = []

    private var deck: [ReviewItem] {
        bookmarkedSentences.map(ReviewItem.sentence) + savedWords.map(ReviewItem.word)
    }

    /// Soonest due date across the whole deck (state (b)).
    private var nextDueDate: Date? {
        deck.map(\.srs.dueDate).min()
    }

    var body: some View {
        NavigationStack {
            Group {
                if !deck.isEmpty {
                    deckState
                } else {
                    emptyState
                }
            }
            .navigationTitle("Review")
        }
        .task { refresh() }
        .fullScreenCover(isPresented: $isSessionPresented, onDismiss: refresh) {
            ReviewSessionView(items: sessionItems)
        }
    }

    // MARK: - States

    /// One screen whether or not anything is due: you can always start a
    /// session. Due items get a "smart" review; the whole deck is always
    /// available to practice on demand.
    private var deckState: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()
            VStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 52))
                    .foregroundStyle(DesignSystem.accent)
                if !due.isEmpty {
                    Text("\(due.count) due")
                        .font(.largeTitle.bold())
                        .contentTransition(.numericText())
                    Text(due.count == 1 ? "1 card ready to review" : "\(due.count) cards ready to review")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("All caught up")
                        .font(.largeTitle.bold())
                    Text(nextDueText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
            .padding(.horizontal, DesignSystem.Spacing.lg)

            Spacer()

            VStack(spacing: DesignSystem.Spacing.sm) {
                if !due.isEmpty {
                    Button { startSession(with: due) } label: {
                        Text("Review \(due.count) due")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                // Always available — practice the whole deck whenever you want.
                // Prominent when nothing is due (the primary action then), else secondary.
                if due.isEmpty {
                    Button { startSession(with: deck) } label: {
                        Text("Practice all \(deck.count)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button { startSession(with: deck) } label: {
                        Text("Practice all \(deck.count)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
    }

    private var nextDueText: String {
        guard let next = nextDueDate else { return "Practice any time." }
        if next <= .now { return "Practice any time." }
        return "Next up \(next.formatted(.relative(presentation: .named))) — or practice any time."
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No cards yet",
            systemImage: "brain.head.profile",
            description: Text("Bookmark sentences and save words in the Reader to build your deck."))
    }

    // MARK: - Helpers

    private func startSession(with items: [ReviewItem]) {
        sessionItems = SRSEngine.buildSession(from: items)
        isSessionPresented = true
    }

    private func refresh() {
        due = SRSEngine.dueItems(in: modelContext)
        router.recomputeDueCount(in: modelContext)
    }
}
