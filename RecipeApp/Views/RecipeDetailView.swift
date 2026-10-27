import PhotosUI
import SwiftData
import SwiftUI

struct RecipeDetailView: View {
    let recipe: Recipe

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var products: [Product]
    @AppStorage(PriceProviderFactory.serverURLKey) private var serverURL = ""

    @State private var isCreatingBuild = false
    @State private var confirmDelete = false
    @State private var social: RecipeSummaryDTO?
    @State private var photoItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var photoMessage: String?
    @State private var sparks = 0
    @State private var servingsChoice: Int?
    @State private var cooking = false
    @State private var publishing: Build?
    @AppStorage(DietProfile.allergensKey) private var allergens = ""
    @AppStorage(DietProfile.vegetarianKey) private var vegetarian = false

    private var servings: Int { servingsChoice ?? recipe.servings }
    private var warnings: [String] { DietProfile(stored: allergens, vegetarian: vegetarian).warnings(for: recipe) }
    /// Своя сборка пользователя для публикации рецепта (первая, не из сообщества).
    private var ownBuild: Build? {
        recipe.builds.filter { $0.authorName == nil }.sorted { $0.createdAt < $1.createdAt }.first
    }

    private var session: AuthSession { .shared }
    private var client: RecipeSocialClient? { RecipeSocialClient.fromSettings() }

    var body: some View {
        List {
            Section {
                photoHeader
                    .listRowInsets(EdgeInsets())
                photoActions
            }

            Section {
                BlurText(text: recipe.title, font: .title2.weight(.bold), delayPerWord: 0.06)
                    .foregroundStyle(Ant.text)
                if !recipe.summary.isEmpty {
                    Text(recipe.summary).foregroundStyle(Ant.textSecondary)
                }
                WrapLayout(spacing: 6, lineSpacing: 6) {
                    if let r = Rubric.named(recipe.rubric) {
                        AntTag(text: r.title, palette: Ant.palette(forRubric: r.id))
                    }
                    AntTag(text: "\(recipe.servings) порц.", palette: Ant.geekblue, systemImage: "person.2")
                    if recipe.cookMinutes > 0 {
                        AntTag(text: "\(recipe.cookMinutes) мин", palette: Ant.cyan, systemImage: "clock")
                    }
                    if let likes = social?.likes, likes > 0 {
                        AntTag(text: "\(likes)", palette: Ant.red, systemImage: "heart.fill")
                    }
                }
                if recipe.isUserCreated {
                    Label("Ваш рецепт", systemImage: "person.crop.circle")
                        .foregroundStyle(.secondary)
                }
                if !recipe.steps.isEmpty {
                    Button { cooking = true } label: {
                        Label("Начать готовить", systemImage: "flame")
                    }
                    .buttonStyle(AntButtonStyle(kind: .primary))
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                }
            }

            if !warnings.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Не подходит по вашему профилю", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Ant.orange.text)
                        ForEach(warnings, id: \.self) { w in
                            Text("• " + w).font(.footnote).foregroundStyle(Ant.text)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Ant.orange.bg)
                }
            }

            Section {
                NutritionBlock(summary: NutritionCalculator.recipeSummary(recipe, products: products),
                               servings: recipe.servings)
            } header: {
                Text("КБЖУ")
            } footer: {
                Text("Ориентировочно, по типичным продуктам. Точные цифры — в вашей сборке с выбранными продуктами.")
            }

            Section("Ингредиенты") {
                Stepper(value: Binding(get: { servings }, set: { servingsChoice = $0 }), in: 1...30) {
                    HStack {
                        Text("Порций: \(servings)").font(.body.weight(.medium))
                        if servings != recipe.servings {
                            AntTag(text: "в рецепте \(recipe.servings)", palette: Ant.geekblue)
                        }
                    }
                }
                .accessibilityIdentifier("servings-stepper")
                ForEach(recipe.sortedIngredients) { ingredient in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ingredient.title)
                            if let p = NutritionCalculator.typicalProduct(for: ingredient, in: products),
                               let n = NutritionCalculator.nutrition(of: p, amount: ingredient.scaledAmount(servings: servings),
                                                                     unit: ingredient.unit) {
                                Text("≈ \(Int(n.kcal.rounded())) ккал · Б \(Int(n.protein.rounded())) · Ж \(Int(n.fat.rounded())) · У \(Int(n.carbs.rounded()))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(ingredient.amountText(servings: servings))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: servings)
                    }
                }
                AddToShoppingListButton { ShoppingList.entries(for: recipe, servings: servings) }
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
                    Label("Собрать продукты", systemImage: "cart.badge.plus")
                }
                .buttonStyle(AntButtonStyle(kind: .primary))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            } header: {
                Text("Мои сборки")
            } footer: {
                if !recipe.builds.isEmpty {
                    Text("Откройте сборку, чтобы изменить её, сохранить новый вариант или поделиться.")
                }
            }

            if recipe.isUserCreated {
                Section {
                    if let build = ownBuild {
                        if build.isPublished {
                            Label("Рецепт опубликован в сообществе", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Ant.success)
                        }
                        Button { publishing = build } label: {
                            Label(build.isPublished ? "Обновить публикацию" : "Опубликовать рецепт",
                                  systemImage: "globe")
                        }
                    } else {
                        Text("Соберите продукты — рецепт публикуется вместе с вашим набором.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Поделиться рецептом")
                } footer: {
                    Text("Рецепт появится в «Сообществе» → «Рецепты». Другие смогут сохранить его, собрать свои продукты и оценить. Фото к шагам остаются на вашем телефоне.")
                }
            }

            CommunityBuildsSection(recipeId: recipe.id)

            if !recipe.steps.isEmpty {
                Section("Приготовление") {
                    AntSteps(steps: recipe.steps, recipeId: recipe.isUserCreated ? recipe.id : nil)
                        .padding(.vertical, 6)
                }
            }

            if recipe.isUserCreated {
                Section {
                    Button("Удалить рецепт", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Ant.bgLayout)
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: ShareText.recipe(recipe, products: products),
                          subject: Text(recipe.title),
                          preview: SharePreview(recipe.title, image: ShareText.previewImage(for: recipe))) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Поделиться рецептом")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        Favorites.toggle(recipe, context: context)
                    }
                    if recipe.isFavorite { sparks += 1 }
                } label: {
                    Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(recipe.isFavorite ? Ant.red.base : Ant.primary)
                        .symbolEffect(.bounce, value: recipe.isFavorite)
                        .clickSpark(trigger: sparks)
                }
                .accessibilityLabel(recipe.isFavorite ? "Убрать из избранного" : "В избранное")
            }
        }
        .sheet(isPresented: $isCreatingBuild) {
            BuildEditorView(recipe: recipe, servings: servings)
        }
        .sheet(item: $publishing) { build in
            PublishBuildView(build: build) { _ in }
        }
        .fullScreenCover(isPresented: $cooking) {
            CookingModeView(recipe: recipe, servings: servings)
        }
        .confirmationDialog("Удалить рецепт и все его сборки?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                StepPhotoStore.deleteAll(recipeId: recipe.id)
                context.delete(recipe)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("Опубликованные сборки останутся в сообществе, пока вы не снимете их с публикации.")
        }
        .task(id: serverURL) { await loadSocial() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    // MARK: - Фото

    @ViewBuilder
    private var photoHeader: some View {
        let photos = social?.photos ?? []
        if photos.isEmpty {
            RecipeImage(url: nil, rubric: recipe.rubric, icon: recipe.icon)
                .frame(height: 220)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if client != nil {
                        Text("Пока нет фото — добавьте первое")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.white.opacity(0.75), in: Capsule())
                            .padding(12)
                    }
                }
        } else {
            TabView {
                ForEach(photos.reversed()) { photo in
                    RecipeImage(url: client?.url(photo.url), rubric: recipe.rubric, icon: recipe.icon)
                        .frame(height: 260)
                        .clipped()
                        .overlay(alignment: .bottomLeading) {
                            Text("Фото: \(photo.authorName)")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.black.opacity(0.35), in: Capsule())
                                .padding(10)
                        }
                        .contextMenu { photoMenu(photo) }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .frame(height: 260)
        }
    }

    @ViewBuilder
    private func photoMenu(_ photo: PhotoDTO) -> some View {
        if photo.authorId == session.user?.id {
            Button("Удалить фото", systemImage: "trash", role: .destructive) {
                Task {
                    try? await client?.deletePhoto(photo.id)
                    await loadSocial()
                }
            }
        } else if session.isLoggedIn {
            Button("Пожаловаться", systemImage: "exclamationmark.bubble") {
                Task {
                    try? await client?.reportPhoto(photo.id, reason: "Неподходящее фото")
                    photoMessage = "Жалоба отправлена. Спасибо!"
                }
            }
        }
    }

    @ViewBuilder
    private var photoActions: some View {
        if client != nil {
            if !session.isLoggedIn {
                LoginRequiredButton(title: "Войдите, чтобы добавить фото блюда")
            } else if !(session.user?.isEmailVerified ?? false) {
                VerifyEmailPrompt()
            } else {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack {
                        Label(isUploading ? "Загружаем фото…" : "Добавить фото блюда", systemImage: "camera")
                        if isUploading { Spacer(); ProgressView() }
                    }
                }
                .disabled(isUploading)
            }
            if let photoMessage {
                Text(photoMessage).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func loadSocial() async {
        guard let client else { social = nil; return }
        social = try? await client.summary(recipeId: recipe.id)
    }

    private func upload(_ item: PhotosPickerItem) async {
        guard let client else { return }
        isUploading = true
        photoMessage = nil
        defer {
            isUploading = false
            photoItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let jpeg = PhotoPreparation.jpeg(from: data) else {
                photoMessage = "Не удалось прочитать фото"
                return
            }
            _ = try await client.upload(jpeg: jpeg, recipeId: recipe.id)
            photoMessage = "Фото добавлено"
            await loadSocial()
        } catch {
            photoMessage = error.localizedDescription
        }
    }
}
