import SwiftData
import SwiftUI

// MARK: - Подборки

extension Ant {
    static func palette(named name: String) -> Palette {
        switch name {
        case "volcano": return volcano
        case "orange": return orange
        case "gold": return gold
        case "green": return green
        case "cyan": return cyan
        case "geekblue": return geekblue
        case "magenta": return magenta
        case "purple": return purple
        case "red": return red
        default: return blue
        }
    }
}

struct CollectionCard: View {
    let collection: RecipeCollection
    let count: Int

    var body: some View {
        let palette = Ant.palette(named: collection.palette)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let image = UIImage(named: "food-\(collection.icon)") {
                    Image(uiImage: image).resizable().scaledToFit().frame(width: 40, height: 40)
                }
                Spacer()
                Text("\(count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Ant.bgContainer.opacity(0.7), in: Capsule())
            }
            Spacer(minLength: 0)
            Text(collection.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Ant.text)
            Text(collection.subtitle)
                .font(.caption)
                .foregroundStyle(Ant.textSecondary)
                .lineLimit(2)
        }
        .padding(Ant.paddingSM)
        .frame(width: 150, height: 130, alignment: .leading)
        .background(palette.bg, in: RoundedRectangle(cornerRadius: Ant.radiusLG, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Ant.radiusLG, style: .continuous).strokeBorder(palette.border))
        .accessibilityElement(children: .combine)
    }
}

struct CollectionView: View {
    let collection: RecipeCollection
    var popularIds: [String] = []

    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @Query private var products: [Product]

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let items = collection.recipes(from: recipes, popularIds: popularIds)
        let nutrition = NutritionIndex(products)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(collection.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Ant.textSecondary)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, recipe in
                        NavigationLink(value: recipe) {
                            RecipeCard(recipe: recipe, cover: nil, kcalPerServing: nutrition.kcalPerServing(recipe))
                        }
                        .buttonStyle(AntPressStyle())
                        .appear(index: index % 6)
                    }
                }
            }
            .padding()
        }
        .background(Ant.bgLayout)
        .navigationTitle(collection.title)
    }
}

// MARK: - «Из того, что есть»

struct FridgeView: View {
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @Query private var products: [Product]
    @Query private var ingredients: [Ingredient]

    /// Выбранные категории сохраняются между запусками.
    @AppStorage("fridgeItems") private var stored = ""
    @AppStorage("fridgeAssumeStaples") private var assumeStaples = true
    @State private var query = ""

    private var selected: Set<String> { Set(stored.split(separator: ",").map(String.init)) }

    private func toggle(_ id: String) {
        var set = selected
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        stored = set.sorted().joined(separator: ",")
    }

    private var allCategories: [(id: String, title: String)] {
        FridgeMatcher.categories(matching: "", ingredients: ingredients, products: products)
    }

    private var suggestions: [(id: String, title: String)] {
        FridgeMatcher.categories(matching: query, ingredients: ingredients, products: products)
            .filter { !selected.contains($0.id) }
    }

    private func title(_ id: String) -> String { allCategories.first { $0.id == id }?.title ?? id }

    var body: some View {
        let results = FridgeMatcher.match(recipes: recipes, available: selected, assumeStaples: assumeStaples)
        List {
            Section {
                TextField("Например: курица, рис, морковь", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(addFirstSuggestion)
                if !selected.isEmpty {
                    WrapLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(selected.sorted { title($0) < title($1) }, id: \.self) { id in
                            Button { withAnimation(.snappy) { toggle(id) } } label: {
                                HStack(spacing: 4) {
                                    Text(title(id))
                                    Image(systemName: "xmark").imageScale(.small)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .foregroundStyle(.white)
                                .background(Ant.primary, in: RoundedRectangle(cornerRadius: Ant.radius, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Убрать \(title(id))")
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Что есть дома")
            } footer: {
                Text("Отметьте продукты — подберём рецепты, где их хватает. Соль, специи, масло и сахар считаем, что есть.")
            }

            Section(query.isEmpty ? "Частые продукты" : "Подходит под «\(query.trimmed)»") {
                WrapLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(Array(suggestions.prefix(query.isEmpty ? 24 : 40)), id: \.id) { cat in
                        Button { withAnimation(.snappy) { toggle(cat.id); query = "" } } label: {
                            Text(cat.title)
                                .font(.subheadline)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .foregroundStyle(Ant.text)
                                .background(Ant.bgContainer, in: RoundedRectangle(cornerRadius: Ant.radius, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Ant.radius, style: .continuous).strokeBorder(Ant.border))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                Toggle("Соль, специи, масло и сахар есть", isOn: $assumeStaples)
            }

            Section {
                if selected.isEmpty {
                    Text("Добавьте хотя бы один продукт.").foregroundStyle(Ant.textTertiary)
                } else if results.isEmpty {
                    Text("Пока ничего не подходит — добавьте ещё продуктов.").foregroundStyle(Ant.textTertiary)
                }
                ForEach(results) { result in
                    NavigationLink(value: result.recipe) {
                        FridgeRow(result: result)
                    }
                }
            } header: {
                Text(results.isEmpty ? "Рецепты" : "Можно приготовить: \(results.count)")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Ant.bgLayout)
        .navigationTitle("Из того, что есть")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addFirstSuggestion() {
        guard let first = suggestions.first else { return }
        toggle(first.id)
        query = ""
    }
}

private struct FridgeRow: View {
    let result: FridgeMatcher.Result

    var body: some View {
        HStack(spacing: 12) {
            RecipeImage(url: nil, rubric: result.recipe.rubric, icon: result.recipe.icon)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: Ant.radius, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(result.recipe.title).font(.subheadline.weight(.semibold)).foregroundStyle(Ant.text)
                if result.isComplete {
                    AntTag(text: "Всё есть", palette: Ant.green, systemImage: "checkmark")
                } else {
                    Text("Не хватает: " + result.missing.map(\.title).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(Ant.orange.text)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Text("\(result.have.count)/\(result.total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Ant.textTertiary)
        }
        .padding(.vertical, 2)
    }
}
