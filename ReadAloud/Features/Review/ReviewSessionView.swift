import SwiftUI
import SwiftData

/// Listen-first flashcard session (PHASE3_DESIGN §2). Each card auto-plays its
/// prompt via `SpeechPlayer`; the reviewer recalls, reveals, then grades. A
/// grade of "Again" re-enqueues the item once at the tail. Reaching the end
/// shows a summary. All grading persists immediately via `SRSEngine.grade`.
struct ReviewSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case recall, revealed, summary }

    @State private var queue: [ReviewItem]
    @State private var index = 0
    @State private var phase: Phase = .recall
    @State private var tally: [ReviewGrade: Int] = [:]
    @State private var requeuedIDs: Set<PersistentIdentifier> = []
    @State private var player = SpeechPlayer()
    @State private var showEndConfirm = false
    @State private var remainingDue = 0

    init(items: [ReviewItem]) {
        _queue = State(initialValue: items)
    }

    private var current: ReviewItem? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if phase == .summary || current == nil {
                    summaryView
                } else if let item = current {
                    cardView(item)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if phase != .summary {
                        Button {
                            showEndConfirm = true
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("End session")
                    }
                }
            }
            .confirmationDialog("End session?", isPresented: $showEndConfirm, titleVisibility: .visible) {
                Button("End session", role: .destructive) { finish() }
                Button("Keep reviewing", role: .cancel) {}
            } message: {
                Text("Cards you've already graded keep their progress.")
            }
        }
    }

    // MARK: - Card

    @ViewBuilder
    private func cardView(_ item: ReviewItem) -> some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Text("\(index + 1) of \(queue.count)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            if phase == .recall {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(DesignSystem.accent)
                    .accessibilityLabel("Listen to the prompt")

                Button {
                    speak(item.promptText, item.languageCode)
                } label: {
                    Label("Replay", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            } else {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Text(item.revealText)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)

                    if let context = item.contextText, !context.isEmpty {
                        VStack(spacing: DesignSystem.Spacing.sm) {
                            Text(context)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button {
                                speak(context, item.languageCode)
                            } label: {
                                Label("Play sentence", systemImage: "speaker.wave.2")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
            }

            Spacer()

            if phase == .recall {
                Button {
                    withAnimation { phase = .revealed }
                } label: {
                    Text("Reveal answer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                gradeButtons(item)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .task(id: index) {
            speak(item.promptText, item.languageCode)
        }
    }

    private func gradeButtons(_ item: ReviewItem) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            ForEach(ReviewGrade.allCases) { grade in
                Button {
                    submit(grade, item)
                } label: {
                    Text(grade.label)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("Grade \(grade.label)")
            }
        }
    }

    // MARK: - Summary

    private var summaryView: some View {
        let total = tally.values.reduce(0, +)
        return VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(DesignSystem.accent)

            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("Session complete")
                    .font(.title2.bold())
                Text(total == 1 ? "1 card reviewed" : "\(total) cards reviewed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(ReviewGrade.allCases) { grade in
                    HStack {
                        Text(grade.label)
                        Spacer()
                        Text("\(tally[grade] ?? 0)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .padding(.horizontal, DesignSystem.Spacing.lg)

            Spacer()

            VStack(spacing: DesignSystem.Spacing.sm) {
                if remainingDue > 0 {
                    Button {
                        startMore()
                    } label: {
                        Text("Review \(remainingDue) more")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else if let next = nextDueDate() {
                    Text("Next review \(next.formatted(.relative(presentation: .named)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if remainingDue > 0 {
                    Button { finish() } label: {
                        Text("Done").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    Button { finish() } label: {
                        Text("Done").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
    }

    // MARK: - Actions

    private func speak(_ text: String, _ languageCode: String) {
        player.load(sentences: [text], languageCode: languageCode)
        player.play(at: 0)
    }

    private func submit(_ grade: ReviewGrade, _ item: ReviewItem) {
        SRSEngine.grade(item, grade, in: modelContext)
        tally[grade, default: 0] += 1
        Haptics.select()

        // "Again" re-enqueues the card once at the tail.
        if grade == .again, !requeuedIDs.contains(item.id) {
            requeuedIDs.insert(item.id)
            queue.append(item)
        }
        advance()
    }

    private func advance() {
        player.stop()
        if index + 1 < queue.count {
            phase = .recall
            index += 1
        } else {
            finishToSummary()
        }
    }

    private func finishToSummary() {
        remainingDue = SRSEngine.dueCount(in: modelContext)
        router.recomputeDueCount(in: modelContext)
        Haptics.success()
        withAnimation { phase = .summary }
    }

    /// Rebuild a fresh session from whatever is still due.
    private func startMore() {
        let due = SRSEngine.dueItems(in: modelContext)
        queue = SRSEngine.buildSession(from: due)
        index = 0
        phase = .recall
        tally = [:]
        requeuedIDs = []
    }

    private func finish() {
        player.stop()
        router.recomputeDueCount(in: modelContext)
        dismiss()
    }

    /// Soonest due date across the whole deck, for the "Next review" line.
    private func nextDueDate() -> Date? {
        var dates: [Date] = []
        let sentenceFetch = FetchDescriptor<Sentence>(predicate: #Predicate { $0.isBookmarked })
        if let sentences = try? modelContext.fetch(sentenceFetch) {
            dates += sentences.map { $0.srs?.dueDate ?? .distantPast }
        }
        let wordFetch = FetchDescriptor<SavedWord>()
        if let words = try? modelContext.fetch(wordFetch) {
            dates += words.map { $0.srs?.dueDate ?? .distantPast }
        }
        return dates.min()
    }
}
