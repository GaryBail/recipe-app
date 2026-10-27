import SwiftUI
import SwiftData

/// Блок «Сборки сообщества» на экране рецепта: лучшая сборка выделена как рекомендация.
struct CommunityBuildsSection: View {
    let recipeId: String

    @AppStorage(PriceProviderFactory.serverURLKey) private var serverURL = ""
    @State private var builds: [CommunityBuildDTO] = []
    @State private var state: LoadState = .idle

    enum LoadState: Equatable { case idle, loading, failed(String), loaded }

    var body: some View {
        Section {
            if CommunityClient.fromSettings() == nil {
                Text("Укажите адрес сервера в настройках, чтобы видеть сборки других пользователей.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                switch state {
                case .idle, .loading:
                    HStack { Spacer(); ProgressView(); Spacer() }
                case .failed(let message):
                    Text(message).font(.footnote).foregroundStyle(.red)
                case .loaded where builds.isEmpty:
                    Text("Пока никто не поделился сборкой для этого рецепта.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .loaded:
                    ForEach(Array(builds.prefix(5).enumerated()), id: \.element.id) { index, dto in
                        NavigationLink {
                            CommunityBuildDetailView(initial: dto)
                        } label: {
                            CommunityBuildRow(build: dto, isRecommended: index == 0 && dto.ratingCount > 0)
                        }
                    }
                    if builds.count > 5 {
                        NavigationLink("Все сборки (\(builds.count))") {
                            CommunityFeedView(recipeId: recipeId)
                        }
                    }
                }
            }
        } header: {
            Text("Сборки сообщества")
        }
        .task(id: serverURL) { await load() }
    }

    private func load() async {
        guard let client = CommunityClient.fromSettings() else { return }
        state = .loading
        do {
            builds = try await client.builds(recipeId: recipeId, sort: .top)
            state = .loaded
        } catch {
            state = .failed("Не удалось загрузить: \(error.localizedDescription)")
        }
    }
}

struct CommunityBuildRow: View {
    let build: CommunityBuildDTO
    var isRecommended = false
    var showRecipe = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(build.name).font(.headline)
                if isRecommended {
                    Text("Рекомендуем")
                        .font(.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.green.opacity(0.2), in: Capsule())
                }
            }
            if showRecipe {
                Text(build.recipe.title).font(.subheadline)
            }
            HStack(spacing: 6) {
                StarsView(value: build.ratingAvg ?? 0)
                Text(ratingSummary(avg: build.ratingAvg, count: build.ratingCount))
                Text("· \(build.authorName)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(build.items.map(\.product.name).joined(separator: ", "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

/// Лента сборок: все рецепты или один, лучшие или новые.
struct CommunityFeedView: View {
    var recipeId: String? = nil

    @State private var sort: CommunityClient.Sort = .top
    @State private var builds: [CommunityBuildDTO] = []
    @State private var errorText: String?
    @State private var isLoading = false

    var body: some View {
        List {
            Section {
                Picker("Сортировка", selection: $sort) {
                    ForEach(CommunityClient.Sort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                if CommunityClient.fromSettings() == nil {
                    Text("Укажите адрес сервера в настройках.").foregroundStyle(.secondary)
                } else if let errorText {
                    Text(errorText).foregroundStyle(.red)
                } else if isLoading && builds.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if builds.isEmpty {
                    Text("Пока пусто — поделитесь своей сборкой первым.").foregroundStyle(.secondary)
                }
                ForEach(builds) { dto in
                    NavigationLink {
                        CommunityBuildDetailView(initial: dto)
                    } label: {
                        CommunityBuildRow(build: dto, showRecipe: recipeId == nil)
                    }
                }
            }
        }
        .navigationTitle("Сообщество")
        .refreshable { await load() }
        .task(id: sort) { await load() }
    }

    private func load() async {
        guard let client = CommunityClient.fromSettings() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            builds = try await client.builds(recipeId: recipeId, sort: sort)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Чужая (или своя опубликованная) сборка: продукты, оценки, действия.
struct CommunityBuildDetailView: View {
    let initial: CommunityBuildDTO

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var build: CommunityBuildDTO?
    @State private var ratings: [CommunityRatingDTO] = []
    @State private var stars = 0
    @State private var comment = ""
    @State private var message: String?
    @State private var isWorking = false
    @State private var showReport = false
    @State private var confirmBlock = false
    @State private var savedBuild: Build?

    private var current: CommunityBuildDTO { build ?? initial }
    private var isMine: Bool { current.authorId == AuthSession.shared.user?.id }
    private var isLoggedIn: Bool { AuthSession.shared.isLoggedIn }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(current.recipe.title).font(.headline)
                    HStack(spacing: 6) {
                        StarsView(value: current.ratingAvg ?? 0)
                        Text(ratingSummary(avg: current.ratingAvg, count: current.ratingCount))
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Text("Автор: \(current.authorName)").font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Продукты") {
                ForEach(current.recipe.ingredients, id: \.id) { ingredient in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.product(forIngredient: ingredient.id)?.displayName ?? "—")
                        Text("\(ingredient.title), \(ingredient.amount.formatted()) \((MeasureUnit(rawValue: ingredient.unit) ?? .pieces).short)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                NavigationLink {
                    CartComparisonView(lines: current.cartLines)
                } label: {
                    Label("Где купить дешевле", systemImage: "cart")
                }
                if let savedBuild {
                    NavigationLink(value: savedBuild) {
                        Label("Открыть сохранённую копию", systemImage: "checkmark.circle")
                    }
                } else if !isMine {
                    Button { save() } label: {
                        Label("Сохранить себе", systemImage: "square.and.arrow.down")
                    }
                }
            } footer: {
                if !isMine && savedBuild == nil {
                    Text("Копию можно изменить и сохранить как свой вариант.")
                }
            }

            if !current.recipe.steps.isEmpty {
                Section("Приготовление") {
                    ForEach(Array(current.recipe.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top) {
                            Text("\(index + 1).").bold()
                            Text(step)
                        }
                    }
                }
            }

            if !isMine && !isLoggedIn {
                Section("Ваша оценка") {
                    LoginRequiredButton(title: "Войдите, чтобы оценить сборку")
                }
            } else if !isMine && !(AuthSession.shared.user?.isEmailVerified ?? false) {
                Section("Ваша оценка") {
                    VerifyEmailPrompt()
                }
            } else if !isMine {
                Section("Ваша оценка") {
                    StarPicker(stars: $stars)
                    TextField("Комментарий (необязательно)", text: $comment, axis: .vertical)
                        .lineLimit(1...4)
                    Button(current.myRating == nil ? "Оценить" : "Обновить оценку") {
                        Task { await rate() }
                    }
                    .disabled(stars == 0 || isWorking)
                }
            }

            if !ratings.isEmpty {
                Section("Отзывы") {
                    ForEach(ratings, id: \.userId) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                StarsView(value: Double(r.stars))
                                Text(r.authorName).font(.caption).foregroundStyle(.secondary)
                            }
                            if let c = r.comment, !c.isEmpty { Text(c).font(.subheadline) }
                        }
                    }
                }
            }

            if let message {
                Section { Text(message).font(.footnote) }
            }

            if isMine {
                Section {
                    Button("Удалить публикацию", role: .destructive) { Task { await deleteOwn() } }
                }
            } else if isLoggedIn {
                Section {
                    Button("Пожаловаться", role: .destructive) { showReport = true }
                    Button("Скрыть все сборки автора", role: .destructive) { confirmBlock = true }
                }
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isWorking)
        .task { await load() }
        .confirmationDialog("Причина жалобы", isPresented: $showReport, titleVisibility: .visible) {
            ForEach(["Оскорбительный контент", "Спам или реклама", "Опасный или вредный рецепт", "Другое"], id: \.self) { reason in
                Button(reason) { Task { await report(reason) } }
            }
        }
        .confirmationDialog("Скрыть все сборки \(current.authorName)?", isPresented: $confirmBlock,
                            titleVisibility: .visible) {
            Button("Скрыть", role: .destructive) { Task { await block() } }
        }
    }

    private func load() async {
        guard let client = CommunityClient.fromSettings() else { return }
        if let fresh = try? await client.build(id: initial.id) {
            build = fresh
            stars = fresh.myRating ?? 0
        }
        ratings = (try? await client.ratings(buildId: initial.id)) ?? []
        if let mine = ratings.first(where: { $0.userId == AuthSession.shared.user?.id }) {
            comment = mine.comment ?? ""
        }
    }

    private func rate() async {
        guard let client = CommunityClient.fromSettings() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            build = try await client.rate(buildId: current.id, stars: stars,
                                         comment: comment.trimmed.isEmpty ? nil : comment.trimmed)
            ratings = (try? await client.ratings(buildId: current.id)) ?? ratings
            message = "Спасибо за оценку!"
        } catch {
            message = error.localizedDescription
        }
    }

    private func save() {
        do {
            savedBuild = try CommunityMapper.importBuild(current, into: context)
            message = "Сборка сохранена в рецепт «\(current.recipe.title)»."
        } catch {
            message = "Не удалось сохранить: \(error.localizedDescription)"
        }
    }

    private func report(_ reason: String) async {
        guard let client = CommunityClient.fromSettings() else { return }
        do {
            try await client.report(buildId: current.id, reason: reason)
            message = "Жалоба отправлена. Спасибо!"
        } catch {
            message = error.localizedDescription
        }
    }

    private func block() async {
        guard let client = CommunityClient.fromSettings() else { return }
        do {
            try await client.block(userId: current.authorId)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    private func deleteOwn() async {
        guard let client = CommunityClient.fromSettings() else { return }
        do {
            try await client.delete(id: current.id)
            // Снимаем отметку о публикации с локальной сборки, если она есть.
            let id: String? = current.id
            if let local = try? context.fetch(FetchDescriptor<Build>(predicate: #Predicate { $0.remoteId == id })).first {
                local.isPublished = false
                local.remoteId = nil
                try? context.save()
            }
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Открывает сборку по id (из уведомления или push).
struct CommunityBuildLoader: View {
    let buildId: String
    @State private var dto: CommunityBuildDTO?
    @State private var errorText: String?

    var body: some View {
        Group {
            if let dto {
                CommunityBuildDetailView(initial: dto)
            } else if let errorText {
                ContentUnavailableView("Сборка недоступна", systemImage: "exclamationmark.triangle",
                                       description: Text(errorText))
            } else {
                ProgressView()
            }
        }
        .task(id: buildId) {
            guard let client = CommunityClient.fromSettings() else {
                errorText = "Укажите адрес сервера в настройках."
                return
            }
            do {
                dto = try await client.build(id: buildId)
            } catch {
                errorText = "Возможно, автор удалил её. \(error.localizedDescription)"
            }
        }
    }
}
