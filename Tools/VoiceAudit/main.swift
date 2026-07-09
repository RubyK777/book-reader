// Voice audit — PIVOT_PLAN.md Phase 0, task 0.3.
// Lists every installed French (fr-*) AVSpeechSynthesisVoice with identifier,
// name, quality tier, and traits, then prints a recommendation table sorted by
// quality — input for picking VoiceStore defaults for the fr-FR -> en pair (D9).
//
// Standalone macOS CLI beside Tools/OCRSpike — NOT part of any Xcode target.
//
// Usage:
//   swift Tools/VoiceAudit/main.swift
//
// NOTE: this audit is mechanical (what is installed, at which tier). The final
// listening judgment — how each voice actually sounds at 0.4-0.5x and 1.0x
// rates, and which one becomes the shadowing model — is Ruby's, by ear.

import Foundation
import AVFoundation

func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
    switch quality {
    case .default: return "default"
    case .enhanced: return "enhanced"
    case .premium: return "premium"
    @unknown default: return "unknown(\(quality.rawValue))"
    }
}

func qualityRank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
    switch quality {
    case .premium: return 0
    case .enhanced: return 1
    case .default: return 2
    @unknown default: return 3
    }
}

func traitsLabel(_ voice: AVSpeechSynthesisVoice) -> String {
    var traits: [String] = []
    if voice.voiceTraits.contains(.isNoveltyVoice) { traits.append("NOVELTY") }
    if voice.voiceTraits.contains(.isPersonalVoice) { traits.append("personal") }
    return traits.isEmpty ? "-" : traits.joined(separator: ",")
}

let allVoices = AVSpeechSynthesisVoice.speechVoices()
let frenchVoices = allVoices
    .filter { $0.language.lowercased().hasPrefix("fr") }
    .sorted {
        if $0.language != $1.language { return $0.language < $1.language }
        if qualityRank($0.quality) != qualityRank($1.quality) {
            return qualityRank($0.quality) < qualityRank($1.quality)
        }
        return $0.name < $1.name
    }

print("Voice audit (PIVOT_PLAN 0.3) — installed AVSpeechSynthesisVoice, fr-* locales")
print("Total installed voices (all languages): \(allVoices.count); French: \(frenchVoices.count)\n")

if frenchVoices.isEmpty {
    print("No French voices installed. Install via System Settings > Accessibility >")
    print("Spoken Content > System Voice > Manage Voices... (French).")
    exit(2)
}

// Full inventory.
let header = String(format: "%-8@ | %-22@ | %-9@ | %-10@ | %@",
                    "locale" as NSString, "name" as NSString, "quality" as NSString,
                    "traits" as NSString, "identifier" as NSString)
print(header)
print(String(repeating: "-", count: 110))
for voice in frenchVoices {
    let line = String(format: "%-8@ | %-22@ | %-9@ | %-10@ | %@",
                      voice.language as NSString,
                      voice.name as NSString,
                      qualityLabel(voice.quality) as NSString,
                      traitsLabel(voice) as NSString,
                      voice.identifier as NSString)
    print(line)
}

// Recommendation table: best candidate per quality tier, novelty voices excluded
// (they are jokes, not learning models), fr-FR preferred over fr-CA for the D9 pair.
print("\nRECOMMENDATION (mechanical ranking — novelty voices excluded, fr-FR preferred)")
print(String(repeating: "-", count: 110))

let candidates = frenchVoices.filter { !$0.voiceTraits.contains(.isNoveltyVoice) }
let tiers: [(AVSpeechSynthesisVoiceQuality, String)] = [
    (.premium, "premium"), (.enhanced, "enhanced"), (.default, "default")
]
for (tier, label) in tiers {
    let inTier = candidates.filter { $0.quality == tier }
    guard !inTier.isEmpty else {
        print("\(label): (none installed)")
        continue
    }
    // Prefer fr-FR; alphabetical within that.
    let best = inTier.sorted {
        let a = $0.language == "fr-FR" ? 0 : 1
        let b = $1.language == "fr-FR" ? 0 : 1
        if a != b { return a < b }
        return $0.name < $1.name
    }.first!
    print("\(label): \(best.name) (\(best.language)) — \(best.identifier)")
    if inTier.count > 1 {
        let rest = inTier.filter { $0.identifier != best.identifier }
            .map { "\($0.name) (\($0.language))" }
            .joined(separator: ", ")
        print("         alternatives: \(rest)")
    }
}

print("""

NOTE: quality tier and locale are the only things this tool can rank. The final
default-voice pick for VoiceStore, and the shadowing-model quality note, require
listening at 0.4-0.5x and 1.0x rates — that judgment is Ruby's.
""")
