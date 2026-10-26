import SwiftUI
import SwiftData

struct RecipeListView: View {
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List(recipes) { recipe in
                NavigationLink(value: recipe) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.title).font(.headline)
                        Text(recipe.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if !recipe.builds.isEmpty {
                            Text("Сборок: \(recipe.builds.count)")
                                .font(.caption)
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Рецепты")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .navigationDestination(for: Build.self) { BuildDetailView(build: $0) }
            .overlay {
                if recipes.isEmpty { ProgressView() }
            }
        }
    }
}
