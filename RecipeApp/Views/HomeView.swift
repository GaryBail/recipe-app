import Observation
import SwiftData
import SwiftUI

/// Данные главной с сервера: популярные рецепты (по лайкам за 30 дней) и обложки.
@MainActor
@Observable
final class HomeModel {
    private(set) var popular: [PopularDTO] = []
    private(set) var covers: [String: PhotoDTO] = [:]
    private var client: RecipeSocialClient? { RecipeSocialClient.fromSettings() }

    func load(recipeIds: [String]) async {
        guard let client else {
            popular = []
            covers = [:]
            return
        }
        popular = (try? await client.popular(limit: 10)) ?? []
        covers = (try? await client.covers(for: recipeIds)) ?? covers
    }

    func coverURL(for recipeId: String) -> URL? {
        guard let client, let photo = covers[recipeId] ?? popular.first(where: { $0.recipeId == recipeId })?.cover
        else { return nil }
        return client.url(photo.thumbUrl)
    }
}

struct HomeView: View {
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @Query private var products: [Product]
    @AppStorage(PriceProviderFactory.serverURLKey) private var serverURL = ""

    @State private var model = HomeModel()
    @State private var search = ""
    @State private var rubric: String? = nil
    @State private var showNewRecipe = false

    private var myRecipes: [Recipe] { recipes.filter(\.isUserCreated) }

    /// Популярное по лайкам; пока лайков нет (или нет сервера) — избранные редакцией.
    private var popularRecipes: [Recipe] {
        let byId = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let fromServer = model.popular.compactMap { byId[$0.recipeId] }
        let featured = recipes.filter(\.featured)
        return Array((fromServer + featured.filter { r in !fromServer.contains { $0.id == r.id } }).prefix(10))
    }

    private var filtered: [Recipe] {
        let query = search.trimmed.lowercased()
        return recipes.filter { recipe in
            (rubric == nil || recipe.rubric == rubric)
                && (query.isEmpty
                    || recipe.title.lowercased().contains(query)
                    || recipe.ingredients.contains { $0.title.lowercased().contains(query) })
        }
    }

    private func kcal(_ recipe: Recipe) -> Double? {
        let summary = NutritionCalculator.recipeSummary(recipe, products: products)
        return summary.grams > 0 ? summary.perServing(recipe.servings).kcal : nil
    }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if search.isEmpty {
                        popularSection
                        rubricChips
                    }
                    if search.isEmpty && rubric == nil && !myRecipes.isEmpty {
                        grid(title: "Мои рецепты", items: myRecipes)
                    }
                    grid(title: gridTitle, items: filtered)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Рецепты")
            .searchable(text: $search, prompt: "Блюдо или продукт")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NotificationsBell()
                    Button { showNewRecipe = true } label: {
                        Label("Новый рецепт", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewRecipe) { RecipeEditorView() }
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .navigationDestination(for: Build.self) { BuildDetailView(build: $0) }
            .task(id: serverURL) { await model.load(recipeIds: recipes.map(\.id)) }
            .refreshable { await model.load(recipeIds: recipes.map(\.id)) }
            .overlay { if recipes.isEmpty { ProgressView() } }
        }
    }

    private var gridTitle: String {
        if !search.isEmpty { return filtered.isEmpty ? "Ничего не нашлось" : "Найдено" }
        if let rubric, let r = Rubric.named(rubric) { return r.title }
        return "Все рецепты"
    }

    private var popularSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(title: "Популярное")
                Spacer()
                if model.popular.isEmpty {
                    Text("выбор редакции").font(.caption).foregroundStyle(.secondary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(popularRecipes) { recipe in
                        NavigationLink(value: recipe) {
                            RecipeCard(recipe: recipe, cover: model.coverURL(for: recipe.id),
                                       kcalPerServing: kcal(recipe), imageHeight: 150)
                                .frame(width: 210)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private var rubricChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Все", symbol: "square.grid.2x2", selected: rubric == nil) { rubric = nil }
                ForEach(Rubric.all) { r in
                    chip(title: r.title, symbol: r.symbol, selected: rubric == r.id) {
                        rubric = rubric == r.id ? nil : r.id
                    }
                }
            }
        }
    }

    private func chip(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func grid(title: String, items: [Recipe]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: title)
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(items) { recipe in
                    NavigationLink(value: recipe) {
                        RecipeCard(recipe: recipe, cover: model.coverURL(for: recipe.id), kcalPerServing: kcal(recipe))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Избранное — рецепты, которые пользователь отметил сердечком.
struct FavoritesView: View {
    @Query(filter: #Predicate<Recipe> { $0.isFavorite }) private var favoriteRecipes: [Recipe]

    /// Сначала недавно добавленные.
    private var favorites: [Recipe] {
        favoriteRecipes.sorted { ($0.favoritedAt ?? .distantPast) > ($1.favoritedAt ?? .distantPast) }
    }
    @Query private var products: [Product]
    @State private var model = HomeModel()

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            Group {
                if favorites.isEmpty {
                    ContentUnavailableView {
                        Label("Пока пусто", systemImage: "heart")
                    } description: {
                        Text("Нажмите ♡ на странице рецепта — он появится здесь.")
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(favorites) { recipe in
                                NavigationLink(value: recipe) {
                                    let s = NutritionCalculator.recipeSummary(recipe, products: products)
                                    RecipeCard(recipe: recipe, cover: model.coverURL(for: recipe.id),
                                               kcalPerServing: s.grams > 0 ? s.perServing(recipe.servings).kcal : nil)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Избранное")
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .navigationDestination(for: Build.self) { BuildDetailView(build: $0) }
            .task(id: favorites.count) { await model.load(recipeIds: favorites.map(\.id)) }
        }
    }
}
