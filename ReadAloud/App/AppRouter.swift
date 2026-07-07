import SwiftUI

/// Root tabs.
enum AppTab: Hashable {
    case library, saved, review, settings
}

/// App-wide navigation state, injected via `.environment`.
@Observable
final class AppRouter {
    var tab: AppTab = .library
    var libraryPath = NavigationPath()
    var isScanFlowPresented = false
}
