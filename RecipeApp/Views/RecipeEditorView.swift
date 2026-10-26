import SwiftUI
import SwiftData

/// Черновик ингредиента в редакторе рецепта: сразу с выбранным продуктом.
struct IngredientDraft: Identifiable, Hashable {
    var id = UUID().uuidString
    var title = ""
    /// nil — новая категория (создаётся по названию ингредиента).
    var categoryId: String?
    var amount: Double = 100
    var unit: MeasureUnit = .grams
    /// Продукт из каталога; nil — свой продукт.
    var productId: String?
    var customProductName = ""
    var customProductBrand = ""

    var hasProduct: Bool { productId != nil || !customProductName.trimmed.isEmpty }
    var isValid: Bool { !title.trimmed.isEmpty && amount > 0 && hasProduct }
}

/// Создание своего рецепта сразу с готовым набором продуктов (первая сборка).
struct RecipeEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Product.name) private var products: [Product]
    @Query private var allIngredients: [Ingredient]

    @State private var title = ""
    @State private var summary = ""
    @State private var servings = 2
    @State private var stepsText = ""
    @State private var drafts: [IngredientDraft] = [IngredientDraft()]

    private var categories: [(id: String, title: String)] {
        CategoryCatalog.titles(ingredients: allIngredients, products: products)
    }

    private var canSave: Bool {
        !title.trimmed.isEmpty && !drafts.isEmpty && drafts.allSatisfy(\.isValid)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Рецепт") {
                    TextField("Название блюда", text: $title)
                    TextField("Коротко о блюде", text: $summary, axis: .vertical)
                        .lineLimit(2...4)
                    Stepper("Порций: \(servings)", value: $servings, in: 1...20)
                }

                Section {
                    ForEach($drafts) { $draft in
                        NavigationLink {
                            IngredientDraftView(draft: $draft, categories: categories, products: products)
                        } label: {
                            DraftRow(draft: draft, productName: productName(for: draft))
                        }
                    }
                    .onDelete { drafts.remove(atOffsets: $0) }
                    .onMove { drafts.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        drafts.append(IngredientDraft())
                    } label: {
                        Label("Добавить ингредиент", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Ингредиенты и продукты")
                } footer: {
                    Text("Для каждого ингредиента выберите конкретный продукт — это будет ваша первая сборка. Потом её можно менять и сохранять варианты.")
                }

                Section {
                    TextEditor(text: $stepsText)
                        .frame(minHeight: 120)
                } header: {
                    Text("Приготовление")
                } footer: {
                    Text("Каждый шаг — с новой строки.")
                }
            }
            .navigationTitle("Новый рецепт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save).disabled(!canSave)
                }
            }
        }
    }

    private func productName(for draft: IngredientDraft) -> String? {
        if let id = draft.productId { return products.first { $0.id == id }?.displayName }
        return draft.customProductName.trimmed.isEmpty ? nil : draft.customProductName.trimmed
    }

    private func save() {
        let recipeId = "user-\(UUID().uuidString.lowercased())"
        let steps = stepsText.split(whereSeparator: \.isNewline).map { String($0).trimmed }.filter { !$0.isEmpty }
        let recipe = Recipe(id: recipeId, title: title.trimmed, summary: summary.trimmed,
                            servings: servings, steps: steps)
        recipe.isUserCreated = true
        context.insert(recipe)

        let build = Build(name: "Моя сборка", recipe: recipe)
        context.insert(build)

        for (index, draft) in drafts.enumerated() {
            let categoryId = draft.categoryId ?? "user-cat-\(UUID().uuidString.lowercased())"
            let ingredient = Ingredient(id: "\(recipeId)-\(index)", title: draft.title.trimmed,
                                        categoryId: categoryId, amount: draft.amount,
                                        unit: draft.unit, position: index)
            ingredient.recipe = recipe
            context.insert(ingredient)

            let product: Product
            if let id = draft.productId, let existing = products.first(where: { $0.id == id }) {
                product = existing
            } else {
                product = Product(id: "user-prod-\(UUID().uuidString.lowercased())",
                                  name: draft.customProductName.trimmed,
                                  brand: draft.customProductBrand.trimmed.isEmpty ? nil : draft.customProductBrand.trimmed,
                                  categoryId: categoryId, barcode: nil)
                context.insert(product)
            }

            let item = BuildItem(ingredientId: ingredient.id, product: product)
            item.build = build
            context.insert(item)
        }

        try? context.save()
        dismiss()
    }
}

private struct DraftRow: View {
    let draft: IngredientDraft
    let productName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(draft.title.trimmed.isEmpty ? "Новый ингредиент" : draft.title)
                .foregroundStyle(draft.title.trimmed.isEmpty ? .secondary : .primary)
            if let productName {
                Text("\(productName) · \(draft.amount.formatted()) \(draft.unit.short)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Выберите продукт")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct IngredientDraftView: View {
    @Binding var draft: IngredientDraft
    let categories: [(id: String, title: String)]
    let products: [Product]

    private var categoryProducts: [Product] {
        guard let id = draft.categoryId else { return [] }
        return products.filter { $0.categoryId == id }
    }

    var body: some View {
        Form {
            Section("Ингредиент") {
                TextField("Например, «Твёрдый сыр»", text: $draft.title)
                HStack {
                    TextField("Количество", value: $draft.amount, format: .number)
                        .keyboardType(.decimalPad)
                    Picker("", selection: $draft.unit) {
                        ForEach(MeasureUnit.allCases, id: \.self) { Text($0.short).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                }
            }

            Section {
                Picker("Категория", selection: $draft.categoryId) {
                    Text("Новая категория").tag(String?.none)
                    ForEach(categories, id: \.id) { Text($0.title).tag(Optional($0.id)) }
                }
                .onChange(of: draft.categoryId) { _, _ in draft.productId = nil }
            } footer: {
                Text("Выберите существующую категорию, чтобы видеть продукты из каталога и сравнивать сборки с другими.")
            }

            Section("Продукт") {
                if !categoryProducts.isEmpty {
                    Picker("Из каталога", selection: $draft.productId) {
                        Text("Свой продукт").tag(String?.none)
                        ForEach(categoryProducts) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                }
                if draft.productId == nil {
                    TextField("Название продукта", text: $draft.customProductName)
                    TextField("Бренд (необязательно)", text: $draft.customProductBrand)
                }
            }
        }
        .navigationTitle(draft.title.trimmed.isEmpty ? "Ингредиент" : draft.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
