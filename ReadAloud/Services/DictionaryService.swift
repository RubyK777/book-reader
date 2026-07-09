import UIKit

/// Thin wrapper over the system dictionary (PHASE3_DESIGN §5).
enum DictionaryService {
    /// Whether an installed dictionary has an entry for `term`. Used to decorate
    /// the Look Up affordance; we still present the reference view either way,
    /// since it offers a Manage Dictionaries flow when nothing is found.
    static func hasDefinition(for term: String) -> Bool {
        UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term)
    }
}
