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
                if !due.isEmpty {
                    dueState
                } else if !deck.isEmpty {
                    nothingDueState
                } else {
                    emptyState
                }
            }
            .navigationTitle("Review")
        }
        .task { refresh() }
        .fullScreenCover(isPresented: $isSessionPresented, onDismiss: refresh) {
            ReviewSessionView(items: SRSEngine.buildSession(from: due))
        }
    }

    // MARK: - States

    private var dueState: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()
            VStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 52))
                    .foregroundStyle(DesignSystem.accent)
                Text("\(due.count) due")
                    .font(.largeTitle.bold())
                    .contentTransition(.numericText())
                Text(due.count == 1 ? "1 card ready to review" : "\(due.count) cards ready to review")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
            .padding(.horizontal, DesignSystem.Spacing.lg)

            Spacer()

            Button {
                isSessionPresented = true
            } label: {
                Text("Start session")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
    }

    private var nothingDueState: some View {
        ContentUnavailableView {
            Label("Nothing due", systemImage: "checkmark.circle")
        } description: {
            if let next = nextDueDate {
                Text("Come back tomorrow — next review \(next.formatted(.relative(presentation: .named))).")
            } else {
                Text("Come back tomorrow.")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No cards yet",
            systemImage: "brain.head.profile",
            description: Text("Bookmark sentences and save words in the Reader to build your deck."))
    }

    // MARK: - Helpers

    private func refresh() {
        due = SRSEngine.dueItems(in: modelContext)
        router.recomputeDueCount(in: modelContext)
    }
}
