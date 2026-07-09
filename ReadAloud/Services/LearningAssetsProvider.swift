import Foundation

/// Provider seam for the Understand section (PIVOT_PLAN D10). v1 ships exactly
/// one implementation — on-device Foundation Models. A cloud provider may plug
/// in later as an explicit user opt-in; callers depend only on this protocol.
/// Library rules apply: no SwiftUI, no singletons, dependencies passed in.
protocol LearningAssetsProviding {
    /// Whether the provider can generate right now (device tier, model state,
    /// language support). Views fall back to user-authored fields when false.
    var isAvailable: Bool { get }

    /// Human-readable reason when `isAvailable` is false (shown in the
    /// fallback view), nil when available.
    var unavailabilityReason: String? { get }

    /// Generate breakdown/vocab/grammar for one sentence. `sourceLanguage` is
    /// the sentence's BCP-47 code; `explanationLanguage` is the user's native
    /// language (glosses and the grammar point are written in it).
    func generateAssets(for sentenceText: String,
                        sourceLanguage: String,
                        explanationLanguage: String) async throws -> LearningAssets
}

enum LearningAssetsProviderFactory {
    /// The default provider for this device, or nil when no tier is available
    /// (pre-iOS 26 / non-Apple Intelligence hardware) — the caller shows the
    /// fallback learn view (D2).
    static func makeDefault() -> (any LearningAssetsProviding)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return FoundationModelsAssetsProvider()
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// On-device generation via Apple's Foundation Models framework (D1).
/// Structured output through guided generation — the model fills
/// `LearningAssetsDraft`, so there is no free-text parsing.
@available(iOS 26.0, macOS 26.0, *)
struct FoundationModelsAssetsProvider: LearningAssetsProviding {
    /// Marks generated content for provenance (D7).
    static let modelVersion = "apple-foundation-models-26"

    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    var unavailabilityReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to generate breakdowns."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading — try again soon."
        case .unavailable:
            return "On-device intelligence isn't available right now."
        }
    }

    func generateAssets(for sentenceText: String,
                        sourceLanguage: String,
                        explanationLanguage: String) async throws -> LearningAssets {
        let source = Self.languageName(for: sourceLanguage)
        let native = Self.languageName(for: explanationLanguage)

        let session = LanguageModelSession(instructions: """
            You help a \(native)-speaking learner understand \(source) they \
            photographed in real life. Split the given \(source) text into its \
            meaningful chunks in order, gloss each chunk in \(native), pick the \
            2-4 vocabulary items most worth learning, and state the single most \
            useful grammar or usage point in one or two short \(native) \
            sentences. Chunks must reproduce the original text exactly. If the \
            text is a fragment (a sign or menu line, not a full sentence), \
            treat it as a phrase and leave the grammar point empty.
            """)

        let response = try await session.respond(
            to: "Text: \(sentenceText)",
            generating: LearningAssetsDraft.self)
        let draft = response.content

        let grammar = draft.grammarPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return LearningAssets(
            chunks: draft.chunks.map { .init(text: $0.text, gloss: $0.gloss) },
            keyVocab: draft.keyVocab.map { .init(term: $0.term, meaning: $0.meaning) },
            grammarPoint: grammar.isEmpty ? nil : grammar,
            isGenerated: true,
            modelVersion: Self.modelVersion,
            generatedAt: .now)
    }

    /// English display name for a BCP-47 code ("fr-FR" → "French") for prompts.
    private static func languageName(for code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: String(code.prefix(2)))
            ?? code
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct LearningAssetsDraft {
    @Guide(description: "The text split into meaningful chunks/phrases, in original order, reproducing the original text exactly")
    var chunks: [ChunkDraft]

    @Guide(description: "The 2-4 vocabulary items most worth learning from this text")
    var keyVocab: [VocabDraft]

    @Guide(description: "The single most useful grammar or usage point, one or two short sentences in the learner's language; empty string if the text is a fragment with no grammar to explain")
    var grammarPoint: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct ChunkDraft {
    @Guide(description: "A chunk of the original text, copied exactly")
    var text: String
    @Guide(description: "What this chunk means, in the learner's native language")
    var gloss: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct VocabDraft {
    @Guide(description: "The vocabulary term as it appears in the text (dictionary form is fine)")
    var term: String
    @Guide(description: "Its meaning in the learner's native language, brief")
    var meaning: String
}
#endif
