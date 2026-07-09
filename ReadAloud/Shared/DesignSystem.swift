import SwiftUI
import UIKit

/// Design tokens — spacing, corner radii, and accent usage.
/// Screens compose these instead of hardcoding paddings/radii.
enum DesignSystem {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 20
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
}
