import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    let recipe: Recipe

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isCreatingBuild = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                if !recipe.summary.isEmpty { Text(recipe.summary) }
                Label("Порций: \(recipe.servings)", systemImage: "person.2")
                    .foregroundStyle(.secondary)
                if recipe.isUserCreated {
                    Label("Ваш рецепт", systemImage: "person.crop.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Ингредиенты") {
                ForEach(recipe.sortedIngredients) { ingredient in
                    LabeledContent(ingredient.title, value: ingredient.amountText)
                }
            }

            Section {
                ForEach(recipe.builds.sorted { $0.createdAt > $1.createdAt }) { build in
                    NavigationLink(value: build) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(build.name)
                                if build.isPublished {
                                    Image(systemName: "globe").font(.caption).foregroundStyle(.tint)
                                }
                            }
                            Text(build.authorName.map { "Автор: \($0)" } ?? build.createdAt.formatted(date: .abbreviated, time: .omitted))
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
            } header: {
                Text("Мои сборки")
            } footer: {
                if !recipe.builds.isEmpty {
                    Text("Откройте сборку, чтобы изменить её, сохранить новый вариант или поделиться.")
                }
            }

            CommunityBuildsSection(recipeId: recipe.id)

            if !recipe.steps.isEmpty {
                Section("Приготовление") {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top) {
                            Text("\(index + 1).").bold()
                            Text(step)
                        }
                    }
                }
            }

            if recipe.isUserCreated {
                Section {
                    Button("Удалить рецепт", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(recipe.title)
        .sheet(isPresented: $isCreatingBuild) {
            BuildEditorView(recipe: recipe)
        }
        .confirmationDialog("Удалить рецепт и все его сборки?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                context.delete(recipe)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("Опубликованные сборки останутся в сообществе, пока вы не снимете их с публикации.")
        }
    }
}
