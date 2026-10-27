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

/// Карточка рецепта в стиле Ant Design Card: обложка сверху, тело с заголовком и тегами.
struct RecipeCard: View {
    let recipe: Recipe
    let cover: URL?
    let kcalPerServing: Double?
    var imageHeight: CGFloat = 120

    private var rubric: Rubric? { Rubric.named(recipe.rubric) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecipeImage(url: cover, rubric: recipe.rubric, icon: recipe.icon)
                .frame(height: imageHeight)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Ant.red.base)
                            .padding(6)
                            .background(Ant.bgContainer.opacity(0.9), in: Circle())
                            .padding(8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let rubric {
                        AntTag(text: rubric.title, palette: Ant.palette(forRubric: rubric.id), bordered: false)
                            .padding(8)
                    }
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ant.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 10) {
                    if recipe.cookMinutes > 0 {
                        Label("\(recipe.cookMinutes) мин", systemImage: "clock")
                    }
                    if let kcalPerServing {
                        Label("\(Int(kcalPerServing.rounded())) ккал", systemImage: "flame")
                    }
                }
                .font(.caption)
                .foregroundStyle(Ant.textTertiary)
                .labelStyle(CompactLabelStyle())
            }
            .padding(Ant.paddingSM)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Ant.bgContainer)
        .clipShape(RoundedRectangle(cornerRadius: Ant.radiusLG, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Ant.radiusLG, style: .continuous).strokeBorder(Ant.borderSecondary))
        .antShadow()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// КБЖУ как Ant Statistic: числа «добегают» (CountUp), под ними — доли БЖУ (Progress).
struct NutritionBlock: View {
    let summary: NutritionSummary
    let servings: Int

    var body: some View {
        let portion = summary.perServing(servings)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                statistic("ккал", portion.kcal, palette: Ant.orange)
                statistic("белки, г", portion.protein, palette: Ant.red)
                statistic("жиры, г", portion.fat, palette: Ant.gold)
                statistic("углев., г", portion.carbs, palette: Ant.blue)
            }
            macroBar(portion)
            Text("На порцию (всего порций: \(servings))")
                .font(.caption).foregroundStyle(Ant.textTertiary)
            Text("Всё блюдо: \(summary.total.shortText)")
                .font(.footnote).foregroundStyle(Ant.textSecondary)
            if let per100 = summary.per100g {
                Text("На 100 г: \(per100.shortText)")
                    .font(.footnote).foregroundStyle(Ant.textSecondary)
            }
            if !summary.missing.isEmpty {
                Text("Без учёта: \(summary.missing.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(Ant.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func statistic(_ title: String, _ value: Double, palette: Ant.Palette) -> some View {
        VStack(spacing: 2) {
            CountUpText(value: value, font: .title3.weight(.semibold))
                .foregroundStyle(palette.text)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Ant.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(palette.bg, in: RoundedRectangle(cornerRadius: Ant.radiusLG, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Ant.radiusLG, style: .continuous).strokeBorder(palette.border, lineWidth: 0.75))
    }

    /// Доли калорий из белков, жиров и углеводов (4/9/4 ккал на грамм).
    @ViewBuilder
    private func macroBar(_ n: Nutrition) -> some View {
        let parts: [(Double, Color, String)] = [(n.protein * 4, Ant.red.base, "Б"), (n.fat * 9, Ant.gold.base, "Ж"),
                                                (n.carbs * 4, Ant.blue.base, "У")]
        let total = parts.reduce(0) { $0 + $1.0 }
        if total > 0 {
            VStack(alignment: .leading, spacing: 6) {
                MacroBar(parts: parts.map { ($0.0 / total, $0.1) })
                    .frame(height: 8)
                HStack(spacing: 12) {
                    ForEach(parts, id: \.2) { part in
                        HStack(spacing: 4) {
                            Circle().fill(part.1).frame(width: 7, height: 7)
                            Text("\(part.2) \(Int((part.0 / total * 100).rounded()))%")
                        }
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Ant.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Сегментированная полоса Progress, которая «наполняется» при появлении.
private struct MacroBar: View {
    let parts: [(Double, Color)]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fill: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Capsule().fill(part.1)
                        .frame(width: max(0, (geo.size.width - 4) * part.0 * fill))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capsule().fill(Ant.fill))
        }
        .onAppear {
            if reduceMotion { fill = 1 } else { withAnimation(.easeOut(duration: 0.9).delay(0.1)) { fill = 1 } }
        }
    }
}

/// Заголовок раздела на главной.
struct SectionTitle: View {
    let title: String
    var body: some View {
        AntSectionHeader(title: title)
    }
}
