import SwiftUI
import SwiftData

/// Экран сборки: для каждого ингредиента рецепта пользователь выбирает конкретный продукт.
/// Режимы: новая сборка, новый вариант на основе существующей, редактирование.
struct BuildEditorView: View {
    enum Mode {
        case new
        case variant(of: Build)
        case edit(Build)
    }

    let recipe: Recipe
    let mode: Mode
    /// Порции новой сборки (с экрана рецепта).
    var servings: Int? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Product.name) private var products: [Product]

    @State private var name: String
    /// ingredientId → productId
    @State private var selection: [String: String]
    @State private var addingProductFor: Ingredient?
    @State private var choices: ChoicesDTO?

    init(recipe: Recipe, mode: Mode = .new, servings: Int? = nil) {
        self.recipe = recipe
        self.mode = mode
        self.servings = servings
        switch mode {
        case .new:
            _name = State(initialValue: "")
            _selection = State(initialValue: [:])
        case .variant(let source):
            _name = State(initialValue: "\(source.name) — вариант")
            _selection = State(initialValue: source.selection)
        case .edit(let build):
            _name = State(initialValue: build.name)
            _selection = State(initialValue: build.selection)
        }
    }

    private var ingredients: [Ingredient] { recipe.sortedIngredients }

    private var isComplete: Bool {
        ingredients.allSatisfy { selection[$0.id] != nil }
    }

    private var title: String {
        switch mode {
        case .new: return "Новая сборка"
        case .variant: return "Новый вариант"
        case .edit: return "Изменить сборку"
        }
    }

    private var defaultName: String { "Моя \(recipe.title.lowercased())" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField(defaultName, text: $name)
                }

                if let choices, choices.builds > 0 {
                    Section {
                        Button {
                            withAnimation(.snappy) { applyPopular() }
                        } label: {
                            Label("Выбрать как большинство", systemImage: "person.3.sequence.fill")
                        }
                    } footer: {
                        Text("По \(choices.builds) \(buildsWord(choices.builds)) сообщества: для каждого ингредиента — самый частый выбор.")
                    }
                }

                Section {
                    ForEach(ingredients) { ingredient in
                        VStack(alignment: .leading, spacing: 6) {
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
                            .accessibilityIdentifier("picker-\(ingredient.id)")
                            if let top = choices?.ingredients[ingredient.id]?.first {
                                Button {
                                    withAnimation(.snappy) { select(top.product, for: ingredient) }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "star.circle.fill")
                                        Text("Чаще выбирают: \(top.product.displayName) · \(top.count)")
                                            .lineLimit(1)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(selection[ingredient.id] == top.product.id ? Ant.success : Ant.primary)
                                }
                                .buttonStyle(.borderless)
                            }
                            Button("Добавить свой продукт…") { addingProductFor = ingredient }
                                .font(.caption)
                                .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Выберите продукты")
                } footer: {
                    if case .edit(let build) = mode, build.isPublished {
                        Text("Опубликованная версия обновится, когда вы опубликуете сборку заново.")
                    } else {
                        Text("Сборка сохранится для этого рецепта, ей можно поделиться в сообществе.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save).disabled(!isComplete)
                }
            }
            .task { await loadChoices() }
            .sheet(item: $addingProductFor) { ingredient in
                NewProductView(categoryId: ingredient.categoryId, categoryTitle: ingredient.title) { product in
                    selection[ingredient.id] = product.id
                }
            }
        }
    }

    private func loadChoices() async {
        guard let client = CommunityClient.fromSettings() else { return }
        choices = try? await client.choices(recipeId: recipe.id)
    }

    private func buildsWord(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "сборке" }
        return "сборкам"
    }

    /// Выбор продукта из сообщества: если его нет в каталоге телефона — добавляем.
    private func select(_ dto: CommunityProductDTO, for ingredient: Ingredient) {
        if !products.contains(where: { $0.id == dto.id }) {
            let product = Product(id: dto.id, name: dto.name, brand: dto.brand,
                                  categoryId: ingredient.categoryId, barcode: dto.barcode)
            context.insert(product)
            try? context.save()
        }
        selection[ingredient.id] = dto.id
    }

    private func applyPopular() {
        for ingredient in ingredients {
            if let top = choices?.ingredients[ingredient.id]?.first { select(top.product, for: ingredient) }
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
        let finalName = name.trimmed.isEmpty ? defaultName : name.trimmed
        let build: Build
        if case .edit(let existing) = mode {
            build = existing
            build.name = finalName
            for item in build.items { context.delete(item) }
            build.items = []
        } else {
            build = Build(name: finalName, recipe: recipe)
            if case .variant(let source) = mode { build.servings = source.servings }
            if let servings, servings != recipe.servings { build.servings = servings }
            context.insert(build)
        }

        for ingredient in ingredients {
            guard let productId = selection[ingredient.id],
                  let product = products.first(where: { $0.id == productId }) else { continue }
            let item = BuildItem(ingredientId: ingredient.id, product: product)
            item.build = build
            context.insert(item)
        }

        try? context.save()
        PriceWatchClient.resyncIfWatched(build)
        dismiss()
    }
}

/// Добавление своего продукта в категорию (например, сыра, которого нет в каталоге).
struct NewProductView: View {
    let categoryId: String
    let categoryTitle: String
    var onCreate: (Product) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brand = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название, например «Пармезан 24 мес.»", text: $name)
                    TextField("Бренд (необязательно)", text: $brand)
                } footer: {
                    Text("Продукт появится в категории «\(categoryTitle)».")
                }
            }
            .navigationTitle("Свой продукт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        let product = Product(id: "user-prod-\(UUID().uuidString.lowercased())",
                                              name: name.trimmed,
                                              brand: brand.trimmed.isEmpty ? nil : brand.trimmed,
                                              categoryId: categoryId, barcode: nil)
                        context.insert(product)
                        try? context.save()
                        onCreate(product)
                        dismiss()
                    }
                    .disabled(name.trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
