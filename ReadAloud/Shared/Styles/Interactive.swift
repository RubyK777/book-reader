import SwiftUI

/// Interactive button styles. Presses get a springy scale that livens taps
/// without changing behavior; every animation is gated on Reduce Motion inside
/// the style so feature views stay clean (they just apply the style).

// MARK: - Chip

/// Selectable word/phrase/filter chip (Save sheets, Learn view, Notebook
/// filters). Serif term text; `tint` fills when selected (defaults to the ink
/// accent so existing call sites are unchanged). Moved here from `Theme.swift`;
/// `isSelected` stays the first parameter for source compatibility.
struct ChipButtonStyle: ButtonStyle {
    var isSelected = false
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration, isSelected: isSelected, tint: tint)
    }

    private struct Chip: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        let tint: Color
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(Theme.termFont)
                .fontDesign(Theme.sentenceDesign)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(Capsule().fill(isSelected ? tint : Theme.card))
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Theme.cardStroke))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.92 : 1))
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.55),
                           value: configuration.isPressed)
        }
    }
}

// MARK: - Pressable tile

/// A press style for tappable cards/tiles (e.g. bookshelf covers): a gentle
/// scale-down on press with a spring back, so the tile feels physical before it
/// navigates. Reduce Motion → no scaling. Composes with `NavigationLink`.
struct PressableScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        Pressable(configuration: configuration, scale: scale)
    }

    private struct Pressable: View {
        let configuration: ButtonStyleConfiguration
        let scale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? scale : 1))
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6),
                           value: configuration.isPressed)
        }
    }
}

// MARK: - Prominent action

/// Full-width primary/secondary action button. `prominent` fills with `tint`
/// and white text; `prominent: false` is the soft-tinted secondary variant.
/// Press scales down with an overshoot spring; Reduce Motion → opacity dim only.
struct SpringyProminentButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    var prominent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        Springy(configuration: configuration, tint: tint, prominent: prominent)
    }

    private struct Springy: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        let prominent: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .fill(prominent ? tint : Palette.soft(tint))
                )
                .foregroundStyle(prominent ? Color.white : tint)
                .opacity(!isEnabled ? 0.5 : (configuration.isPressed && reduceMotion ? 0.85 : 1))
                .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.5),
                           value: configuration.isPressed)
        }
    }
}
