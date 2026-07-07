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

    /// Persisted page: sentences + affordances come from SwiftData.
    init(page: ScanPage) {
        self.source = .persisted(page)
    }

    /// Ephemeral: plain strings, no persistence affordances.
    init(sentences: [String], languageCode: String) {
        self.source = .ephemeral(sentences, languageCode)
    }

    @Environment(\.modelContext) private var modelContext
    @State private var player = SpeechPlayer()
    @State private var wordSheetSentence: Sentence?

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
                                onSaveWord: row.sentence.map { s in { wordSheetSentence = s } }
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
            playbackBar(sentenceCount: rows.count)
        }
        .navigationTitle("Reader")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { translationToolbar }
        .onAppear {
            player.load(sentences: rows.map(\.text), languageCode: languageCode)
            refreshTranslationConfig()
        }
        .onDisappear { player.stop() }
        .onChange(of: translationTarget) { refreshTranslationConfig() }
        .translationTask(translationConfig) { session in
            await translateMissing(using: session)
        }
        .sheet(item: $wordSheetSentence) { sentence in
            SaveWordSheet(sentence: sentence, languageCode: languageCode)
        }
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
            .foregroundStyle(.orange)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12))
        }
        .buttonStyle(.plain)
    }

    // MARK: Bookmark

    private func toggleBookmark(_ sentence: Sentence) {
        sentence.isBookmarked.toggle()
        if sentence.isBookmarked, sentence.srs == nil {
            sentence.srs = SRSState()
        }
        try? modelContext.save()
        Haptics.bookmark()
    }

    private func playbackBar(sentenceCount: Int) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.minTapTarget) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill")
                }
                .disabled((player.currentSentenceIndex ?? 0) == 0)

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isSpeaking ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                }

                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                }
                .disabled(player.currentSentenceIndex.map { $0 + 1 >= sentenceCount } ?? false)
            }
            .font(.title2)

            HStack {
                Toggle(isOn: $player.repeatMode) {
                    Image(systemName: "repeat")
                }
                .toggleStyle(.button)

                Spacer()

                Picker("Speed", selection: $player.speedMultiplier) {
                    ForEach([0.5, 0.65, 0.75, 0.9, 1.0], id: \.self) { speed in
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

/// What renders under a source card while translation is on.
private enum TranslationLine: Equatable {
    case text(String)
    case loading
}

private enum TranslationIssue: Equatable {
    case failed
    case unsupportedPair

    var message: String {
        switch self {
        case .failed: "Couldn't translate this page — tap to retry."
        case .unsupportedPair: "Translation isn't available for this language pair."
        }
    }
}

private struct SentenceCard: View {
    let text: String
    let isActive: Bool
    let highlightRange: NSRange?
    let sentence: Sentence?
    let translation: TranslationLine?
    let onTap: () -> Void
    /// Nil in ephemeral mode — hides the bookmark star.
    let onToggleBookmark: (() -> Void)?
    /// Nil in ephemeral mode — hides the Save Word context action.
    let onSaveWord: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Text(attributedText)
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }

                if let onToggleBookmark {
                    Button(action: onToggleBookmark) {
                        Image(systemName: (sentence?.isBookmarked ?? false) ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle((sentence?.isBookmarked ?? false) ? Color.yellow : .secondary)
                            .frame(width: DesignSystem.minTapTarget, height: DesignSystem.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel((sentence?.isBookmarked ?? false) ? "Remove bookmark" : "Bookmark sentence")
                }
            }

            if let translation {
                Divider()
                translationView(translation)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(isActive ? Color.accentColor.opacity(0.14) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .strokeBorder(isActive ? Color.accentColor : .clear, lineWidth: 2)
        )
        .scaleEffect(isActive ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isActive)
        .contextMenu {
            if let onSaveWord {
                Button {
                    onSaveWord()
                } label: {
                    Label("Save Word…", systemImage: "text.badge.plus")
                }
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Label("Copy Sentence", systemImage: "doc.on.doc")
                }
            }
        }
    }

    @ViewBuilder
    private func translationView(_ line: TranslationLine) -> some View {
        switch line {
        case let .text(translated):
            Text(translated)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Translation: \(translated)")
        case .loading:
            Text("Translating…")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Translating")
        }
    }

    private var attributedText: AttributedString {
        var attributed = AttributedString(text)
        if let nsRange = highlightRange, let range = Range(nsRange, in: attributed) {
            attributed[range].backgroundColor = .yellow.opacity(0.6)
            attributed[range].font = .title3.bold()
        }
        return attributed
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
}
