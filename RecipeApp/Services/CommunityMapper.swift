import Foundation
import SwiftData

/// Перевод между локальными моделями и сборками сообщества.
enum CommunityMapper {
    /// Сборка → запрос на публикацию. Вместе со сборкой публикуется рецепт,
    /// чтобы свои рецепты пользователей тоже можно было открыть у других.
    static func publishRequest(for build: Build, authorName: String) -> PublishBuildRequest? {
        guard let recipe = build.recipe else { return nil }
        let ingredients = recipe.sortedIngredients
        let items: [CommunityItemDTO] = ingredients.compactMap { ingredient in
            guard let p = build.product(for: ingredient) else { return nil }
            return CommunityItemDTO(
                ingredientId: ingredient.id,
                product: CommunityProductDTO(id: p.id, name: p.name, brand: p.brand,
                                             categoryId: p.categoryId, barcode: p.barcode))
        }
        guard !items.isEmpty else { return nil }

        let recipeDTO = CommunityRecipeDTO(
            id: recipe.id, title: recipe.title, summary: recipe.summary,
            servings: recipe.servings, steps: recipe.steps,
            ingredients: ingredients.map {
                CommunityIngredientDTO(id: $0.id, title: $0.title, categoryId: $0.categoryId,
                                       amount: $0.amount, unit: $0.unitRaw)
            })
        return PublishBuildRequest(authorName: authorName, name: build.name, recipe: recipeDTO, items: items)
    }

    /// Сохраняет чужую сборку себе. Если рецепта нет — создаёт его, недостающие продукты добавляет в каталог.
    @MainActor
    @discardableResult
    static func importBuild(_ dto: CommunityBuildDTO, into context: ModelContext) throws -> Build {
        let existing = try existingRecipe(id: dto.recipe.id, in: context)
        let recipe = existing ?? createRecipe(dto.recipe, in: context)
        // У локальной копии рецепта могут быть другие ингредиенты — берём только совпадающие.
        let localIngredientIds = existing.map { Set($0.ingredients.map(\.id)) }
            ?? Set(dto.recipe.ingredients.map(\.id))

        let build = Build(name: dto.name, recipe: recipe)
        build.authorName = dto.authorName
        build.sourceRemoteId = dto.id
        context.insert(build)

        for item in dto.items where localIngredientIds.contains(item.ingredientId) {
            let product = try existingProduct(id: item.product.id, in: context) ?? {
                let p = Product(id: item.product.id, name: item.product.name, brand: item.product.brand,
                                categoryId: item.product.categoryId, barcode: item.product.barcode)
                context.insert(p)
                return p
            }()
            let buildItem = BuildItem(ingredientId: item.ingredientId, product: product)
            buildItem.build = build
            context.insert(buildItem)
        }

        try context.save()
        return build
    }

    @MainActor
    private static func existingRecipe(id: String, in context: ModelContext) throws -> Recipe? {
        var descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @MainActor
    private static func existingProduct(id: String, in context: ModelContext) throws -> Product? {
        var descriptor = FetchDescriptor<Product>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @MainActor
    private static func createRecipe(_ dto: CommunityRecipeDTO, in context: ModelContext) -> Recipe {
        let recipe = Recipe(id: dto.id, title: dto.title, summary: dto.summary,
                            servings: dto.servings, steps: dto.steps)
        context.insert(recipe)
        for (index, i) in dto.ingredients.enumerated() {
            let ingredient = Ingredient(id: i.id, title: i.title, categoryId: i.categoryId, amount: i.amount,
                                        unit: MeasureUnit(rawValue: i.unit) ?? .pieces, position: index)
            ingredient.recipe = recipe
            context.insert(ingredient)
        }
        return recipe
    }
}
