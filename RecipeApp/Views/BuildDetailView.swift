import SwiftUI
import SwiftData

struct BuildDetailView: View {
    let build: Build

    var body: some View {
        List {
            if let recipe = build.recipe {
                Section("Продукты") {
                    ForEach(recipe.sortedIngredients) { ingredient in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(build.product(for: ingredient)?.displayName ?? "—")
                            Text("\(ingredient.title), \(ingredient.amountText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    CartComparisonView(lines: build.cartLines())
                } label: {
                    Label("Где купить дешевле", systemImage: "cart")
                }
            }
        }
        .navigationTitle(build.name)
    }
}
