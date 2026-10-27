import SwiftUI
import SwiftData

struct BuildDetailView: View {
    let build: Build

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var editorMode: BuildEditorView.Mode?
    @State private var showPublish = false
    @State private var remote: CommunityBuildDTO?
    @State private var errorText: String?
    @State private var isWorking = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            if let author = build.authorName {
                Section {
                    Label("Сохранено из сообщества, автор: \(author)", systemImage: "person.2")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let recipe = build.recipe {
                Section("Продукты") {
                    Stepper(value: Binding(get: { build.effectiveServings },
                                           set: { build.servings = $0 == recipe.servings ? nil : $0
                                                  try? context.save()
                                                  PriceWatchClient.resyncIfWatched(build) }),
                            in: 1...30) {
                        Text("Порций: \(build.effectiveServings)").font(.body.weight(.medium))
                    }
                    ForEach(recipe.sortedIngredients) { ingredient in
                        let product = build.product(for: ingredient)
                        let amount = ingredient.scaledAmount(servings: build.effectiveServings)
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product?.displayName ?? "—")
                                Text("\(ingredient.title), \(ingredient.unit.format(amount))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let product,
                               let n = NutritionCalculator.nutrition(of: product, amount: amount, unit: ingredient.unit) {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(Int(n.kcal.rounded())) ккал").font(.footnote.monospacedDigit())
                                    Text("Б \(Int(n.protein.rounded())) · Ж \(Int(n.fat.rounded())) · У \(Int(n.carbs.rounded()))")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    NutritionBlock(summary: NutritionCalculator.buildSummary(build), servings: recipe.servings)
                } header: {
                    Text("КБЖУ вашей сборки")
                } footer: {
                    Text("Ориентировочно, по справочным значениям выбранных продуктов (сырой вес). У конкретных марок цифры отличаются.")
                }
            }

            Section {
                NavigationLink {
                    CartComparisonView(lines: build.cartLines())
                } label: {
                    Label("Где купить дешевле", systemImage: "cart")
                }
                AddToShoppingListButton { ShoppingList.entries(for: build) }
                ShareLink(item: ShareText.build(build), subject: Text(build.name)) {
                    Label("Отправить список покупок", systemImage: "paperplane")
                }
                Button {
                    editorMode = .variant(of: build)
                } label: {
                    Label("Сохранить как новый вариант", systemImage: "square.on.square")
                }
                Button {
                    editorMode = .edit(build)
                } label: {
                    Label("Изменить", systemImage: "pencil")
                }
            }

            PriceWatchSection(build: build)

            Section {
                if build.isPublished {
                    if let remote {
                        HStack {
                            StarsView(value: remote.ratingAvg ?? 0)
                            Text(ratingSummary(avg: remote.ratingAvg, count: remote.ratingCount, empty: "Пока нет оценок"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button { showPublish = true } label: {
                        Label("Опубликовать заново", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) { Task { await unpublish() } } label: {
                        Label("Снять с публикации", systemImage: "eye.slash")
                    }
                } else {
                    Button { showPublish = true } label: {
                        Label("Поделиться в сообществе", systemImage: "square.and.arrow.up")
                    }
                }
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Сообщество")
            } footer: {
                if !build.isPublished {
                    Text("Другие пользователи увидят рецепт и ваш набор продуктов и смогут его оценить.")
                }
            }
            .disabled(isWorking)

            Section {
                Button("Удалить сборку", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(build.name)
        .sheet(isPresented: Binding(get: { editorMode != nil }, set: { if !$0 { editorMode = nil } })) {
            if let recipe = build.recipe, let mode = editorMode {
                BuildEditorView(recipe: recipe, mode: mode)
            }
        }
        .sheet(isPresented: $showPublish) {
            PublishBuildView(build: build) { dto in remote = dto }
        }
        .confirmationDialog("Удалить сборку?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await deleteBuild() } }
        } message: {
            if build.isPublished { Text("Публикация в сообществе тоже будет удалена.") }
        }
        .task(id: build.remoteId) { await loadRemote() }
    }

    private func loadRemote() async {
        guard let id = build.remoteId, let client = CommunityClient.fromSettings() else { return }
        remote = try? await client.build(id: id)
    }

    private func unpublish() async {
        guard let id = build.remoteId else { return }
        guard let client = CommunityClient.fromSettings() else {
            errorText = "Укажите адрес сервера в настройках"
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.delete(id: id)
            build.isPublished = false
            build.remoteId = nil
            remote = nil
            try? context.save()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func deleteBuild() async {
        if build.isPublished, let id = build.remoteId, let client = CommunityClient.fromSettings() {
            try? await client.delete(id: id)
        }
        if build.isWatched, let watches = PriceWatchClient.fromSettings() {
            try? await watches.delete(id: build.id.uuidString)
        }
        context.delete(build)
        try? context.save()
        dismiss()
    }
}

/// Публикация сборки. Автор — текущий аккаунт.
struct PublishBuildView: View {
    let build: Build
    var onPublished: (CommunityBuildDTO) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var isSending = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                if let user = AuthSession.shared.user {
                    Section {
                        LabeledContent("Автор", value: user.displayName)
                        if !user.isEmailVerified { VerifyEmailPrompt() }
                    } footer: {
                        Text("Имя можно изменить в настройках.")
                    }
                } else {
                    Section {
                        Text("Чтобы делиться сборками, войдите в аккаунт.").font(.footnote)
                        LoginRequiredButton(title: "Войти или зарегистрироваться")
                    }
                }
                Section("Название сборки") {
                    TextField(build.name, text: $name)
                }
                if build.recipe?.isUserCreated == true {
                    Section {
                        Text("Ваш рецепт будет опубликован вместе со сборкой.")
                            .font(.footnote)
                    }
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Публикация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Опубликовать") { Task { await publish() } }
                            .disabled(!(AuthSession.shared.user?.isEmailVerified ?? false))
                    }
                }
            }
            .onAppear { if name.isEmpty { name = build.name } }
        }
    }

    private func publish() async {
        guard let client = CommunityClient.fromSettings() else {
            errorText = "Укажите адрес сервера в настройках (⚙️ на главном экране)."
            return
        }
        if !name.trimmed.isEmpty { build.name = name.trimmed }
        guard let request = CommunityMapper.publishRequest(for: build) else {
            errorText = "В сборке нет выбранных продуктов."
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            // Повторная публикация заменяет старую версию.
            if let old = build.remoteId { try? await client.delete(id: old) }
            let dto = try await client.publish(request)
            build.isPublished = true
            build.remoteId = dto.id
            try? context.save()
            onPublished(dto)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Звёзды рейтинга (только отображение).
struct StarsView: View {
    let value: Double

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: Double(i) <= value.rounded() ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .accessibilityLabel(Text("Рейтинг \(String(format: "%.1f", value)) из 5"))
    }
}

/// Выбор оценки.
struct StarPicker: View {
    @Binding var stars: Int

    var body: some View {
        HStack {
            ForEach(1...5, id: \.self) { i in
                Button {
                    stars = i
                } label: {
                    Image(systemName: i <= stars ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(.yellow)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(i) из 5")
            }
        }
    }
}

/// "4.5 · 12 оценок"
func ratingSummary(avg: Double?, count: Int, empty: String = "нет оценок") -> String {
    guard count > 0 else { return empty }
    return "\(String(format: "%.1f", avg ?? 0)) · \(count) оценок"
}

/// «Следить за ценой»: сервер несколько раз в день пересчитывает корзину в магазинах Москвы.
struct PriceWatchSection: View {
    let build: Build

    @Environment(\.modelContext) private var context
    @AppStorage("cityId") private var cityId = "msk"
    @State private var watch: WatchDTO?
    @State private var errorText: String?
    @State private var isWorking = false

    private var session: AuthSession { .shared }

    var body: some View {
        Section {
            if !session.isLoggedIn {
                LoginRequiredButton(title: "Войдите, чтобы следить за ценой")
            } else {
                Toggle(isOn: Binding(get: { build.isWatched }, set: { on in Task { await setWatched(on) } })) {
                    Label("Следить за ценой", systemImage: "bell.badge")
                }
                .disabled(isWorking)

                if build.isWatched, let watch {
                    if let best = watch.best, let total = watch.bestTotal {
                        LabeledContent("Сейчас дешевле всего") {
                            Text("\(total.formatted(.currency(code: "RUB").precision(.fractionLength(0)))) · \(StoreNames.name(best.storeId))")
                        }
                        if let usual = watch.usual {
                            LabeledContent("Обычно", value: usual.formatted(.currency(code: "RUB").precision(.fractionLength(0))))
                        }
                    } else {
                        Text("Цены появятся после ближайшей проверки (7:00, 12:00 и 18:00 по Москве).")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let date = watch.checkedDate {
                        Text("Проверено \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Цена")
                .task(id: build.isWatched) { await load() }
        } footer: {
            if cityId != PriceWatchClient.supportedCity {
                Text("Пока цены проверяются только для Москвы (Пятёрочка и Перекрёсток).")
            } else {
                Text("Проверяем Пятёрочку и Перекрёсток в Москве. Напомним не чаще раза в день — когда корзина подешевеет или давно не заглядывали.")
            }
        }
    }

    private func load() async {
        guard build.isWatched, let client = PriceWatchClient.fromSettings() else { return }
        watch = try? await client.get(id: build.id.uuidString)
    }

    private func setWatched(_ on: Bool) async {
        guard let client = PriceWatchClient.fromSettings() else {
            errorText = "Укажите адрес сервера в настройках."
            return
        }
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            if on {
                guard let request = PriceWatchClient.request(for: build) else {
                    errorText = "В сборке нет продуктов."
                    return
                }
                watch = try await client.upsert(id: build.id.uuidString, request)
                let authorized = await PushRegistration.isAuthorized()
                if !authorized { await PushRegistration.requestAndRegister() }
            } else {
                try await client.delete(id: build.id.uuidString)
                watch = nil
            }
            build.isWatched = on
            try? context.save()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
