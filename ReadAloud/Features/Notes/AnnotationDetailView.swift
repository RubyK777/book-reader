import SwiftUI
import SwiftData

/// One saved annotation: the notebook's editing surface (PIVOT_PLAN Phase 4).
/// Lifecycle rule: the annotation is the parent — edits update its review card
/// in place, delete cascades to the card (with confirmation), suspend keeps
/// history but leaves the due queue.
struct AnnotationDetailView: View {
    @Bindable var annotation: Annotation

    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nativeLanguage") private var nativeLanguage = LanguageCatalog.deviceDefaultNative

    @State private var player = SpeechPlayer()
    @State private var confirmDelete = false
    @State private var isDrafting = false
    @State private var isExplaining = false
    @State private var generationNote: String?

    private let provider = LearningAssetsProviderFactory.makeDefault()

    var body: some View {
        Form {
            headerSection
            noteSection
            confusionSection
            reviewSection
            dangerSection
        }
        .navigationTitle(annotation.type.rawValue.capitalized)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            player.stop()
            try? modelContext.save()
        }
        .confirmationDialog("Delete this saved item?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete item and its review card", role: .destructive) { deleteAnnotation() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its review history goes with it. To keep the history but stop reviews, suspend it instead.")
        }
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(annotation.text)
                        .font(.title3.weight(.semibold))
                        .fontDesign(Theme.sentenceDesign)
                    Spacer()
                    Button {
                        player.speakLine(annotation.text, languageCode: annotation.languageCode)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if annotation.contextSentence != annotation.text {
                    Text(annotation.contextSentence)
                        .font(.callout)
                        .fontDesign(Theme.sentenceDesign)
                        .foregroundStyle(.secondary)
                }

                Picker("Intent", selection: intentBinding) {
                    Text("None").tag(SaveIntent?.none)
                    ForEach(SaveIntent.allCases, id: \.self) { intent in
                        Text(intent.displayName).tag(SaveIntent?.some(intent))
                    }
                }
                .font(.callout)
            }
        }
    }

    private var noteSection: some View {
        Section("Note & example") {
            TextField("Your note", text: nonNilBinding(\.userNote), axis: .vertical)
                .lineLimit(1...4)

            TextField("Your example sentence", text: nonNilBinding(\.userExample), axis: .vertical)
                .lineLimit(1...4)
                .fontDesign(Theme.sentenceDesign)

            if provider?.isAvailable == true {
                Button {
                    Task { await draftExample() }
                } label: {
                    if isDrafting {
                        HStack { ProgressView().controlSize(.small); Text("Drafting…") }
                    } else {
                        Label(annotation.userExample?.isEmpty == false
                              ? "Draft a different example" : "Draft an example for me",
                              systemImage: "sparkles")
                    }
                }
                .disabled(isDrafting)
            }

            TextField("Tags (comma separated)", text: tagsBinding)
                .autocorrectionDisabled()

            if let generationNote {
                Text(generationNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var confusionSection: some View {
        Section("Confusion") {
            Toggle("I'm confused by this", isOn: confusedBinding)

            if annotation.isConfusing {
                if let explanation = annotation.aiExplanation, !explanation.isEmpty {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text(explanation)
                            .font(.callout)
                        Label("AI-generated — check anything that looks off", systemImage: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else if provider?.isAvailable == true {
                    Button {
                        Task { await explain() }
                    } label: {
                        if isExplaining {
                            HStack { ProgressView().controlSize(.small); Text("Thinking…") }
                        } else {
                            Label("Explain this to me", systemImage: "sparkles")
                        }
                    }
                    .disabled(isExplaining)
                }

                Toggle("Resolved — I get it now", isOn: $annotation.isResolved)
            }
        }
    }

    private var reviewSection: some View {
        Section("Review") {
            if let srs = annotation.srs {
                LabeledContent("Next review",
                               value: srs.dueDate.relativeNamed)
                LabeledContent("Interval", value: "\(srs.intervalDays) days")
                LabeledContent("Reviews", value: "\(srs.repetitions)")
            }
            Toggle("Suspended", isOn: suspendedBinding)
            if annotation.isSuspended {
                Text("Keeps its history but won't come up for review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dangerSection: some View {
        Section {
            Button("Delete Saved Item", role: .destructive) {
                confirmDelete = true
            }
        }
    }

    // MARK: Bindings

    private var intentBinding: Binding<SaveIntent?> {
        Binding(get: { annotation.intent }, set: { annotation.intent = $0 })
    }

    private var confusedBinding: Binding<Bool> {
        Binding(get: { annotation.isConfusing },
                set: { newValue in
                    annotation.isConfusing = newValue
                    if !newValue { annotation.isResolved = false }
                })
    }

    private var suspendedBinding: Binding<Bool> {
        Binding(get: { annotation.isSuspended },
                set: { newValue in
                    annotation.isSuspended = newValue
                    try? modelContext.save()
                    router.recomputeDueCount(in: modelContext)
                })
    }

    private func nonNilBinding(_ keyPath: ReferenceWritableKeyPath<Annotation, String?>) -> Binding<String> {
        Binding(get: { annotation[keyPath: keyPath] ?? "" },
                set: { annotation[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }

    private var tagsBinding: Binding<String> {
        Binding(get: { annotation.tags.joined(separator: ", ") },
                set: { newValue in
                    annotation.tags = newValue
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                })
    }

    // MARK: Actions

    private func draftExample() async {
        guard let provider else { return }
        isDrafting = true
        generationNote = nil
        do {
            let example = try await provider.draftExample(
                for: annotation.text,
                context: annotation.contextSentence,
                sourceLanguage: annotation.languageCode,
                explanationLanguage: nativeLanguage)
            annotation.userExample = example
            generationNote = "AI draft — edit it to make it yours."
            try? modelContext.save()
        } catch {
            generationNote = "Couldn't draft an example — try again."
        }
        isDrafting = false
    }

    private func explain() async {
        guard let provider else { return }
        isExplaining = true
        do {
            annotation.aiExplanation = try await provider.explainConfusion(
                about: annotation.text,
                context: annotation.contextSentence,
                sourceLanguage: annotation.languageCode,
                explanationLanguage: nativeLanguage)
            try? modelContext.save()
        } catch {
            generationNote = "Couldn't generate an explanation — try again."
        }
        isExplaining = false
    }

    private func deleteAnnotation() {
        player.stop()
        modelContext.delete(annotation)
        try? modelContext.save()
        router.recomputeDueCount(in: modelContext)
        Haptics.select()
        dismiss()
    }
}
