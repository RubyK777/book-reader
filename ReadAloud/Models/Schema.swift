import Foundation
import SwiftData

/// Versioned schema so future model changes migrate cleanly.
///
/// The app is **pre-ship**, so every field added so far (incl. the translation
/// fields `Book.translationLanguage` / `Sentence.translatedText`, and the
/// planned `SavedWord.sourceBookTitle`) folds into this single V1 version —
/// there is no shipped store to migrate from, and two versions listing the
/// same model classes produce identical checksums that SwiftData rejects.
///
/// IMPORTANT (TRANSLATION_DESIGN §2, PHASE2_DESIGN §1): before the FIRST model
/// change that lands *after* a build reaches a real device (e.g. Ruby's
/// TestFlight install), freeze the current models as `ReadAloudSchemaV1` with
/// its own nested copies, add `ReadAloudSchemaV2` = the new models, and a
/// `.lightweight` stage between them — that snapshot is what her store migrates
/// from. Until then, one version is correct.
enum ReadAloudSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Book.self, ScanPage.self, Sentence.self, SavedWord.self]
    }
}

/// Current schema the container opens against.
typealias ReadAloudSchema = ReadAloudSchemaV1

enum ReadAloudMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ReadAloudSchemaV1.self]
    }
    static var stages: [MigrationStage] { [] }
}
