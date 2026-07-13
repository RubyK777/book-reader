import SwiftUI
import UIKit

/// The app's visual identity — "paper & ink" (development conventions Shared/Styles layer).
/// Learning content (sentences, words, chunks) is set in serif like a book
/// page; UI chrome stays in the system sans. One ink-blue accent everywhere.
/// Screens compose these tokens; they never hardcode fonts or colors.
///
/// Base identity tokens only. Related style files:
/// - `Palette.swift` — the five semantic accent hues + wash/confetti palettes
/// - `SemanticColors.swift` — per-enum `tint` mappings
/// - `Interactive.swift` — `ChipButtonStyle`, `SpringyProminentButtonStyle`
/// - `Cards.swift` — `LearningCard`/`.learningCard(active:)`, `SectionHeaderLabel`
enum Theme {

    // MARK: Color

    /// French ink blue — the app accent (buttons, active states, links).
    static let accent = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.50, green: 0.68, blue: 0.83, alpha: 1)   // lifted for dark
            : UIColor(red: 0.17, green: 0.36, blue: 0.52, alpha: 1)   // #2B5B84
    })

    /// Soft accent fill for active/selected surfaces.
    static let accentSoft = accent.opacity(0.13)

    /// Card surface: warm paper in light mode, elevated grey in dark.
    static let card = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.secondarySystemBackground
            : UIColor(red: 0.972, green: 0.965, blue: 0.945, alpha: 1)
    })

    /// Hairline stroke that keeps cards crisp on the plain background.
    static let cardStroke = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor(red: 0.85, green: 0.83, blue: 0.78, alpha: 1)
    })

    /// The karaoke word highlight (shared by Reader and Learn).
    static let karaoke = Color.yellow.opacity(0.55)

    // MARK: Type — learning content is serif ("the book voice")

    /// A full sentence being studied or read.
    static let sentenceFont = Font.title3.weight(.regular)
    static let sentenceDesign = Font.Design.serif

    /// The hero sentence on the Learn screen.
    static let heroFont = Font.title2.weight(.medium)

    /// Source-language words/chunks inside chips and rows.
    static let termFont = Font.callout.weight(.medium)

    /// Serif helper so call sites stay declarative.
    static func serif(_ font: Font) -> Font { font }
}
