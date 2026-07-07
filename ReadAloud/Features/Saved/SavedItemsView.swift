import SwiftUI

/// Placeholder — real saved-items browser lands in a later wave.
struct SavedItemsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Saved Words",
                systemImage: "bookmark",
                description: Text("Words you save while reading will appear here."))
                .navigationTitle("Saved")
        }
    }
}
