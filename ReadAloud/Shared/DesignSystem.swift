import SwiftUI
import UIKit

/// Design tokens — spacing, corner radii, icon sizes, accent (design system).
/// Screens compose these instead of hardcoding paddings/radii/sizes. Every value
/// is a multiple of 8 (4 is the only half-step).
enum DesignSystem {
    /// 8-pt spacing scale. `screenMargin` is the unified left/right screen inset.
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32

        /// Unified screen side margin (guideline §2).
        static let screenMargin: CGFloat = 16
    }

    /// One global radius ladder (guideline §3): icon/small 8 · button 10 ·
    /// card 12 · hero container 20. Don't invent per-view radii.
    enum CornerRadius {
        static let small: CGFloat = 8
        static let button: CGFloat = 10
        static let medium: CGFloat = 12
        static let large: CGFloat = 20
    }

    /// Uniform SF Symbol sizes (guideline §6). Body-adjacent symbols should
    /// prefer semantic `Font` styles; these are for deliberate fixed sizing.
    enum IconSize {
        static let sm: CGFloat = 16
        static let md: CGFloat = 24
        static let lg: CGFloat = 28
        /// Large decorative/empty-state symbol.
        static let hero: CGFloat = 48
        /// Extra-large hero glyph (summary seal, viewfinder).
        static let xl: CGFloat = 56
    }

    /// The app accent — use for primary actions and highlights (Theme.accent).
    static let accent = Theme.accent

    /// Minimum tappable size per Apple HIG.
    static let minTapTarget: CGFloat = 44
}

/// Thin wrapper over UIKit feedback generators so feature views
/// don't reach into UIKit directly.
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func bookmark() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Session-complete celebration — a heavy thump followed by the success
    /// chime, paired with the confetti burst on the Review summary.
    static func celebrate() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
