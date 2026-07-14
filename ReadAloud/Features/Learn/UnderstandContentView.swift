import SwiftUI

/// The "Understand" breakdown for a sentence (D1/D2/D7): chunk-by-chunk gloss,
/// key vocabulary with one-tap save, an optional grammar point, and provenance
/// + edit/regenerate/delete controls. Pure presentation — the owning view keeps
/// the state and passes actions in as closures.
struct UnderstandContentView: View {
    let assets: LearningAssets
    /// Whether the sentence already has an annotation for this term.
    let isSaved: (String) -> Bool
    let onSpeak: (String) -> Void
    let onSaveVocab: ([LearningAssets.VocabItem]) -> Void
    let onEdit: () -> Void
    let onRegenerate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            if !assets.chunks.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    ForEach(assets.chunks, id: \.self) { chunk in
                        Button {
                            onSpeak(chunk.text)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                                Image(systemName: "speaker.wave.1")
                                    .font(.caption)
                                    .foregroundStyle(DesignSystem.accent)
                                Text(chunk.text)
                                    .fontWeight(.medium)
                                    .fontDesign(Theme.sentenceDesign)
                                Text(chunk.gloss)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                            }
                            .font(.callout)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(chunk.text), meaning: \(chunk.gloss). Tap to hear.")
                    }
                }
            }

            if !assets.keyVocab.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    HStack {
                        Text("Key vocabulary")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer(minLength: DesignSystem.Spacing.sm)
                        let unsaved = assets.keyVocab.filter { !isSaved($0.term) }
                        if !unsaved.isEmpty {
                            Button {
                                onSaveVocab(unsaved)
                            } label: {
                                Label(unsaved.count == assets.keyVocab.count
                                      ? "Save all" : "Save \(unsaved.count) more",
                                      systemImage: "square.and.arrow.down")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    ForEach(assets.keyVocab, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                            Text(item.term).fontWeight(.medium).fontDesign(Theme.sentenceDesign)
                            Text(item.meaning).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            if isSaved(item.term) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.verdigris)
                                    .accessibilityLabel("Saved")
                            }
                        }
                        .font(.callout)
                    }
                }
            }

            if let grammar = assets.grammarPoint {
                Divider()
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Grammar point")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(grammar).font(.callout)
                }
            }

            Divider()
            HStack(spacing: DesignSystem.Spacing.md) {
                if assets.isGenerated {
                    // D7 provenance: generated content is always visibly marked.
                    Label(assets.userEditedAt == nil
                          ? "AI-generated — check anything that looks off"
                          : "AI-generated, edited by you",
                          systemImage: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Button("Edit") { onEdit() }
                    .font(.caption)
                Menu {
                    Button {
                        onRegenerate()
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete Breakdown", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Breakdown options")
            }
        }
    }
}
