import SwiftUI
import UIKit

/// The app's visual identity — "paper & ink" (CLAUDE.md Shared/Styles layer).
/// Learning content (sentences, words, chunks) is set in serif like a book
/// page; UI chrome stays in the system sans. One ink-blue accent everywhere.
/// Screens compose these tokens/styles; they never hardcode fonts or colors.
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

// MARK: - Card chrome

/// Standard content card: warm paper, hairline stroke, soft radius.
/// `active` tints it with the accent (playing sentence, selected state).
struct LearningCard: ViewModifier {
    var active = false

    func body(content: Content) -> some View {
        content
            .padding(DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(active ? Theme.accentSoft : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .strokeBorder(active ? Theme.accent : Theme.cardStroke,
                                  lineWidth: active ? 1.5 : 1)
            )
    }
}

extension View {
    func learningCard(active: Bool = false) -> some View {
        modifier(LearningCard(active: active))
    }
}

// MARK: - Chip

/// Selectable word/phrase chip (Save sheets, Learn view). Serif term text,
/// accent fill when selected.
struct ChipButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.termFont)
            .fontDesign(Theme.sentenceDesign)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(
                Capsule().fill(isSelected ? Theme.accent : Theme.card)
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.clear : Theme.cardStroke)
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Section header (Learn view, detail screens)

/// Uppercase micro-label with the accent icon — one consistent section voice.
struct SectionHeaderLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(0.8)
                .foregroundStyle(.secondary)
        }
    }
}
