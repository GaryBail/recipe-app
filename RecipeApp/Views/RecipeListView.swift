import SwiftUI
import SwiftData

struct RecipeListView: View {
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @State private var showSettings = false
    @State private var showNewRecipe = false

    private var myRecipes: [Recipe] { recipes.filter(\.isUserCreated) }
    private var catalogRecipes: [Recipe] { recipes.filter { !$0.isUserCreated } }

    var body: some View {
        NavigationStack {
            List {
                if !myRecipes.isEmpty {
                    Section("Мои рецепты") {
                        ForEach(myRecipes) { RecipeRow(recipe: $0) }
                    }
                }
                Section(myRecipes.isEmpty ? "" : "Рецепты") {
                    ForEach(catalogRecipes) { RecipeRow(recipe: $0) }
                }
            }
            .navigationTitle("Рецепты")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        CommunityFeedView()
                    } label: {
                        Label("Сообщество", systemImage: "person.3")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showNewRecipe = true } label: {
                        Label("Новый рецепт", systemImage: "plus")
                    }
                    Button { showSettings = true } label: {
                        Label("Настройки", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showNewRecipe) { RecipeEditorView() }
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .navigationDestination(for: Build.self) { BuildDetailView(build: $0) }
            .overlay {
                if recipes.isEmpty { ProgressView() }
            }
        }
    }
}

private struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        NavigationLink(value: recipe) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title).font(.headline)
                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !recipe.builds.isEmpty {
                    Text("Сборок: \(recipe.builds.count)")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
