import Foundation
import SwiftData

/// Версии схемы данных на телефоне. После выхода в App Store модели меняем только так:
/// 1. Скопировать текущие модели в новое пространство (`enum SchemaV2: VersionedSchema { @Model final class Recipe … }`),
///    внести изменения уже там, а верхнеуровневые `Recipe` и т.д. сделать typealias на последнюю версию.
/// 2. Добавить `SchemaV2` в `AppMigrationPlan.schemas` и шаг в `stages`:
///    `.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)` для простых изменений
///    (новое поле со значением по умолчанию, новая модель) или `.custom(…)`, если данные нужно перенести.
/// Без этого изменение модели может не открыть старую базу — и у пользователя пропадут сборки и избранное.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Recipe.self, Ingredient.self, Product.self, Build.self, BuildItem.self, ShoppingItem.self]
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum AppModelContainer {
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(for: Schema(versionedSchema: SchemaV1.self),
                           migrationPlan: AppMigrationPlan.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }

    /// Контейнер приложения. Если базу открыть не удалось (например, ошибка миграции), приложение
    /// запускается с временной базой в памяти, а файл на диске не трогается — данные можно спасти обновлением.
    static let shared: ModelContainer = {
        do {
            return try make()
        } catch {
            NSLog("Не удалось открыть базу: \(error). Временно работаем без сохранения.")
            UserDefaults.standard.set(String(describing: error), forKey: "lastStoreError")
            // swiftlint:disable:next force_try
            return try! make(inMemory: true)
        }
    }()
}
