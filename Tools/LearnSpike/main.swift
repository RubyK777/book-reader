// Foundation Models quality spike — PIVOT_PLAN.md Phase 0, task 0.1.
// Validates the pivot's biggest technical bet (risk register #1): can the
// on-device ~3B Apple Intelligence model produce usable phrase breakdowns,
// key vocab, and grammar points for French sentences, explained in English (D9)?
//
// Standalone macOS 26 CLI beside Tools/OCRSpike — NOT part of any Xcode target.
//
// Usage:
//   swift Tools/LearnSpike/main.swift [fixtures-path]
//   swift Tools/LearnSpike/main.swift Fixtures/french_sentences.txt
//
// If the `swift` interpreter fails with "JIT session error: Symbols not found",
// the installed OS's FoundationModels ABI does not match the SDK (seen on
// macOS 26.0 beta builds vs the release SDK). Compile ahead-of-time instead —
// the binary weak-links the framework and self-diagnoses at runtime:
//   swiftc -O -Xlinker -weak_framework -Xlinker FoundationModels \
//          -o /tmp/learnspike Tools/LearnSpike/main.swift
//   /tmp/learnspike Fixtures/french_sentences.txt
//
// Output is hand-gradeable per sentence (PIVOT_PLAN 0.1 acceptance:
// >=80% of breakdowns rated usable; wrong-grammar-note rate recorded).

import Foundation
import FoundationModels

// MARK: - @Generable draft matching PIVOT_PLAN §6 LearningAssets
// (chunks / key vocab / one grammar point — short fields, English explanations)

@available(macOS 26.0, *)
@Generable
struct LearningAssetsDraft {
    @Generable
    struct Chunk {
        @Guide(description: "A short meaningful chunk of the French sentence, copied verbatim, in order. Together the chunks should cover the whole sentence.")
        var text: String
        @Guide(description: "A concise English gloss of this chunk (a few words).")
        var gloss: String
    }

    @Generable
    struct VocabItem {
        @Guide(description: "A key French word or fixed expression from the sentence, in dictionary form where sensible.")
        var term: String
        @Guide(description: "Its English meaning, brief (a few words).")
        var meaning: String
    }

    @Guide(description: "The sentence split into 2-6 meaningful phrase chunks, in original order, each with an English gloss.")
    var chunks: [Chunk]

    @Guide(description: "1-4 key vocabulary items an adult English-speaking learner of French should retain from this sentence.")
    var keyVocab: [VocabItem]

    @Guide(description: "One short English note (1-2 sentences) about the single most useful grammar or usage point in this sentence. Must be true and specific to this sentence.")
    var grammarPoint: String
}

// MARK: - Runtime ABI probe
//
// The FoundationModels ABI changed between macOS 26.0 betas and the release
// (e.g. respond(...) gained/lost an `isolation:` parameter; the session init
// dropped `guardrails:`). A binary built with a release SDK aborts at dyld
// launch on a beta OS unless the framework is weak-linked. With weak linking,
// missing symbols resolve to NULL — so before calling into the generation
// path, verify the exact symbols this binary was compiled against actually
// exist in the loaded framework. If not, report precisely why and stop.

let requiredReleaseABISymbols: [(name: String, mangled: String)] = [
    ("LanguageModelSession.init(model:tools:instructions:)",
     "$s16FoundationModels20LanguageModelSessionC5model5tools12instructionsAcA06SystemcD0C_SayAA4Tool_pGSSSgtcfC"),
    ("LanguageModelSession.respond(to:generating:includeSchemaInPrompt:options:)",
     "$s16FoundationModels20LanguageModelSessionC7respond2to10generating21includeSchemaInPrompt7optionsAC8ResponseVy_xGSS_xmSbAA17GenerationOptionsVtYaKAA9GenerableRzlF"),
]

func missingReleaseABISymbols() -> [String] {
    requiredReleaseABISymbols
        .filter { dlsym(dlopen(nil, RTLD_NOW), $0.mangled) == nil }
        .map(\.name)
}

// MARK: - Spike runner

@available(macOS 26.0, *)
func describeAvailability(_ availability: SystemLanguageModel.Availability) -> String {
    switch availability {
    case .available:
        return "available"
    case .unavailable(let reason):
        switch reason {
        case .deviceNotEligible:
            return "unavailable(.deviceNotEligible) — this Mac's hardware does not support Apple Intelligence"
        case .appleIntelligenceNotEnabled:
            return "unavailable(.appleIntelligenceNotEnabled) — Apple Intelligence is not turned on in System Settings"
        case .modelNotReady:
            return "unavailable(.modelNotReady) — model assets are still downloading / not ready yet; retry later"
        @unknown default:
            return "unavailable(unknown reason: \(reason))"
        }
    }
}

@available(macOS 26.0, *)
func runSpike(fixturesPath: String) async {
    print("Foundation Models learning-assets spike (PIVOT_PLAN 0.1)")
    print("Fixtures: \(fixturesPath)\n")

    let model = SystemLanguageModel.default
    let availabilityDescription = describeAvailability(model.availability)
    print("SystemLanguageModel.default.availability: \(availabilityDescription)")

    let missing = missingReleaseABISymbols()
    if missing.isEmpty {
        print("ABI probe: OK — installed framework exports the release-SDK generation symbols.")
    } else {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        print("ABI probe: MISMATCH — the installed FoundationModels framework (\(osVersion))")
        print("does not export the release-SDK symbols this binary was compiled against:")
        for name in missing { print("   • \(name)") }
        print("This happens on macOS 26.0 BETA builds with a release SDK (Xcode 26.x).")
    }

    guard case .available = model.availability else {
        print("\nRESULT: model unavailable on this machine — spike cannot grade output quality here.")
        print("Record the reason above in docs/SPIKE_RESULTS.md; rerun on Apple Intelligence hardware.")
        exit(2)
    }

    guard missing.isEmpty else {
        print("\nRESULT: BLOCKED — OS/SDK ABI mismatch, generation cannot run on this machine.")
        print("Rerun on release macOS 26.0+ (or with a matching beta SDK). Availability status above is still valid.")
        exit(3)
    }

    // Load fixture sentences (one per line).
    guard let raw = try? String(contentsOfFile: fixturesPath, encoding: .utf8) else {
        print("error: cannot read fixtures file at \(fixturesPath)")
        exit(1)
    }
    let sentences = raw
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    print("Loaded \(sentences.count) French sentence(s).\n")

    let instructions = """
        You are a French-to-English language learning assistant inside a reading app. \
        The user is an adult English speaker learning French. \
        For each French sentence you receive, produce learning assets: \
        the sentence broken into meaningful phrase chunks with English glosses, \
        a few key vocabulary items with English meanings, \
        and one short, accurate grammar or usage note in English specific to that sentence. \
        All explanations must be in English. Keep every field short. \
        Never invent words that are not in the sentence.
        """

    var timings: [Double] = []
    var failures = 0

    for (index, sentence) in sentences.enumerated() {
        print(String(repeating: "=", count: 70))
        print("[\(index + 1)/\(sentences.count)] \(sentence)")

        // Fresh session per sentence: no cross-sentence context accumulation,
        // and one bad sentence can't poison or overflow the next.
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "French sentence: \(sentence)"

        let start = Date()
        do {
            let response = try await session.respond(to: prompt, generating: LearningAssetsDraft.self)
            let elapsed = Date().timeIntervalSince(start)
            timings.append(elapsed)
            let assets = response.content

            print(String(format: "   time: %.2fs", elapsed))
            print("   chunks:")
            for chunk in assets.chunks {
                print("      • \(chunk.text)  →  \(chunk.gloss)")
            }
            print("   keyVocab:")
            for item in assets.keyVocab {
                print("      • \(item.term) = \(item.meaning)")
            }
            print("   grammarPoint: \(assets.grammarPoint)")
        } catch let error as LanguageModelSession.GenerationError {
            let elapsed = Date().timeIntervalSince(start)
            failures += 1
            print(String(format: "   FAILED after %.2fs — GenerationError: %@", elapsed, describeGenerationError(error)))
        } catch {
            let elapsed = Date().timeIntervalSince(start)
            failures += 1
            print(String(format: "   FAILED after %.2fs — %@", elapsed, String(describing: error)))
        }
        print()
    }

    // Summary stats for SPIKE_RESULTS.md.
    print(String(repeating: "=", count: 70))
    print("SUMMARY")
    print("   sentences: \(sentences.count), succeeded: \(sentences.count - failures), failed: \(failures)")
    if !timings.isEmpty {
        let sorted = timings.sorted()
        let mean = timings.reduce(0, +) / Double(timings.count)
        let median = sorted[sorted.count / 2]
        print(String(format: "   timing: min %.2fs · median %.2fs · mean %.2fs · max %.2fs",
                     sorted.first!, median, mean, sorted.last!))
    }
    print("   Hand-grade each output above against the >=80%-usable bar (PIVOT_PLAN 0.1):")
    print("   usable = chunks correct, glosses accurate, grammar point true and relevant.")
}

@available(macOS 26.0, *)
func describeGenerationError(_ error: LanguageModelSession.GenerationError) -> String {
    switch error {
    case .guardrailViolation:
        return "guardrailViolation (safety guardrail rejected prompt or output)"
    case .exceededContextWindowSize:
        return "exceededContextWindowSize"
    case .unsupportedLanguageOrLocale:
        return "unsupportedLanguageOrLocale"
    case .assetsUnavailable:
        return "assetsUnavailable (model assets missing)"
    case .decodingFailure:
        return "decodingFailure (structured output did not match schema)"
    case .unsupportedGuide:
        return "unsupportedGuide"
    case .rateLimited:
        return "rateLimited"
    default:
        return String(describing: error)
    }
}

// MARK: - Entry point (availability-gated per D2)

let fixturesPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Fixtures/french_sentences.txt"

if #available(macOS 26.0, *) {
    await runSpike(fixturesPath: fixturesPath)
} else {
    print("FoundationModels requires macOS 26.0+ — this machine cannot run spike 0.1.")
    exit(2)
}
