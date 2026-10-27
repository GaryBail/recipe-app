import SwiftUI
import UIKit

/// Тексты для «Поделиться»: уходят через системное меню в Telegram, WhatsApp, VK, «Сообщения» и т.д.
/// Обычный текст с эмодзи — так он одинаково хорошо выглядит в любом мессенджере.
enum ShareText {
    static func recipe(_ recipe: Recipe, products: [Product]) -> String {
        var lines: [String] = []
        lines.append("🍽 \(recipe.title)")
        if !recipe.summary.isEmpty { lines.append(recipe.summary) }
        lines.append("")

        var facts: [String] = []
        if recipe.cookMinutes > 0 { facts.append("⏱ \(recipe.cookMinutes) мин") }
        facts.append("👥 \(recipe.servings) \(portions(recipe.servings))")
        let nutrition = NutritionCalculator.recipeSummary(recipe, products: products)
        if nutrition.grams > 0 {
            facts.append("🔥 ≈ \(Int(nutrition.perServing(recipe.servings).kcal.rounded())) ккал на порцию")
        }
        lines.append(facts.joined(separator: " · "))
        lines.append("")

        lines.append("Ингредиенты:")
        for ingredient in recipe.sortedIngredients {
            lines.append("• \(ingredient.title) — \(ingredient.amountText)")
        }

        if !recipe.steps.isEmpty {
            lines.append("")
            lines.append("Приготовление:")
            for (index, step) in recipe.steps.enumerated() {
                lines.append("\(index + 1). \(step)")
            }
        }

        lines.append("")
        lines.append("Рецепт из приложения «ВыборВкуса»")
        return lines.joined(separator: "\n")
    }

    /// Список покупок по сборке — с конкретными продуктами.
    static func build(_ build: Build) -> String {
        guard let recipe = build.recipe else { return build.name }
        var lines = ["🛒 Продукты для «\(recipe.title)»"]
        if build.name != "Моя \(recipe.title.lowercased())" {
            lines.append("Сборка «\(build.name)»")
        }
        lines.append("")
        for ingredient in recipe.sortedIngredients {
            let product = build.product(for: ingredient)?.displayName ?? ingredient.title
            lines.append("☐ \(product) — \(ingredient.amountText(servings: build.effectiveServings))")
        }
        let nutrition = NutritionCalculator.buildSummary(build)
        if nutrition.grams > 0 {
            lines.append("")
            lines.append("На порцию: \(nutrition.perServing(recipe.servings).shortText)")
        }
        lines.append("")
        lines.append("Собрано в приложении «ВыборВкуса»")
        return lines.joined(separator: "\n")
    }

    static func previewImage(for recipe: Recipe) -> Image {
        let name = recipe.icon.isEmpty ? (Rubric.named(recipe.rubric)?.icon ?? "fork-and-knife-with-plate") : recipe.icon
        if let image = UIImage(named: "food-\(name)") {
            return Image(uiImage: image)
        }
        return Image(systemName: "fork.knife")
    }

    static func portions(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "порция" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "порции" }
        return "порций"
    }
}
