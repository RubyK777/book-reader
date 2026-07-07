import SwiftUI
import SwiftData

/// Core screen (PROJECT_PLAN.md §4.3): tappable sentence cards,
/// active card tinted with word-level highlight, playback bar below.
/// Two sources: `.persisted` (a saved ScanPage, with bookmark + save-word
/// affordances) and `.ephemeral` (raw strings, e.g. #Preview) which hides them.
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

    /// Ordered (text, backing sentence?) rows. `sentence` is nil in ephemeral mode.
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

            playbackBar(sentenceCount: rows.count)
        }
        .navigationTitle("Reader")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { player.load(sentences: rows.map(\.text), languageCode: languageCode) }
        .onDisappear { player.stop() }
        .sheet(item: $wordSheetSentence) { sentence in
            SaveWordSheet(sentence: sentence, languageCode: languageCode)
        }
    }

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

private struct SentenceCard: View {
    let text: String
    let isActive: Bool
    let highlightRange: NSRange?
    let sentence: Sentence?
    let onTap: () -> Void
    /// Nil in ephemeral mode — hides the bookmark star.
    let onToggleBookmark: (() -> Void)?
    /// Nil in ephemeral mode — hides the Save Word context action.
    let onSaveWord: (() -> Void)?

    var body: some View {
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
