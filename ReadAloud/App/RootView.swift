import SwiftUI

/// Four-tab shell. Library owns the primary navigation stack
/// (Book → BookDetail → Reader); other tabs are placeholders this milestone.
struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            NavigationStack(path: $router.libraryPath) {
                LibraryView()
                    .navigationDestination(for: Book.self) { book in
                        BookDetailView(book: book)
                    }
                    .navigationDestination(for: ScanPage.self) { page in
                        ReaderView(page: page)
                    }
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
            .tag(AppTab.library)

            SavedItemsView()
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .tag(AppTab.saved)

            ReviewView()
                .tabItem { Label("Review", systemImage: "brain.head.profile") }
                .tag(AppTab.review)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}
