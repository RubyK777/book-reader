import SwiftUI
import SwiftData
import WidgetKit

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
        updateWidgetSnapshot(in: context)
    }

    /// Push the values the home-screen widget shows into the App Group and ask
    /// WidgetKit to refresh: the due count, plus a "phrase to remember" (the
    /// newest saved annotation, with its sentence's translation when there is one).
    @MainActor
    private func updateWidgetSnapshot(in context: ModelContext) {
        SharedStore.writeDueCount(dueCount)

        var descriptor = FetchDescriptor<Annotation>(sortBy: [SortDescriptor(\.savedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        let newest = try? context.fetch(descriptor).first
        SharedStore.writePhrase(newest?.text,
                                translation: newest?.sentence?.translatedText,
                                languageCode: newest?.languageCode)

        WidgetCenter.shared.reloadAllTimelines()
    }
}
