import SwiftUI
import SwiftData
import Translation

/// Detail for one bookmarked sentence: the full text, its meaning (translated
/// into the native language), a replay button, an editable note (autosaved),
/// the SRS schedule, and a "Remove from Saved" action that only clears the
/// bookmark — the sentence and its SRS state are kept. Saved words & phrases
/// are `Annotation`s and use `AnnotationDetailView` instead (V5, DECISIONS #63).
struct SavedItemDetailView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(AppRouter.self) private var router
  @Environment(\.dismiss) private var dismiss
  @AppStorage("nativeLanguage") private var nativeLanguage = LanguageCatalog.deviceDefaultNative

  private let sentence: Sentence
  @State private var player = SpeechPlayer()
  @State private var isConfirmingRemoval = false
  @State private var meaning: TranslationMeaning = .none
  @State private var translateConfig: TranslationSession.Configuration?

  init(sentence: Sentence) { self.sentence = sentence }

  var body: some View {
    Form {
      Section {
        Text(text)
          .font(.title3.weight(.semibold))
        if let dateText {
          Text("\(sourceLabel) · \(dateText)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Button {
          player.speakLine(text, languageCode: languageCode)
          Haptics.select()
        } label: {
          Label("Play", systemImage: "speaker.wave.2.fill")
        }
      }

      meaningSection

      Section("Note") {
        TextField("Add a note", text: noteBinding, axis: .vertical)
          .lineLimit(1...4)
      }

      Section("Review") {
        LabeledContent("Repetitions", value: "\(srs.repetitions)")
        LabeledContent("Ease", value: srs.easeFactor.formatted(.number.precision(.fractionLength(1))))
        LabeledContent("Interval", value: "\(srs.intervalDays) day\(srs.intervalDays == 1 ? "" : "s")")
        LabeledContent("Due", value: srs.dueDate.relativeNamed)
      }

      Section {
        Button(role: .destructive) { isConfirmingRemoval = true } label: {
          Label("Remove from Saved", systemImage: "bookmark.slash")
        }
      }
    }
    .navigationTitle("Sentence")
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog(
      "Remove this sentence from Saved?",
      isPresented: $isConfirmingRemoval,
      titleVisibility: .visible
    ) {
      Button("Remove from Saved", role: .destructive) { performRemoval() }
      Button("Cancel", role: .cancel) {}
    }
    .task { resolveMeaning() }
    .translationTask(translateConfig) { session in
      await translate(using: session)
    }
  }

  /// The translated meaning, once resolved. Hidden when the sentence is already
  /// in the native language or no translation is available.
  @ViewBuilder
  private var meaningSection: some View {
    switch meaning {
    case .translating:
      Section("Meaning") {
        HStack(spacing: DesignSystem.Spacing.sm) {
          ProgressView().controlSize(.small)
          Text("Translating…").foregroundStyle(.secondary)
        }
      }
    case let .ready(translated):
      Section("Meaning") {
        Text(translated).font(.body)
      }
    case .none, .unavailable:
      EmptyView()
    }
  }

  /// Reuse the stored sentence translation, skip when already the native
  /// language, else translate live into it.
  private func resolveMeaning() {
    guard meaning == .none else { return }
    (meaning, translateConfig) = TranslationResolver.begin(
      existing: sentence.translatedText, source: languageCode, native: nativeLanguage)
  }

  @MainActor
  private func translate(using session: TranslationSession) async {
    meaning = await TranslationResolver.resolve(session, text: text)
    if case let .ready(translated) = meaning, sentence.translatedText == nil {
      sentence.translatedText = translated
      try? modelContext.save()
    }
  }

  // MARK: - Accessors

  private var text: String { sentence.text }
  private var languageCode: String { sentence.page?.book?.languageCode ?? "en-US" }
  private var srs: SRSState { sentence.srs ?? SRSState() }
  private var sourceLabel: String { LanguageCatalog.name(for: languageCode) }
  private var dateText: String? { sentence.page?.scannedAt.shortDate }

  private var noteBinding: Binding<String> {
    Binding(
      get: { sentence.userNote ?? "" },
      set: { newValue in
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        sentence.userNote = trimmed.isEmpty ? nil : newValue
      }
    )
  }

  // MARK: - Mutations

  private func performRemoval() {
    sentence.isBookmarked = false   // keep SRS state; never delete the sentence here
    try? modelContext.save()
    router.recomputeDueCount(in: modelContext)
    dismiss()
  }
}
