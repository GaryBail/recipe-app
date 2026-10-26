import SwiftUI
import SwiftData

/// Экран сборки: для каждого ингредиента рецепта пользователь выбирает конкретный продукт.
struct BuildEditorView: View {
    let recipe: Recipe

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Product.name) private var products: [Product]

    @State private var name = ""
    /// ingredientId → productId
    @State private var selection: [String: String] = [:]

    private var ingredients: [Ingredient] { recipe.sortedIngredients }

    private var isComplete: Bool {
        ingredients.allSatisfy { selection[$0.id] != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Моя \(recipe.title.lowercased())", text: $name)
                }

                Section {
                    ForEach(ingredients) { ingredient in
                        Picker(selection: binding(for: ingredient)) {
                            Text("Не выбран").tag(String?.none)
                            ForEach(products(in: ingredient.categoryId)) { product in
                                Text(product.displayName).tag(Optional(product.id))
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(ingredient.title)
                                Text(ingredient.amountText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Выберите продукты")
                } footer: {
                    Text("Сборка сохранится для этого рецепта, позже ей можно будет поделиться.")
                }
            }
            .navigationTitle("Новая сборка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save).disabled(!isComplete)
                }
            }
        }
    }

    private func products(in categoryId: String) -> [Product] {
        products.filter { $0.categoryId == categoryId }
    }

    private func binding(for ingredient: Ingredient) -> Binding<String?> {
        Binding(
            get: { selection[ingredient.id] },
            set: { selection[ingredient.id] = $0 }
        )
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let build = Build(name: trimmed.isEmpty ? "Моя \(recipe.title.lowercased())" : trimmed,
                          recipe: recipe)
        context.insert(build)

        for ingredient in ingredients {
            guard let productId = selection[ingredient.id],
                  let product = products.first(where: { $0.id == productId }) else { continue }
            let item = BuildItem(ingredientId: ingredient.id, product: product)
            item.build = build
            context.insert(item)
        }

        try? context.save()
        dismiss()
    }
}
