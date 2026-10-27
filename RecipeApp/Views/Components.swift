import SwiftUI

/// Картинка рецепта: фото с сервера или аккуратная заглушка с символом рубрики.
struct RecipeImage: View {
    let url: URL?
    let rubric: String

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: RecipeImage.colors(for: rubric), startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: Rubric.named(rubric)?.symbol ?? "fork.knife")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    var body: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: placeholder
                }
            }
        } else {
            placeholder
        }
    }

    static func colors(for rubric: String) -> [Color] {
        switch rubric {
        case "breakfast": return [Color(red: 0.98, green: 0.72, blue: 0.35), Color(red: 0.95, green: 0.50, blue: 0.30)]
        case "soup": return [Color(red: 0.90, green: 0.40, blue: 0.35), Color(red: 0.70, green: 0.22, blue: 0.30)]
        case "salad": return [Color(red: 0.55, green: 0.80, blue: 0.45), Color(red: 0.25, green: 0.60, blue: 0.40)]
        case "main": return [Color(red: 0.85, green: 0.55, blue: 0.35), Color(red: 0.60, green: 0.35, blue: 0.25)]
        case "side": return [Color(red: 0.85, green: 0.75, blue: 0.50), Color(red: 0.65, green: 0.55, blue: 0.35)]
        case "pastry": return [Color(red: 0.95, green: 0.65, blue: 0.70), Color(red: 0.80, green: 0.45, blue: 0.60)]
        default: return [Color(red: 0.70, green: 0.70, blue: 0.75), Color(red: 0.50, green: 0.50, blue: 0.58)]
        }
    }
}

/// Карточка рецепта для главной и избранного.
struct RecipeCard: View {
    let recipe: Recipe
    let cover: URL?
    let kcalPerServing: Double?
    var imageHeight: CGFloat = 130

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RecipeImage(url: cover, rubric: recipe.rubric)
                .frame(height: imageHeight)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.black.opacity(0.25), in: Circle())
                            .padding(8)
                    }
                }
            Text(recipe.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 8) {
                if recipe.cookMinutes > 0 {
                    Label("\(recipe.cookMinutes) мин", systemImage: "clock")
                }
                if let kcalPerServing {
                    Label("\(Int(kcalPerServing.rounded())) ккал", systemImage: "flame")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// КБЖУ: плитки на порцию и строки для всего блюда и 100 г.
struct NutritionBlock: View {
    let summary: NutritionSummary
    let servings: Int

    var body: some View {
        let portion = summary.perServing(servings)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                tile("ккал", portion.kcal, color: .orange)
                tile("белки, г", portion.protein, color: .red)
                tile("жиры, г", portion.fat, color: .yellow)
                tile("углев., г", portion.carbs, color: .blue)
            }
            Text("На порцию (всего порций: \(servings))")
                .font(.caption).foregroundStyle(.secondary)
            Text("Всё блюдо: \(summary.total.shortText)")
                .font(.footnote)
            if let per100 = summary.per100g {
                Text("На 100 г: \(per100.shortText)")
                    .font(.footnote)
            }
            if !summary.missing.isEmpty {
                Text("Без учёта: \(summary.missing.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func tile(_ title: String, _ value: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(value.rounded()))")
                .font(.title3.weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Заголовок раздела на главной.
struct SectionTitle: View {
    let title: String
    var body: some View {
        Text(title).font(.title3.weight(.bold))
    }
}
