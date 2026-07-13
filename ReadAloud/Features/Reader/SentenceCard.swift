import SwiftUI
import UIKit

/// What renders under a source card while translation is on.
enum TranslationLine: Equatable {
    case text(String)
    case loading
}

enum TranslationIssue: Equatable {
    case failed
    case unsupportedPair

    var message: String {
        switch self {
        case .failed: "Couldn't translate this page — tap to try again."
        case .unsupportedPair: "Translation isn't offered for this language pair yet."
        }
    }
}

/// One sentence row in the Reader: the (optionally word-highlighted) source text
/// with its translation line, plus per-sentence actions (Learn, bookmark, and a
/// context menu). All actions are optional closures — nil hides them, which is
/// how the ephemeral (unsaved) Reader mode drops save/edit/delete affordances.
struct SentenceCard: View {
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
    /// Nil in ephemeral mode — hides Edit/Delete of the sentence.
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    /// Nil in ephemeral mode — hides the Learn drill-down (product design Phase 2).
    let onLearn: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Text(attributedText)
                    .font(Theme.sentenceFont)
                    .fontDesign(Theme.sentenceDesign)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }

                if let onLearn {
                    Button(action: onLearn) {
                        Image(systemName: "graduationcap")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: DesignSystem.minTapTarget, height: DesignSystem.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Learn this sentence")
                }

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
        .learningCard(active: isActive)
        .scaleEffect(reduceMotion ? 1.0 : (isActive ? 1.02 : 1.0))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isActive)
        .contextMenu {
            if let onLearn {
                Button {
                    onLearn()
                } label: {
                    Label("Learn Sentence…", systemImage: "graduationcap")
                }
            }
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
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit Sentence", systemImage: "pencil")
                }
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Sentence", systemImage: "trash")
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
            attributed[range].backgroundColor = Theme.karaoke
            attributed[range].font = Theme.sentenceFont.weight(.bold)
        }
        return attributed
    }
}
