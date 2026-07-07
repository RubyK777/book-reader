import Foundation
import SwiftData

/// Versioned schema so future model changes migrate cleanly.
enum ReadAloudSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Book.self, ScanPage.self, Sentence.self, SavedWord.self]
    }
}

enum ReadAloudMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ReadAloudSchemaV1.self]
    }
    static var stages: [MigrationStage] { [] }
}
