import Observation
import SwiftData
import SwiftUI

/// Данные главной с сервера: популярные рецепты (по лайкам за 30 дней) и обложки.
@MainActor
@Observable
final class HomeModel {
    private(set) var popular: [PopularDTO] = []
    private(set) var covers: [String: PhotoDTO] = [:]
    /// Популярное за 7 дней — для подборки «Хиты недели».
    private(set) var weekPopular: [PopularDTO] = []
    private var client: RecipeSocialClient? { RecipeSocialClient.fromSettings() }

    func load(recipeIds: [String]) async {
        guard let client else {
            popular = []
            covers = [:]
            return
        }
        popular = (try? await client.popular(limit: 10)) ?? []
        weekPopular = (try? await client.popular(limit: 10, days: 7)) ?? []
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
    @State private var filters: Set<RecipeFilter> = []
    @State private var cuisine: String? = nil
    @AppStorage(DietProfile.allergensKey) private var allergens = ""
    @AppStorage(DietProfile.vegetarianKey) private var vegetarian = false

    private var profile: DietProfile { DietProfile(stored: allergens, vegetarian: vegetarian) }

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
        let profile = profile
        return recipes.filter { recipe in
            (rubric == nil || recipe.rubric == rubric)
                && (cuisine == nil || recipe.cuisine == cuisine)
                && (query.isEmpty
                    || recipe.title.lowercased().contains(query)
                    || recipe.ingredients.contains { $0.title.lowercased().contains(query) })
                && filters.allSatisfy {
                    $0.matches(recipe, kcalPerServing: $0 == .light ? kcal(recipe) : nil, profile: profile)
                }
        }
    }

    /// КБЖУ карточек: индекс «категория → типичный продукт» строится один раз, а не для каждой карточки.
    @State private var nutrition = NutritionIndex([])

    private func kcal(_ recipe: Recipe) -> Double? { nutrition.kcalPerServing(recipe) }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if search.isEmpty {
                        hero
                        popularSection
                        collectionsSection
                        cuisineChips
                        rubricChips
                        filterChips
                    }
                    if search.isEmpty && rubric == nil && !myRecipes.isEmpty {
                        grid(title: "Мои рецепты", items: myRecipes)
                    }
                    grid(title: gridTitle, items: filtered)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Ant.bgLayout)
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
            .task(id: products.count) { nutrition = NutritionIndex(products) }
            .refreshable { await model.load(recipeIds: recipes.map(\.id)) }
            .overlay { if recipes.isEmpty { ProgressView() } }
        }
    }

    private var gridTitle: String {
        if !search.isEmpty { return filtered.isEmpty ? "Ничего не нашлось" : "Найдено" }
        if filtered.isEmpty { return "Ничего не подошло — снимите часть фильтров" }
        let cuisineTitle: String? = cuisine.flatMap { id in
            Cuisine.named(id).map { c in id == "other" ? "Другие кухни" : "\(c.title) кухня" }
        }
        let parts = [cuisineTitle,
                     rubric.flatMap { Rubric.named($0)?.title }].compactMap { $0 }
        let base = parts.isEmpty ? "Все рецепты" : parts.joined(separator: " · ")
        return filters.isEmpty ? base : "\(base): \(filtered.count)"
    }

    /// Баннер: «аврора» на фоне, заголовок проявляется по словам, счётчики добегают.
    private var hero: some View {
        let catalog = recipes.filter { !$0.isUserCreated }.count
        return VStack(alignment: .leading, spacing: 10) {
            BlurText(text: "Что приготовим сегодня?", font: .title2.weight(.bold))
                .foregroundStyle(.white)
            HStack(spacing: 14) {
                heroStat(Double(catalog), "рецептов")
                heroStat(Double(Rubric.all.count), "рубрик")
                heroStat(Double(products.count), "продуктов")
            }
            Text("Ваши любимые рецепты и продукты в одной корзине")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
            NavigationLink {
                FridgeView()
            } label: {
                Label("Что приготовить из того, что есть?", systemImage: "refrigerator")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Ant.primary)
                    .background(.white, in: RoundedRectangle(cornerRadius: Ant.radiusLG, style: .continuous))
            }
            .buttonStyle(AntPressStyle())
            .padding(.top, 4)
        }
        .padding(Ant.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(colors: [Ant.primary, Ant.geekblue.base], startPoint: .topLeading, endPoint: .bottomTrailing)
                AuroraBackground().opacity(0.9)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Ant.radiusLG * 1.5, style: .continuous))
        .antShadow(elevated: true)
        .appear()
    }

    private func heroStat(_ value: Double, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            CountUpText(value: value, font: .title3.weight(.bold), duration: 1.2)
            Text(title).font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: Ant.radius, style: .continuous))
    }

    private var popularSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AntSectionHeader(title: "Популярное") {
                if model.popular.isEmpty {
                    ShinyText(text: "выбор редакции")
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(popularRecipes) { recipe in
                        NavigationLink(value: recipe) {
                            RecipeCard(recipe: recipe, cover: model.coverURL(for: recipe.id),
                                       kcalPerServing: kcal(recipe), imageHeight: 140)
                                .frame(width: 210)
                        }
                        .buttonStyle(AntPressStyle())
                        .carouselTilt()
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 4)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }

    private var rubricChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Все", symbol: "square.grid.2x2", selected: rubric == nil) { rubric = nil }
                ForEach(Rubric.all) { r in
                    chip(title: r.title, symbol: r.symbol, icon: r.icon, selected: rubric == r.id) {
                        rubric = rubric == r.id ? nil : r.id
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    /// Подборки: хиты недели, сезонная, быстрые, постные, на всю семью.
    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AntSectionHeader(title: "Подборки")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(RecipeCollection.all().enumerated()), id: \.element.id) { index, collection in
                        NavigationLink {
                            CollectionView(collection: collection, popularIds: model.weekPopular.map(\.recipeId))
                        } label: {
                            CollectionCard(collection: collection,
                                           count: collection.recipes(from: recipes,
                                                                     popularIds: model.weekPopular.map(\.recipeId)).count)
                        }
                        .buttonStyle(AntPressStyle())
                        .appear(index: index)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    /// Кухни мира: русская, итальянская, японская…
    private var cuisineChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            AntSectionHeader(title: "Кухни мира")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Cuisine.all.filter { c in recipes.contains { $0.cuisine == c.id } }) { c in
                        Button {
                            withAnimation(.snappy) { cuisine = cuisine == c.id ? nil : c.id }
                        } label: {
                            VStack(spacing: 4) {
                                if let image = UIImage(named: "food-\(c.icon)") {
                                    Image(uiImage: image).resizable().scaledToFit().frame(width: 34, height: 34)
                                }
                                Text(c.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                            }
                            .frame(width: 84, height: 70)
                            .foregroundStyle(cuisine == c.id ? Color.white : Ant.text)
                            .background(cuisine == c.id ? Ant.primary : Ant.bgContainer,
                                        in: RoundedRectangle(cornerRadius: Ant.radiusLG, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Ant.radiusLG, style: .continuous)
                                .strokeBorder(cuisine == c.id ? Color.clear : Ant.borderSecondary))
                        }
                        .buttonStyle(AntPressStyle())
                        .accessibilityLabel("\(c.title) кухня")
                        .accessibilityAddTraits(cuisine == c.id ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RecipeFilter.allCases.filter { $0 != .safe || !profile.isEmpty }) { f in
                    AntCheckableTag(title: f.title, selected: filters.contains(f)) {
                        Image(systemName: f.symbol)
                    } action: {
                        withAnimation(.snappy) {
                            if filters.contains(f) { filters.remove(f) } else { filters.insert(f) }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func chip(title: String, symbol: String, icon: String? = nil, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        AntCheckableTag(title: title, selected: selected) {
            if let icon, let image = UIImage(named: "food-\(icon)") {
                Image(uiImage: image).resizable().scaledToFit().frame(width: 20, height: 20)
            } else {
                Image(systemName: symbol)
            }
        } action: {
            withAnimation(.snappy) { action() }
        }
    }

    private func grid(title: String, items: [Recipe]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: title)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, recipe in
                    NavigationLink(value: recipe) {
                        RecipeCard(recipe: recipe, cover: model.coverURL(for: recipe.id), kcalPerServing: kcal(recipe))
                    }
                    .buttonStyle(AntPressStyle())
                    .appear(index: index % 6)
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
    @State private var nutrition = NutritionIndex([])

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
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(Array(favorites.enumerated()), id: \.element.id) { index, recipe in
                                NavigationLink(value: recipe) {
                                    RecipeCard(recipe: recipe, cover: model.coverURL(for: recipe.id),
                                               kcalPerServing: nutrition.kcalPerServing(recipe))
                                }
                                .buttonStyle(AntPressStyle())
                                .appear(index: index % 6)
                            }
                        }
                        .padding()
                    }
                    .background(Ant.bgLayout)
                }
            }
            .navigationTitle("Избранное")
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .navigationDestination(for: Build.self) { BuildDetailView(build: $0) }
            .task(id: favorites.count) { await model.load(recipeIds: favorites.map(\.id)) }
            .task(id: products.count) { nutrition = NutritionIndex(products) }
        }
    }
}
