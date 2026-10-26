import XCTest
import SwiftData
@testable import RecipeApp

@MainActor
final class CommunityTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(
            for: Recipe.self, Ingredient.self, Product.self, Build.self, BuildItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// Рецепт с двумя ингредиентами и сборкой.
    private func makeBuild() throws -> Build {
        let recipe = Recipe(id: "user-r1", title: "Мой салат", summary: "Быстро", servings: 2, steps: ["Нарезать"])
        recipe.isUserCreated = true
        context.insert(recipe)
        let cheese = Ingredient(id: "user-r1-0", title: "Сыр", categoryId: "feta", amount: 150, unit: .grams, position: 0)
        let tomato = Ingredient(id: "user-r1-1", title: "Томаты", categoryId: "tomatoes", amount: 300, unit: .grams, position: 1)
        cheese.recipe = recipe
        tomato.recipe = recipe
        context.insert(cheese)
        context.insert(tomato)

        let feta = Product(id: "feta-greek", name: "Фета греческая", brand: nil, categoryId: "feta", barcode: nil)
        let cherry = Product(id: "tomato-cherry", name: "Томаты черри", brand: "Агро", categoryId: "tomatoes", barcode: nil)
        context.insert(feta)
        context.insert(cherry)

        let build = Build(name: "Летний", recipe: recipe)
        context.insert(build)
        for (ingredient, product) in [(cheese, feta), (tomato, cherry)] {
            let item = BuildItem(ingredientId: ingredient.id, product: product)
            item.build = build
            context.insert(item)
        }
        try context.save()
        return build
    }

    func testPublishRequestIncludesRecipeAndProducts() throws {
        let build = try makeBuild()
        let request = try XCTUnwrap(CommunityMapper.publishRequest(for: build, authorName: "Гарри"))
        XCTAssertEqual(request.authorName, "Гарри")
        XCTAssertEqual(request.name, "Летний")
        XCTAssertEqual(request.recipe.id, "user-r1")
        XCTAssertEqual(request.recipe.ingredients.map(\.id), ["user-r1-0", "user-r1-1"])
        XCTAssertEqual(request.items.map(\.product.id), ["feta-greek", "tomato-cherry"])

        // На сервер уходит snake_case
        let json = String(decoding: try CommunityClient.encoder.encode(request), as: UTF8.self)
        XCTAssertTrue(json.contains("\"author_name\""))
        XCTAssertTrue(json.contains("\"ingredient_id\""))
        XCTAssertTrue(json.contains("\"category_id\""))
    }

    func testBuildSelectionAndVariantKeepProducts() throws {
        let build = try makeBuild()
        XCTAssertEqual(build.selection, ["user-r1-0": "feta-greek", "user-r1-1": "tomato-cherry"])
    }

    private func sampleDTO(recipeId: String = "community-r", ingredientId: String = "community-r-0") throws -> CommunityBuildDTO {
        let json = """
        {"id": "abc", "author_id": "u1", "author_name": "Мария", "name": "Сырники мечты",
         "created_at": "2026-10-26T20:00:00+00:00",
         "recipe": {"id": "\(recipeId)", "title": "Сырники", "summary": "", "servings": 3, "steps": ["Смешать"],
                    "ingredients": [{"id": "\(ingredientId)", "title": "Творог", "category_id": "tvorog",
                                     "amount": 400, "unit": "g"}]},
         "items": [{"ingredient_id": "\(ingredientId)",
                    "product": {"id": "user-prod-x", "name": "Творог фермерский", "brand": "Ферма",
                                "category_id": "tvorog", "barcode": null}}],
         "rating_avg": 4.5, "rating_count": 2, "score": 3.8, "my_rating": null}
        """
        return try CommunityClient.decoder.decode(CommunityBuildDTO.self, from: Data(json.utf8))
    }

    func testDecodeCommunityBuild() throws {
        let dto = try sampleDTO()
        XCTAssertEqual(dto.authorName, "Мария")
        XCTAssertEqual(dto.ratingAvg, 4.5)
        XCTAssertNil(dto.myRating)
        XCTAssertEqual(dto.cartLines.first?.title, "Творог фермерский · Ферма")
        XCTAssertEqual(dto.cartLines.first?.requiredAmount, 400)
    }

    func testImportCreatesRecipeAndProduct() throws {
        let build = try CommunityMapper.importBuild(try sampleDTO(), into: context)
        XCTAssertEqual(build.authorName, "Мария")
        XCTAssertEqual(build.sourceRemoteId, "abc")
        XCTAssertEqual(build.recipe?.title, "Сырники")
        XCTAssertEqual(build.items.count, 1)
        XCTAssertEqual(build.items.first?.product?.name, "Творог фермерский")

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(recipes.count, 1)
    }

    func testImportIntoExistingRecipeReusesIt() throws {
        let built = try makeBuild()
        let recipeId = try XCTUnwrap(built.recipe?.id)
        _ = try CommunityMapper.importBuild(try sampleDTO(recipeId: recipeId, ingredientId: "user-r1-0"), into: context)

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(recipes.count, 1)
        XCTAssertEqual(recipes.first?.builds.count, 2)
    }
}
