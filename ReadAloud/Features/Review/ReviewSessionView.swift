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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("nativeLanguage") private var nativeLanguage = LanguageCatalog.deviceDefaultNative

    private enum Phase { case recall, revealed, summary }
    private enum SpeechPhase { case idle, recording, checking }

    @State private var queue: [ReviewItem]
    @State private var index = 0
    @State private var phase: Phase = .recall
    @State private var tally: [ReviewGrade: Int] = [:]
    @State private var requeuedIDs: Set<PersistentIdentifier> = []
    @State private var player = SpeechPlayer()
    @State private var showEndConfirm = false
    @State private var remainingDue = 0
    @State private var showShadowing = false

    // Meaning resolution for the current card.
    @State private var meaning: TranslationMeaning = .none
    @State private var translateConfig: TranslationSession.Configuration?

    @State private var confettiTrigger = 0
    @State private var masteryShown = false

    init(items: [ReviewItem]) {
        _queue = State(initialValue: items)
    }

    private var current: ReviewItem? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    /// Full sentences from this session, deduped — the shadowing material.
    private var shadowableItems: [ReviewItem] {
        var seen = Set<PersistentIdentifier>()
        return queue.filter { item in
            let isSentence: Bool = switch item {
            case .sentence: true
            case let .annotation(a): a.type == .sentence
            case .word: false
            }
            guard isSentence, !seen.contains(item.id) else { return false }
            seen.insert(item.id)
            return true
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
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
                .sheet(isPresented: $showShadowing) {
                    ShadowingPracticeView(items: shadowableItems)
                }

                ConfettiView(trigger: confettiTrigger)
            }
            .overlay(alignment: .top) {
                if masteryShown { masteryBanner }
            }
        }
    }

    /// The "taking root" moment banner — a leaf, a warm line, gone in a beat.
    private var masteryBanner: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "leaf.fill")
                .foregroundStyle(Theme.verdigris)
            VStack(alignment: .leading, spacing: 2) {
                Text("Taking root")
                    .font(.subheadline.weight(.semibold))
                Text("You've really learned this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.verdigris.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .padding(.top, DesignSystem.Spacing.sm)
        .transition(reduceMotion ? .opacity
                    : .move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Taking root. You've really learned this.")
    }

    // MARK: - Card

    @ViewBuilder
    private func cardView(_ item: ReviewItem) -> some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ProgressCounter(current: index + 1, total: queue.count)

            Spacer()

            // FRONT — varies by card face (D4: meaning / listening / cloze).
            frontView(item)
                .padding(.horizontal, DesignSystem.Spacing.md)

            // BACK: the meaning + note + source sentence.
            if phase == .revealed {
                Divider().padding(.horizontal, DesignSystem.Spacing.xl)
                answerView(item)
                    .padding(.horizontal, DesignSystem.Spacing.md)
            } else {
                Text(recallPrompt(item))
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
            // Cloze must not speak the sentence — it contains the answer.
            if item.face != .cloze {
                speak(item.promptText, item.languageCode)
            }
        }
    }

    @ViewBuilder
    private func frontView(_ item: ReviewItem) -> some View {
        switch item.face {
        case .meaning:
            VStack(spacing: DesignSystem.Spacing.md) {
                Text(item.promptText)
                    .font(item.isWord ? .largeTitle.weight(.bold) : .title2.weight(.semibold))
                    .fontDesign(Theme.sentenceDesign)
                    .multilineTextAlignment(.center)

                Button {
                    speak(item.promptText, item.languageCode)
                } label: {
                    Label("Play", systemImage: "speaker.wave.2.fill")
                        .frame(minHeight: DesignSystem.minTapTarget)
                }
                .buttonStyle(.bordered)
            }

        case .listening:
            VStack(spacing: DesignSystem.Spacing.md) {
                if phase == .revealed {
                    Text(item.revealText)
                        .font(.title2.weight(.semibold))
                        .fontDesign(Theme.sentenceDesign)
                        .multilineTextAlignment(.center)
                } else {
                    Image(systemName: "ear")
                        .font(.system(size: DesignSystem.IconSize.hero))
                        .foregroundStyle(DesignSystem.accent)
                        .accessibilityHidden(true)
                }

                HStack(spacing: DesignSystem.Spacing.md) {
                    Button {
                        speak(item.promptText, item.languageCode)
                    } label: {
                        Label("Play", systemImage: "speaker.wave.2.fill")
                            .frame(minHeight: DesignSystem.minTapTarget)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        player.speakLine(item.promptText, languageCode: item.languageCode, slow: true)
                    } label: {
                        Label("Slow", systemImage: "tortoise.fill")
                            .frame(minHeight: DesignSystem.minTapTarget)
                    }
                    .buttonStyle(.bordered)
                }
            }

        case .cloze:
            VStack(spacing: DesignSystem.Spacing.md) {
                Text(item.clozeText ?? item.promptText)
                    .font(.title3.weight(.medium))
                    .fontDesign(Theme.sentenceDesign)
                    .multilineTextAlignment(.center)

                if phase == .revealed {
                    Button {
                        speak(item.contextText ?? item.promptText, item.languageCode)
                    } label: {
                        Label("Play sentence", systemImage: "speaker.wave.2.fill")
                            .frame(minHeight: DesignSystem.minTapTarget)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func recallPrompt(_ item: ReviewItem) -> String {
        switch item.face {
        case .meaning: "What does this mean?"
        case .listening: "Listen — what did you hear?"
        case .cloze: "What fills the blank?"
        }
    }

    /// The answer side: translated meaning, the user's note, and (for words)
    /// the source sentence.
    @ViewBuilder
    private func answerView(_ item: ReviewItem) -> some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Cloze: the blanked term is the answer — show it first.
            if item.face == .cloze {
                Text(item.revealText)
                    .font(.title2.weight(.semibold))
                    .fontDesign(Theme.sentenceDesign)
                    .foregroundStyle(DesignSystem.accent)
                    .multilineTextAlignment(.center)
            }

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
                            .frame(minHeight: DesignSystem.minTapTarget)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func gradeButtons(_ item: ReviewItem) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Text("How well did you know it?")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(ReviewGrade.allCases) { grade in
                    Button {
                        submit(grade, item)
                    } label: {
                        VStack(spacing: 2) {
                            Text(grade.label)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(grade.hint)
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .opacity(0.9)
                        }
                        .frame(maxWidth: .infinity, minHeight: DesignSystem.minTapTarget)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(grade.tint.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                        .overlay(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .stroke(grade.tint, lineWidth: 1))
                        .foregroundStyle(grade.tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(grade.label), \(grade.hint)")
                }
            }
        }
    }

    // MARK: - Summary

    private var summaryView: some View {
        let total = tally.values.reduce(0, +)
        return VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: DesignSystem.IconSize.xl))
                .foregroundStyle(Theme.verdigris)
                .symbolEffect(.bounce)

            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("Session complete")
                    .font(.title2.bold())
                Text(total == 1 ? "You reviewed 1 card" : "You reviewed \(total) cards")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(Array(ReviewGrade.allCases.enumerated()), id: \.element) { index, grade in
                    HStack {
                        Circle()
                            .fill(grade.tint)
                            .frame(width: 8, height: 8)
                        Text(grade.label)
                        Spacer()
                        CountUpText(value: tally[grade] ?? 0,
                                    delay: 0.15 * Double(index),
                                    font: .body.monospacedDigit())
                    }
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .padding(.horizontal, DesignSystem.Spacing.screenMargin)

            Spacer()

            VStack(spacing: DesignSystem.Spacing.sm) {
                // Ungraded shadowing practice on the session's full sentences
                // (PIVOT_PLAN Phase 3 — never interrupts the graded flow).
                if !shadowableItems.isEmpty {
                    Button {
                        showShadowing = true
                    } label: {
                        Label("Practice speaking (\(shadowableItems.count))",
                              systemImage: "mic")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

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
                } else if let next = SRSEngine.nextDue(in: modelContext)?.date {
                    Text("Next review \(next.relativeNamed)")
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
            .padding(.horizontal, DesignSystem.Spacing.screenMargin)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
    }

    // MARK: - Actions

    private func speak(_ text: String, _ languageCode: String) {
        player.speakLine(text, languageCode: languageCode)
    }

    /// Flip to the answer and resolve its meaning: reuse a stored translation,
    /// skip when the source is already the native language, else translate live.
    private func reveal(_ item: ReviewItem) {
        withAnimation { phase = .revealed }
        (meaning, translateConfig) = TranslationResolver.begin(
            existing: item.existingTranslation,
            source: item.languageCode,
            native: nativeLanguage)
    }

    @MainActor
    private func translateCurrent(using session: TranslationSession) async {
        guard let item = current else { return }
        meaning = await TranslationResolver.resolve(session, text: item.promptText)
        // Opportunistic cache: keep the translation the app just computed.
        if case let .ready(text) = meaning {
            item.cacheTranslation(text)
            try? modelContext.save()
        }
    }

    private func submit(_ grade: ReviewGrade, _ item: ReviewItem) {
        let outcome = SRSEngine.grade(item, grade, in: modelContext)
        tally[grade, default: 0] += 1
        Haptics.select()

        // "Again" re-enqueues the card once at the tail.
        if grade == .again, !requeuedIDs.contains(item.id) {
            requeuedIDs.insert(item.id)
            queue.append(item)
        }
        // One-shot "taking root" moment the first time an item matures.
        if outcome.justMatured { markTakingRoot() }
        advance()
    }

    /// A tasteful, one-time growth marker when a card first reaches memory
    /// maturity — not a streak or score (DECISIONS #39). Auto-dismisses.
    private func markTakingRoot() {
        Haptics.success()
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4)) {
            masteryShown = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeOut(duration: 0.4)) { masteryShown = false }
        }
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
        withAnimation { phase = .summary }
        confettiTrigger += 1
        Haptics.celebrate()
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
}
