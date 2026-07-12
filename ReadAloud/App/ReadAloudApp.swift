import SwiftUI
import SwiftData

@main
struct ReadAloudApp: App {
    let container: ModelContainer
    @State private var router = AppRouter()

    init() {
        do {
            container = try ModelContainer(
                for: Schema(versionedSchema: ReadAloudSchema.self),
                migrationPlan: ReadAloudMigrationPlan.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .tint(Theme.accent)
                // Cap how large text can scale: honor smaller Dynamic Type
                // settings, but ceiling the upper end so large text sizes
                // don't blow up the layout.
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
        .modelContainer(container)
    }
}
