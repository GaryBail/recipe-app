import Foundation

/// Справочник каталога из seed.json: рубрики, кухни, категории продуктов и их свойства.
/// Файл (почти 1 МБ) читается один раз за запуск — все остальные места берут данные отсюда.
enum Catalog {
    static let seed: SeedLoader.SeedFile? = SeedLoader.load()

    static let rubrics: [Rubric] = seed?.rubrics ?? []
    static let cuisines: [Cuisine] = seed?.cuisines ?? []
    static let departments: [String] = seed?.departments ?? ["Другое"]

    static let categories: [String: CategoryInfo] = Dictionary(
        (seed?.categories ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    static func category(_ id: String) -> CategoryInfo? { categories[id] }

    /// Категории с признаком: "meat", "fish", "animal", "staple".
    static func categories(tagged tag: String) -> Set<String> { tagIndex[tag] ?? [] }

    /// Категории, в которых есть аллерген ("milk", "gluten"…).
    static func categories(withAllergen allergen: String) -> Set<String> { allergenIndex[allergen] ?? [] }

    /// Отдел магазина для списка покупок. Свои категории пользователя — в «Другое».
    static func department(for categoryId: String) -> (order: Int, title: String) {
        let last = max(departments.count - 1, 0)
        let order = categories[categoryId]?.department ?? last
        return (order, departments.indices.contains(order) ? departments[order] : "Другое")
    }

    private static let tagIndex: [String: Set<String>] = index(\.tags)
    private static let allergenIndex: [String: Set<String>] = index(\.allergens)

    private static func index(_ key: KeyPath<CategoryInfo, [String]?>) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for info in categories.values {
            for value in info[keyPath: key] ?? [] { result[value, default: []].insert(info.id) }
        }
        return result
    }
}

/// Категория продуктов в каталоге: название, отдел магазина, аллергены, признаки.
struct CategoryInfo: Decodable, Hashable, Sendable {
    let id: String
    let title: String
    let department: Int?
    let allergens: [String]?
    let tags: [String]?
}
