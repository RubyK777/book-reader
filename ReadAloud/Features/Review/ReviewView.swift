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
    @Query(filter: #Predicate<Annotation> { !$0.isSuspended })
    private var annotations: [Annotation]

    @State private var due: [ReviewItem] = []
    @State private var isSessionPresented = false
    @State private var sessionItems: [ReviewItem] = []
    @State private var isSpeakingPresented = false
    @State private var isProgressPresented = false

    private var deck: [ReviewItem] {
        bookmarkedSentences.map(ReviewItem.sentence)
            + annotations.map(ReviewItem.annotation)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isProgressPresented = true } label: {
                        Label("Your progress", systemImage: "chart.bar.xaxis")
                    }
                }
            }
        }
        .task { refresh() }
        .fullScreenCover(isPresented: $isSessionPresented, onDismiss: refresh) {
            ReviewSessionView(items: sessionItems)
        }
        .sheet(isPresented: $isSpeakingPresented) {
            SpeakingPracticeView(items: SRSEngine.buildSession(from: deck))
        }
        .sheet(isPresented: $isProgressPresented) {
            ProgressReflectionView()
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
                    .font(.system(size: DesignSystem.IconSize.xl))
                    .foregroundStyle(DesignSystem.accent)
                    .symbolEffect(.bounce, value: due.count)
                if !due.isEmpty {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        CountUpText(value: due.count)
                        Text("due")
                            .font(.largeTitle.bold())
                    }
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
            .background {
                AnimatedMeshBackground()
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                            .stroke(Theme.cardStroke, lineWidth: 1))
            }
            .padding(.horizontal, DesignSystem.Spacing.screenMargin)

            Spacer()

            VStack(spacing: DesignSystem.Spacing.sm) {
                if !due.isEmpty {
                    Button { startSession(with: due) } label: {
                        Text("Review \(due.count) due")
                    }
                    .buttonStyle(SpringyProminentButtonStyle())
                }

                // Always available — practice the whole deck whenever you want.
                // Prominent when nothing is due (the primary action then), else secondary.
                Button { startSession(with: deck) } label: {
                    Text("Practice all \(deck.count)")
                }
                .buttonStyle(SpringyProminentButtonStyle(prominent: due.isEmpty))

                // Ungraded speaking practice — read the whole deck aloud, hear the model.
                Button { isSpeakingPresented = true } label: {
                    Label("Speaking practice", systemImage: "waveform")
                        .frame(minHeight: DesignSystem.minTapTarget)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, DesignSystem.Spacing.screenMargin)
            .padding(.bottom, DesignSystem.Spacing.lg)
            .sensoryFeedback(.impact, trigger: isSessionPresented)
        }
    }

    private var nextDueText: String {
        guard let next = nextDueDate else { return "Practice any time." }
        if next <= .now { return "Practice any time." }
        return "Next up \(next.relativeNamed) — or practice any time."
    }

    private var emptyState: some View {
        AnimatedEmptyState(
            title: "Your review deck is empty",
            message: "Save a word or bookmark a sentence while you read — it comes back here to review, spaced out over time.",
            systemImage: "brain.head.profile",
            tint: Theme.violet)
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
