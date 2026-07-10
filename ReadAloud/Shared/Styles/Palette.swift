import SwiftUI
import UIKit

/// The semantic accent palette layered on top of the "paper & ink" identity
/// (DECISIONS #36). Ink blue (`Theme.accent`) stays the primary voice; these
/// five muted "gouache" hues give source kinds and annotation types each their
/// own color without turning the app neon. Every hue ships an explicit dark
/// variant (lifted for legibility on the elevated grey surface) — never reuse a
/// light hex in dark mode. Presentation-only: no model or schema impact.
enum Palette {

    /// Warm terracotta — menus, "Again", the Library empty state.
    static let coral = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.910, green: 0.573, blue: 0.478, alpha: 1)   // #E8927A
            : UIColor(red: 0.753, green: 0.325, blue: 0.227, alpha: 1)   // #C0533A
    })

    /// Amber — "Hard" and the confused/marigold state everywhere. The light
    /// variant is deliberately dark (#A9740E) for 4.5:1 caption contrast on
    /// paper; the bright yellow lives only in dark mode + confetti.
    static let marigold = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.898, green: 0.722, blue: 0.361, alpha: 1)   // #E5B85C
            : UIColor(red: 0.663, green: 0.455, blue: 0.055, alpha: 1)   // #A9740E
    })

    /// Teal-green — signs, phrases, "Good".
    static let verdigris = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.486, green: 0.769, blue: 0.686, alpha: 1)   // #7CC4AF
            : UIColor(red: 0.184, green: 0.478, blue: 0.408, alpha: 1)   // #2F7A68
    })

    /// Muted violet — screenshots, sentences, the Review empty state.
    static let violet = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.675, green: 0.608, blue: 0.875, alpha: 1)   // #AC9BDF
            : UIColor(red: 0.420, green: 0.337, blue: 0.624, alpha: 1)   // #6B569F
    })

    /// Neutral slate — the "other" source kind, quiet chrome.
    static let slate = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.576, green: 0.639, blue: 0.690, alpha: 1)   // #93A3B0
            : UIColor(red: 0.361, green: 0.420, blue: 0.471, alpha: 1)   // #5C6B78
    })

    /// Soft tinted fill for active/selected surfaces — generalizes
    /// `Theme.accentSoft` to any palette color.
    static func soft(_ color: Color) -> Color { color.opacity(0.13) }

    /// Confetti burst palette (bright variants — celebration, not chrome).
    static let celebration: [Color] = [coral, marigold, verdigris, violet, Theme.accent]

    /// Nine colors for a 3×3 `MeshGradient` — a watercolor wash: paper at the
    /// edges, soft accent/verdigris/violet drifting through the interior.
    static let meshWash: [Color] = [
        Theme.card,          soft(Theme.accent), Theme.card,
        soft(verdigris),     soft(Theme.accent), soft(violet),
        Theme.card,          soft(violet),       Theme.card,
    ]
}

/// Forwarders so call sites can reach the palette through `Theme` alongside the
/// base identity tokens (`Theme.accent`), matching how the rest of the app
/// already namespaces color.
extension Theme {
    static let coral = Palette.coral
    static let marigold = Palette.marigold
    static let verdigris = Palette.verdigris
    static let violet = Palette.violet
    static let slate = Palette.slate
}
