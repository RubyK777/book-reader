import SwiftUI

/// Four-tab shell. Library owns the primary navigation stack
/// (Book → BookDetail → Reader); other tabs are placeholders this milestone.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("reviewRemindersEnabled") private var remindersEnabled = false

    /// Shared between a Library cover and its `BookDetailView` so tapping a book
    /// zooms it *open* into its pages (iOS 18 zoom navigation transition).
    @Namespace private var bookOpen

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            NavigationStack(path: $router.libraryPath) {
                LibraryView(bookNamespace: bookOpen)
                    .navigationDestination(for: Book.self) { book in
                        BookDetailView(book: book)
                            .navigationTransition(.zoom(sourceID: book.persistentModelID, in: bookOpen))
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
                .badge(router.dueCount)
                .tag(AppTab.review)

            NotesView()
                .tabItem { Label("Notebook", systemImage: "note.text") }
                .tag(AppTab.notes)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .task {
            router.recomputeDueCount(in: modelContext)
            rescheduleReminder()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                router.recomputeDueCount(in: modelContext)
                rescheduleReminder()
            }
        }
    }

    /// Keep the single review nudge in sync with the deck's soonest future due
    /// date (or clear it when reminders are off). Cheap; runs on every activate.
    private func rescheduleReminder() {
        guard remindersEnabled else {
            ReviewReminderService.cancel()
            return
        }
        let next = SRSEngine.nextDue(in: modelContext)
        ReviewReminderService.reschedule(at: next?.date, sourceTitle: next?.sourceTitle)
    }
}
