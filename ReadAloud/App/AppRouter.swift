import SwiftUI
import SwiftData

/// Root tabs.
enum AppTab: Hashable {
    case library, saved, review, notes, settings
}

/// App-wide navigation state, injected via `.environment`.
@Observable
final class AppRouter {
    var tab: AppTab = .library
    var libraryPath = NavigationPath()
    var isScanFlowPresented = false

    /// Number of items due for review; drives the Review tab badge.
    private(set) var dueCount = 0

    @MainActor
    func recomputeDueCount(in context: ModelContext) {
        dueCount = SRSEngine.dueCount(in: context)
    }
}
