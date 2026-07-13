import SwiftUI
import SwiftData
import Translation

/// Core screen (PROJECT_PLAN.md §4.3): tappable sentence cards,
/// active card tinted with word-level highlight, playback bar below.
/// Two sources: `.persisted` (a saved ScanPage, with bookmark + save-word +
/// translation) and `.ephemeral` (raw strings, e.g. #Preview) which hides them.
///
/// Translation (TRANSLATION_DESIGN): a persisted page whose Book has a
/// `translationLanguage` batch-translates its sentences once via the iOS 18
/// Translation framework, persists them, and shows them under each source line.
/// TTS always speaks the SOURCE only.
struct ReaderView: View {
    private enum Source {
        case persisted(ScanPage)
        case ephemeral([String], String)
    }

    private let source: Source

    /// Persisted page: sentences + affordances come from SwiftData. Audio pages
    /// play the real recording; text pages use TTS.
    init(page: ScanPage) {
        self.source = .persisted(page)
        _player = State(initialValue: Self.makePlayer(for: page))
    }

    /// Ephemeral: plain strings, no persistence affordances.
    init(sentences: [String], languageCode: String) {
        self.source = .ephemeral(sentences, languageCode)
        _player = State(initialValue: SpeechPlayer(managesNowPlaying: true))
    }

    /// A conversation page (`audioData`) gets the real-audio `RecordingPlayer`,
    /// seeked by each sentence's stored `[start, end]`; everything else uses TTS.
    private static func makePlayer(for page: ScanPage) -> any SentencePlaying {
        if let data = page.audioData {
            let sorted = page.sentences.sorted { $0.orderIndex < $1.orderIndex }
            let duration = page.audioDuration ?? 0
            let ranges: [(start: Double, end: Double)] = sorted.map { sentence in
                (start: sentence.audioStart ?? 0, end: sentence.audioEnd ?? duration)
            }
            let wordTimings: [[WordTiming]] = sorted.map { $0.wordTimings ?? [] }
            return RecordingPlayer(audioData: data, ranges: ranges, wordTimings: wordTimings,
                                   managesNowPlaying: true)
        }
        return SpeechPlayer(managesNowPlaying: true)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    // The Reader's player: TTS for text pages, real audio for conversation pages.
    // The TTS player owns the lock-screen Now Playing + remote controls.
    @State private var player: any SentencePlaying
    @State private var wordSheetSentence: Sentence?
    @State private var editingSentence: Sentence?
    @State private var sentenceToDelete: Sentence?
    @State private var learnSentence: Sentence?

    // After-session digest (PIVOT_PLAN Phase 4): what got saved while this
    // Reader was open, with a one-tap path into reviewing it.
    @State private var sessionStart = Date.distantFuture
    @State private var digestDismissed = false
    @State private var reviewingDigest = false

    // Translation
    @AppStorage("nativeLanguage") private var nativeLanguage = LanguageCatalog.deviceDefaultNative
    @AppStorage("showTranslations") private var showTranslations = true
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var translationIssue: TranslationIssue?

    private var page: ScanPage? {
        if case let .persisted(page) = source { return page }
        return nil
    }
    private var book: Book? { page?.book }
    private var translationTarget: String? { book?.translationLanguage }

    /// Shown on the lock screen while this page plays.
    private var playerTitle: String { book?.title ?? "ReadAloud" }

    /// Ordered sentence rows. `sentence` is nil in ephemeral mode.
    private var rows: [(text: String, sentence: Sentence?)] {
        switch source {
        case let .persisted(page):
            return page.sentences
                .sorted { $0.orderIndex < $1.orderIndex }
                .map { ($0.text, $0) }
        case let .ephemeral(sentences, _):
            return sentences.map { ($0, nil) }
        }
    }

    private var languageCode: String {
        switch source {
        case let .persisted(page):
            // Source (spoken) language — a persisted page's book language is
            // set at first scan; the fallback is defensive, never the user's
            // native language (that's the translation destination, not the source).
            return page.book?.languageCode ?? "en-US"
        case let .ephemeral(_, code):
            return code
        }
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.md) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            SentenceCard(
                                text: row.text,
                                isActive: player.currentSentenceIndex == index,
                                highlightRange: player.currentSentenceIndex == index ? player.highlightRange : nil,
                                sentence: row.sentence,
                                translation: translationLine(for: row.sentence),
                                onTap: { player.play(at: index) },
                                onToggleBookmark: row.sentence.map { s in { toggleBookmark(s) } },
                                onSaveWord: row.sentence.map { s in { wordSheetSentence = s } },
                                onEdit: row.sentence.map { s in { editingSentence = s } },
                                onDelete: row.sentence.map { s in { sentenceToDelete = s } },
                                onLearn: row.sentence.map { s in { player.stop(); learnSentence = s } }
                            )
                            .id(index)
                        }
                    }
                    .padding(DesignSystem.Spacing.md)
                }
                .onChange(of: player.currentSentenceIndex) {
                    guard let index = player.currentSentenceIndex else { return }
                    withAnimation { proxy.scrollTo(index, anchor: .center) }
                }
            }

            if let translationIssue, translationTarget != nil {
                translationIssueRow(translationIssue)
            }
            if !sessionAnnotations.isEmpty && !digestDismissed {
                digestBar
            }
            playbackBar(sentenceCount: rows.count)
        }
        .navigationTitle("Reader")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { translationToolbar }
        .onAppear {
            player.load(sentences: rows.map(\.text), languageCode: languageCode, title: playerTitle)
            refreshTranslationConfig()
            if sessionStart == .distantFuture { sessionStart = .now }
        }
        .onDisappear { player.stop() }
        .onChange(of: scenePhase) { if scenePhase == .active { player.reconcile() } }
        .onChange(of: translationTarget) { refreshTranslationConfig() }
        .translationTask(translationConfig) { session in
            await translateMissing(using: session)
        }
        .sheet(item: $wordSheetSentence) { sentence in
            SaveWordSheet(sentence: sentence, languageCode: languageCode)
        }
        .sheet(item: $learnSentence) { sentence in
            SentenceLearnView(sentence: sentence, languageCode: languageCode)
        }
        .sheet(isPresented: $reviewingDigest) {
            ReviewSessionView(items: sessionAnnotations.map(ReviewItem.annotation))
        }
        .sheet(item: $editingSentence) { sentence in
            EditSentenceSheet(sentence: sentence) { reloadPlayer() }
        }
        .confirmationDialog("Delete this sentence?",
                            isPresented: Binding(get: { sentenceToDelete != nil },
                                                 set: { if !$0 { sentenceToDelete = nil } }),
                            presenting: sentenceToDelete) { sentence in
            Button("Delete", role: .destructive) { deleteSentence(sentence) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the sentence from the page, including any bookmark or review history.")
        }
    }

    /// Reload the player's queue after the page's sentences change (edit/delete).
    private func reloadPlayer() {
        player.load(sentences: rows.map(\.text), languageCode: languageCode, title: playerTitle)
    }

    private func deleteSentence(_ sentence: Sentence) {
        guard case let .persisted(page) = source else { return }
        player.stop()
        let remaining = page.sentences
            .filter { $0.persistentModelID != sentence.persistentModelID }
            .sorted { $0.orderIndex < $1.orderIndex }
        modelContext.delete(sentence)
        for (i, s) in remaining.enumerated() { s.orderIndex = i }   // keep indices contiguous
        try? modelContext.save()
        router.recomputeDueCount(in: modelContext)   // a bookmarked sentence may be gone
        reloadPlayer()
        Haptics.select()
    }

    // MARK: Translation

    /// The line shown under a source card: the persisted translation, or a
    /// "translating…" placeholder while a session is filling the page in.
    private func translationLine(for sentence: Sentence?) -> TranslationLine? {
        guard page != nil, showTranslations, translationTarget != nil,
              let sentence else { return nil }
        if let translated = sentence.translatedText { return .text(translated) }
        return .loading
    }

    private func refreshTranslationConfig() {
        translationIssue = nil
        guard let book, let target = book.translationLanguage, let sourceCode = book.languageCode else {
            translationConfig = nil
            return
        }
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: sourceCode),
            target: Locale.Language(identifier: target))
    }

    @MainActor
    private func translateMissing(using session: TranslationSession) async {
        guard let page else { return }
        let pending = page.sentences
            .sorted { $0.orderIndex < $1.orderIndex }
            .filter { $0.translatedText == nil }
        guard !pending.isEmpty else { return }

        // Correlate by clientIdentifier — batch responses are not guaranteed to
        // return in request order, so never zip by position.
        var byID: [String: Sentence] = [:]
        let requests = pending.map { sentence -> TranslationSession.Request in
            let id = "\(sentence.persistentModelID)"
            byID[id] = sentence
            return TranslationSession.Request(sourceText: sentence.text, clientIdentifier: id)
        }
        do {
            let responses = try await session.translations(from: requests)
            for response in responses {
                if let sentence = byID[response.clientIdentifier ?? ""] {
                    sentence.translatedText = response.targetText
                }
            }
            try modelContext.save()
            translationIssue = nil
        } catch {
            translationIssue = .failed
        }
    }

    /// Set (or clear) a book's translation target. Changing it wipes the book's
    /// now-stale translations; they refill lazily on next Reader open (§4).
    private func setTranslationLanguage(_ new: String?) {
        guard let book, new != book.translationLanguage else { return }
        for page in book.pages {
            for sentence in page.sentences { sentence.translatedText = nil }
        }
        book.translationLanguage = new
        try? modelContext.save()
        refreshTranslationConfig()
    }

    @ToolbarContentBuilder
    private var translationToolbar: some ToolbarContent {
        if page != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showTranslations.toggle()
                } label: {
                    Image(systemName: showTranslations ? "character.book.closed.fill" : "character.book.closed")
                }
                .disabled(translationTarget == nil)
                .accessibilityLabel(showTranslations ? "Hide translations" : "Show translations")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Translate to", selection: translationBinding) {
                        Text("Off").tag(String?.none)
                        // Native language first (the usual destination), then the rest.
                        let native = LanguageCatalog.options.first { $0.code.hasPrefix(nativeLanguage) }
                        if let native {
                            Text("\(native.name) (native)").tag(String?.some(native.code))
                        }
                        ForEach(LanguageCatalog.options.filter { $0.code != native?.code }, id: \.code) { lang in
                            Text(lang.name).tag(String?.some(lang.code))
                        }
                    }
                } label: {
                    Label("Translate to", systemImage: "translate")
                }
            }
        }
    }

    private var translationBinding: Binding<String?> {
        Binding(get: { translationTarget }, set: { setTranslationLanguage($0) })
    }

    private func translationIssueRow(_ issue: TranslationIssue) -> some View {
        Button {
            if issue == .failed { refreshTranslationConfig() }
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(issue.message).font(.footnote)
                Spacer()
            }
            .foregroundStyle(Theme.marigold)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.soft(Theme.marigold))
        }
        .buttonStyle(.plain)
    }

    // MARK: After-session digest (Phase 4)

    /// Annotations saved anywhere on this page since the Reader opened.
    private var sessionAnnotations: [Annotation] {
        guard let page else { return [] }
        return page.sentences
            .flatMap(\.annotations)
            .filter { $0.savedAt >= sessionStart }
            .sorted { $0.savedAt < $1.savedAt }
    }

    /// "2 words · 1 phrase" — counts by type, in a fixed readable order.
    private var digestSummary: String {
        let counts = Dictionary(grouping: sessionAnnotations, by: \.type)
            .mapValues(\.count)
        let order: [AnnotationType] = [.sentence, .phrase, .word, .grammar]
        return order.compactMap { type in
            guard let count = counts[type], count > 0 else { return nil }
            let name = type.rawValue + (count == 1 ? "" : "s")
            return "\(count) \(name)"
        }.joined(separator: " · ")
    }

    private var digestBar: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "bookmark.fill")
                .font(.caption)
                .foregroundStyle(Theme.accent)
            Text("Kept this session: \(digestSummary)")
                .font(.footnote)
                .lineLimit(1)
            Spacer()
            Button("Review these") { reviewingDigest = true }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
            Button {
                digestDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss — items stay saved and scheduled")
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(Theme.accentSoft)
    }

    // MARK: Bookmark

    private func toggleBookmark(_ sentence: Sentence) {
        sentence.setBookmarked(!sentence.isBookmarked)
        try? modelContext.save()
        router.recomputeDueCount(in: modelContext)
        Haptics.bookmark()
    }

    private func playbackBar(sentenceCount: Int) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.xl) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill")
                        .frame(width: DesignSystem.minTapTarget, height: DesignSystem.minTapTarget)
                }
                .disabled((player.currentSentenceIndex ?? 0) == 0)
                .accessibilityLabel("Previous sentence")

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isSpeaking ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: DesignSystem.IconSize.xl))
                }
                .accessibilityLabel(player.isSpeaking ? "Pause" : "Play")

                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .frame(width: DesignSystem.minTapTarget, height: DesignSystem.minTapTarget)
                }
                .disabled(player.currentSentenceIndex.map { $0 + 1 >= sentenceCount } ?? false)
                .accessibilityLabel("Next sentence")
            }
            .font(.title2)

            HStack {
                Toggle(isOn: Binding(get: { player.repeatMode },
                                     set: { player.repeatMode = $0 })) {
                    Image(systemName: "repeat")
                }
                .toggleStyle(.button)

                Spacer()

                Picker("Speed", selection: Binding(get: { player.speedMultiplier },
                                                   set: { player.speedMultiplier = $0 })) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                        Text("\(speed, specifier: "%.2g")×").tag(Float(speed))
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md - DesignSystem.Spacing.xs)
        .background(.bar)
    }
}

#Preview {
    NavigationStack {
        ReaderView(
            sentences: [
                "Le petit prince vivait sur une planète à peine plus grande qu'une maison.",
                "Il regardait le coucher du soleil chaque soir.",
                "Un jour, il décida de partir en voyage.",
            ],
            languageCode: "fr-FR"
        )
    }
    .environment(AppRouter())
}
