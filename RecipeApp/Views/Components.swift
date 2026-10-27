import SwiftUI

/// Картинка рецепта: фото с сервера или заглушка — 3D-иллюстрация блюда на мягком фоне.
struct RecipeImage: View {
    let url: URL?
    let rubric: String
    var icon: String = ""

    private var illustration: UIImage? {
        let name = icon.isEmpty ? (Rubric.named(rubric)?.icon ?? "fork-and-knife-with-plate") : icon
        return UIImage(named: "food-\(name)") ?? UIImage(named: "food-fork-and-knife-with-plate")
    }

    private var placeholder: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: RecipeImage.colors(for: rubric), startPoint: .topLeading, endPoint: .bottomTrailing)
                // мягкое пятно света за иллюстрацией
                Circle()
                    .fill(.white.opacity(0.55))
                    .frame(width: min(geo.size.width, geo.size.height) * 0.8)
                    .blur(radius: 18)
                if let illustration {
                    Image(uiImage: illustration)
                        .resizable()
                        .scaledToFit()
                        .frame(height: min(geo.size.height * 0.62, geo.size.width * 0.62))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 6)
                } else {
                    Image(systemName: Rubric.named(rubric)?.symbol ?? "fork.knife")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
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

    /// Пастельные фоны по рубрикам — иллюстрации яркие, фон не должен с ними спорить.
    static func colors(for rubric: String) -> [Color] {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
        switch rubric {
        case "breakfast": return [c(255, 241, 214), c(255, 222, 189)]
        case "soup": return [c(255, 228, 220), c(252, 205, 196)]
        case "salad": return [c(226, 245, 222), c(201, 234, 205)]
        case "main": return [c(250, 232, 216), c(240, 210, 188)]
        case "side": return [c(245, 238, 216), c(232, 222, 190)]
        case "pastry": return [c(252, 230, 238), c(244, 207, 222)]
        default: return [c(236, 236, 244), c(220, 222, 235)]
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
            RecipeImage(url: cover, rubric: recipe.rubric, icon: recipe.icon)
                .frame(height: imageHeight)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.red)
                            .padding(7)
                            .background(.white.opacity(0.85), in: Circle())
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
