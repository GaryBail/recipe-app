import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    let recipe: Recipe
    @State private var isCreatingBuild = false

    var body: some View {
        List {
            Section {
                Text(recipe.summary)
                Label("Порций: \(recipe.servings)", systemImage: "person.2")
                    .foregroundStyle(.secondary)
            }

            Section("Ингредиенты") {
                ForEach(recipe.sortedIngredients) { ingredient in
                    LabeledContent(ingredient.title, value: ingredient.amountText)
                }
            }

            Section("Мои сборки") {
                ForEach(recipe.builds.sorted { $0.createdAt > $1.createdAt }) { build in
                    NavigationLink(value: build) {
                        VStack(alignment: .leading) {
                            Text(build.name)
                            Text(build.createdAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    isCreatingBuild = true
                } label: {
                    Label("Собрать продукты", systemImage: "plus.circle")
                }
            }

            Section("Приготовление") {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top) {
                        Text("\(index + 1).").bold()
                        Text(step)
                    }
                }
            }
        }
        .navigationTitle(recipe.title)
        .sheet(isPresented: $isCreatingBuild) {
            BuildEditorView(recipe: recipe)
        }
    }
}
