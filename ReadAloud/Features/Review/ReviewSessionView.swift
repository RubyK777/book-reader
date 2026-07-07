import SwiftUI
import SwiftData
import Translation

/// Recognition flashcard session (PHASE3_DESIGN §2). The FRONT shows the
/// foreign word/sentence (read it, hear it); the reviewer recalls its meaning,
/// then reveals the BACK — the translation into their native language, plus
/// their note and (for words) the source sentence. A grade of "Again"
/// re-enqueues the item once at the tail; the end shows a summary. Grading
/// persists immediately via `SRSEngine.grade`.
struct ReviewSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nativeLanguage") private var nativeLanguage = LanguageCatalog.deviceDefaultNative

    private enum Phase { case recall, revealed, summary }

    /// The revealed meaning (translation) for the current card.
    private enum Meaning: Equatable { case none, translating, ready(String), unavailable }

    @State private var queue: [ReviewItem]
    @State private var index = 0
    @State private var phase: Phase = .recall
    @State private var tally: [ReviewGrade: Int] = [:]
    @State private var requeuedIDs: Set<PersistentIdentifier> = []
    @State private var player = SpeechPlayer()
    @State private var showEndConfirm = false
    @State private var remainingDue = 0

    // Meaning resolution for the current card.
    @State private var meaning: Meaning = .none
    @State private var translateConfig: TranslationSession.Configuration?

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
            .translationTask(translateConfig) { session in
                await translateCurrent(using: session)
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

            // FRONT: the foreign word/sentence — read it and hear it, recall the meaning.
            VStack(spacing: DesignSystem.Spacing.md) {
                Text(item.promptText)
                    .font(item.isWord ? .largeTitle.weight(.bold) : .title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Button {
                    speak(item.promptText, item.languageCode)
                } label: {
                    Label("Play", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)

            // BACK: the meaning + note + source sentence.
            if phase == .revealed {
                Divider().padding(.horizontal, DesignSystem.Spacing.xl)
                answerView(item)
                    .padding(.horizontal, DesignSystem.Spacing.md)
            } else {
                Text("What does this mean?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if phase == .recall {
                Button {
                    reveal(item)
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

    /// The answer side: translated meaning, the user's note, and (for words)
    /// the source sentence.
    @ViewBuilder
    private func answerView(_ item: ReviewItem) -> some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            switch meaning {
            case .translating:
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Translating…").foregroundStyle(.secondary)
                }
            case let .ready(text):
                Text(text)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(DesignSystem.accent)
                    .multilineTextAlignment(.center)
            case .unavailable:
                if item.note == nil || item.note?.isEmpty == true {
                    Text("No translation available for this language")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .none:
                EmptyView()
            }

            if let note = item.note, !note.isEmpty {
                VStack(spacing: DesignSystem.Spacing.xs) {
                    Text("Your note")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(note)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }
            }

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

    /// Flip to the answer and resolve its meaning: reuse a stored translation,
    /// skip when the source is already the native language, else translate live.
    private func reveal(_ item: ReviewItem) {
        withAnimation { phase = .revealed }

        if let existing = item.existingTranslation, !existing.isEmpty {
            meaning = .ready(existing)
            return
        }
        let sourceBase = String(item.languageCode.prefix(2)).lowercased()
        let nativeBase = String(nativeLanguage.prefix(2)).lowercased()
        guard sourceBase != nativeBase else {
            meaning = .unavailable   // already in the reader's language — nothing to translate
            return
        }
        meaning = .translating
        translateConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: item.languageCode),
            target: Locale.Language(identifier: nativeLanguage))
    }

    @MainActor
    private func translateCurrent(using session: TranslationSession) async {
        guard let item = current else { return }
        do {
            let responses = try await session.translations(
                from: [TranslationSession.Request(sourceText: item.promptText)])
            if let text = responses.first?.targetText, !text.isEmpty {
                meaning = .ready(text)
            } else {
                meaning = .unavailable
            }
        } catch {
            meaning = .unavailable
        }
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
        meaning = .none
        translateConfig = nil
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
        meaning = .none
        translateConfig = nil
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
