import SwiftUI

/// Presentation-only color mappings: each source kind, annotation type, and
/// review grade owns a palette hue so the content tabs read as color-coded at a
/// glance. These are computed `tint` vars on model enums — they add no stored
/// properties and never touch the SwiftData schema fingerprint (DECISIONS #35).
/// Ink blue (`Theme.accent`) stays primary; the confused state is marigold
/// everywhere.

extension SourceKind {
    /// Shelf tint — thumbnail wash + kind chip on the Library row.
    var tint: Color {
        switch self {
        case .book: Theme.accent
        case .quickScan: Palette.verdigris
        case .conversation: Palette.violet
        }
    }
}

extension AnnotationType {
    /// Notebook row spine + filter-chip tint.
    var tint: Color {
        switch self {
        case .word: Theme.accent
        case .phrase: Palette.verdigris
        case .sentence: Palette.violet
        case .grammar: Palette.coral
        }
    }
}

extension ReviewGrade {
    /// Grade button + summary tally tint (replaces the old red/orange/green/blue).
    var tint: Color {
        switch self {
        case .again: Palette.coral
        case .hard: Palette.marigold
        case .good: Palette.verdigris
        case .easy: Theme.accent
        }
    }
}
