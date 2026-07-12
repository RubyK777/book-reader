import SwiftUI
import UIKit

/// The system dictionary panel for a term (PHASE3_DESIGN §5). Presented as a
/// sheet; when no definition exists it shows a Manage Dictionaries download flow.
struct DictionaryView: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}

/// Identifiable term wrapper so a `String` can drive `.sheet(item:)`.
struct DictionaryTerm: Identifiable { let term: String; var id: String { term } }

extension View {
    /// Present the system dictionary panel for the bound term. Set the binding
    /// to a `DictionaryTerm` to look a word up; it clears on dismiss. Replaces
    /// the copy-pasted `.sheet(item:) { DictionaryView(term:) }` trio.
    func dictionaryLookup(term: Binding<DictionaryTerm?>) -> some View {
        sheet(item: term) { lookup in
            DictionaryView(term: lookup.term).ignoresSafeArea()
        }
    }
}
