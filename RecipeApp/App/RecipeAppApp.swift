import SwiftUI
import SwiftData

@main
struct RecipeAppApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            Recipe.self,
            Ingredient.self,
            Product.self,
            Build.self,
            BuildItem.self
        ])
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        RecipeListView()
            .task { SeedLoader.seedIfNeeded(context) }
    }
}
