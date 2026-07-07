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
        }
        .modelContainer(container)
    }
}
