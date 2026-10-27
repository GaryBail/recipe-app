import Foundation

/// Аллергены и ограничения. Определяются по категориям ингредиентов каталога.
enum Allergen: String, CaseIterable, Identifiable, Sendable {
    case milk, eggs, gluten, fish, seafood, nuts, pork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .milk: return "Молоко и молочное"
        case .eggs: return "Яйца"
        case .gluten: return "Глютен (пшеница, рожь, ячмень)"
        case .fish: return "Рыба"
        case .seafood: return "Морепродукты"
        case .nuts: return "Орехи"
        case .pork: return "Свинина"
        }
    }

    var short: String {
        switch self {
        case .milk: return "молочное"
        case .eggs: return "яйца"
        case .gluten: return "глютен"
        case .fish: return "рыба"
        case .seafood: return "морепродукты"
        case .nuts: return "орехи"
        case .pork: return "свинина"
        }
    }

    /// Категории каталога, в которых есть аллерген.
    var categories: Set<String> {
        switch self {
        case .milk:
            return ["milk", "kefir", "cream", "sour-cream", "tvorog", "butter", "hard-cheese", "semi-hard-cheese",
                    "feta", "suluguni", "processed-cheese", "sausage", "frankfurters", "chocolate"]
        case .eggs:
            return ["eggs", "mayonnaise", "noodles"]
        case .gluten:
            return ["flour", "spaghetti", "pasta-short", "noodles", "bread", "semolina", "pearl-barley", "lavash",
                    "oats", "sausage", "frankfurters", "crab-sticks"]
        case .fish:
            return ["salmon", "herring", "white-fish", "canned-fish"]
        case .seafood:
            return ["crab-sticks"]
        case .nuts:
            return []
        case .pork:
            return ["pork", "pork-cured", "smoked-meat", "ham", "minced-meat", "sausage", "smoked-sausage", "frankfurters"]
        }
    }
}

/// Свойства рецепта для фильтров и подборок.
enum RecipeTraits {
    static let meatCategories: Set<String> = [
        "beef", "pork", "pork-cured", "minced-meat", "chicken-fillet", "chicken-thighs", "chicken-liver",
        "sausage", "smoked-sausage", "frankfurters", "ham", "smoked-meat",
    ]
    static let fishCategories: Set<String> = ["salmon", "herring", "white-fish", "canned-fish", "crab-sticks"]
    static let animalCategories: Set<String> = [
        "milk", "kefir", "cream", "sour-cream", "tvorog", "butter", "hard-cheese", "semi-hard-cheese", "feta",
        "suluguni", "processed-cheese", "eggs", "mayonnaise", "honey",
    ]

    static func categories(_ recipe: Recipe) -> Set<String> { Set(recipe.ingredients.map(\.categoryId)) }

    /// Без мяса и рыбы.
    static func isVegetarian(_ recipe: Recipe) -> Bool {
        categories(recipe).isDisjoint(with: meatCategories.union(fishCategories))
    }

    /// Постное: без мяса, рыбы, молочного и яиц.
    static func isLenten(_ recipe: Recipe) -> Bool {
        categories(recipe).isDisjoint(with: meatCategories.union(fishCategories).union(animalCategories))
    }

    static func isQuick(_ recipe: Recipe) -> Bool { recipe.cookMinutes > 0 && recipe.cookMinutes <= 30 }

    static func allergens(in recipe: Recipe) -> [(allergen: Allergen, ingredients: [String])] {
        Allergen.allCases.compactMap { allergen in
            let titles = recipe.sortedIngredients.filter { allergen.categories.contains($0.categoryId) }.map(\.title)
            return titles.isEmpty ? nil : (allergen, titles)
        }
    }
}

/// Ограничения пользователя (из профиля) и проверка рецептов.
struct DietProfile: Equatable, Sendable {
    static let allergensKey = "dietAllergens"
    static let vegetarianKey = "dietVegetarian"
    static let dailyKcalKey = "dailyKcal"

    var allergens: Set<Allergen>
    var vegetarian: Bool

    init(allergens: Set<Allergen> = [], vegetarian: Bool = false) {
        self.allergens = allergens
        self.vegetarian = vegetarian
    }

    /// Из строки настроек «milk,eggs».
    init(stored: String, vegetarian: Bool) {
        self.allergens = Set(stored.split(separator: ",").compactMap { Allergen(rawValue: String($0)) })
        self.vegetarian = vegetarian
    }

    static func store(_ allergens: Set<Allergen>) -> String {
        allergens.map(\.rawValue).sorted().joined(separator: ",")
    }

    var isEmpty: Bool { allergens.isEmpty && !vegetarian }

    /// Предупреждения для рецепта: «молочное: Сметана, Сливочное масло».
    func warnings(for recipe: Recipe) -> [String] {
        var result = RecipeTraits.allergens(in: recipe)
            .filter { allergens.contains($0.allergen) }
            .map { "\($0.allergen.short): \($0.ingredients.joined(separator: ", "))" }
        if vegetarian && !RecipeTraits.isVegetarian(recipe) {
            let meat = recipe.sortedIngredients
                .filter { RecipeTraits.meatCategories.union(RecipeTraits.fishCategories).contains($0.categoryId) }
                .map(\.title)
            result.append("мясо или рыба: \(meat.joined(separator: ", "))")
        }
        return result
    }

    func fits(_ recipe: Recipe) -> Bool { warnings(for: recipe).isEmpty }
}

/// Дневная норма для процентов КБЖУ. Доли энергии: белки 15 %, жиры 30 %, углеводы 55 %.
struct DailyNorm: Equatable, Sendable {
    var kcal: Double

    static let standard = DailyNorm(kcal: 2000)

    var protein: Double { kcal * 0.15 / 4 }
    var fat: Double { kcal * 0.30 / 9 }
    var carbs: Double { kcal * 0.55 / 4 }

    func percent(_ n: Nutrition) -> (kcal: Int, protein: Int, fat: Int, carbs: Int) {
        func p(_ v: Double, _ norm: Double) -> Int { norm > 0 ? Int((v / norm * 100).rounded()) : 0 }
        return (p(n.kcal, kcal), p(n.protein, protein), p(n.fat, fat), p(n.carbs, carbs))
    }
}

/// Фильтры каталога на главной.
enum RecipeFilter: String, CaseIterable, Identifiable, Sendable {
    case quick, vegetarian, lenten, light, safe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: return "До 30 минут"
        case .vegetarian: return "Без мяса"
        case .lenten: return "Постное"
        case .light: return "Лёгкое"
        case .safe: return "Мне подходит"
        }
    }

    var symbol: String {
        switch self {
        case .quick: return "bolt"
        case .vegetarian: return "leaf"
        case .lenten: return "carrot"
        case .light: return "flame"
        case .safe: return "checkmark.shield"
        }
    }

    /// kcal — калорийность порции (если посчитана).
    func matches(_ recipe: Recipe, kcalPerServing: Double?, profile: DietProfile) -> Bool {
        switch self {
        case .quick: return RecipeTraits.isQuick(recipe)
        case .vegetarian: return RecipeTraits.isVegetarian(recipe)
        case .lenten: return RecipeTraits.isLenten(recipe)
        case .light: return (kcalPerServing ?? .infinity) <= 350
        case .safe: return profile.fits(recipe)
        }
    }
}
