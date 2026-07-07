import SwiftUI

/// Placeholder — the spaced-repetition review engine lands in a later wave.
struct ReviewView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Nothing to review yet",
                systemImage: "brain.head.profile",
                description: Text("Bookmark sentences and save words to build your review deck."))
                .navigationTitle("Review")
        }
    }
}
