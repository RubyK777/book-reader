import SwiftUI

/// D7: generated content is editable and deletable. Edits mark the assets
/// `userEditedAt` (done by the caller) while keeping `isGenerated` provenance.
struct EditAssetsSheet: View {
    @State private var working: LearningAssets
    private let onSave: (LearningAssets) -> Void
    @Environment(\.dismiss) private var dismiss

    init(assets: LearningAssets, onSave: @escaping (LearningAssets) -> Void) {
        _working = State(initialValue: assets)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chunks") {
                    ForEach(working.chunks.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                            TextField("Chunk", text: $working.chunks[i].text)
                                .fontWeight(.medium)
                            TextField("Meaning", text: $working.chunks[i].gloss)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { working.chunks.remove(atOffsets: $0) }
                }

                Section("Key vocabulary") {
                    ForEach(working.keyVocab.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                            TextField("Term", text: $working.keyVocab[i].term)
                                .fontWeight(.medium)
                            TextField("Meaning", text: $working.keyVocab[i].meaning)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { working.keyVocab.remove(atOffsets: $0) }
                }

                Section("Grammar point") {
                    TextField("Grammar point (leave empty to remove)",
                              text: Binding(
                                get: { working.grammarPoint ?? "" },
                                set: { working.grammarPoint = $0.isEmpty ? nil : $0 }),
                              axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Edit Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(working)
                        dismiss()
                    }
                }
            }
        }
    }
}
