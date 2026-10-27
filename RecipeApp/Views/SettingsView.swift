import SwiftUI

struct SettingsView: View {
    @AppStorage(PriceProviderFactory.serverURLKey) private var serverURL = ""
    @AppStorage("cityId") private var cityId = "msk"
    @Environment(\.dismiss) private var dismiss

    @State private var cities: [City] = []
    @State private var checkResult: String?

    var body: some View {
        NavigationStack {
            Form {
                AccountSection()

                Section {
                    Picker("Город", selection: $cityId) {
                        ForEach(cities) { Text($0.name).tag($0.id) }
                    }
                } footer: {
                    Text("Список магазинов с доставкой зависит от города.")
                }

                Section {
                    TextField("http://192.168.1.10:8000", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Проверить соединение") { Task { await check() } }
                        .disabled(serverURL.isEmpty)
                    if let checkResult {
                        Text(checkResult).font(.footnote)
                    }
                } header: {
                    Text("Сервер")
                } footer: {
                    Text("Нужен для цен в магазинах и сообщества. Оставьте пустым — будут тестовые цены, сообщество недоступно.")
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
            .task(id: serverURL) {
                cities = (try? await PriceProviderFactory.make(serverURL: serverURL).cities()) ?? []
            }
        }
    }

    private func check() async {
        checkResult = "Проверяю…"
        guard let base = URL(string: serverURL.trimmingCharacters(in: .whitespaces)) else {
            checkResult = "Некорректный адрес"
            return
        }
        do {
            let (_, response) = try await URLSession.shared.data(from: base.appendingPathComponent("health"))
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            checkResult = ok ? "✅ Сервер доступен" : "Сервер ответил с ошибкой"
        } catch {
            checkResult = "Нет соединения: \(error.localizedDescription)"
        }
    }
}

/// Аккаунт: вход, имя, выход, удаление.
struct AccountSection: View {
    private var session: AuthSession { .shared }
    @State private var showAuth = false
    @State private var name = ""
    @State private var confirmDelete = false
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        Section {
            if let user = session.user {
                HStack {
                    TextField("Имя или ник", text: $name)
                        .onSubmit { Task { await saveName() } }
                    if name.trimmed != user.displayName && !name.trimmed.isEmpty {
                        Button("Сохранить") { Task { await saveName() } }
                    }
                }
                if let email = user.email {
                    LabeledContent("Email", value: email)
                    if !user.isEmailVerified {
                        NavigationLink {
                            VerifyEmailView()
                        } label: {
                            Label("Подтвердить email", systemImage: "envelope.badge")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                if user.hasPassword {
                    NavigationLink("Сменить пароль") { ChangePasswordView() }
                }
                Toggle("Напоминания о ценах", isOn: Binding(
                    get: { user.priceAlertsOn },
                    set: { on in Task { try? await session.update(priceAlerts: on) } }))
                if user.hasApple {
                    Label("Вход через Apple", systemImage: "apple.logo").foregroundStyle(.secondary)
                }
                Button("Выйти") { Task { await session.logout() } }
                Button("Удалить аккаунт", role: .destructive) { confirmDelete = true }
                    .confirmationDialog("Удалить аккаунт?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Удалить навсегда", role: .destructive) { Task { await delete() } }
                    } message: {
                        Text("Будут удалены аккаунт, опубликованные сборки, оценки и уведомления. Рецепты и сборки на этом телефоне останутся.")
                    }
            } else {
                Button {
                    showAuth = true
                } label: {
                    Label("Войти или зарегистрироваться", systemImage: "person.crop.circle")
                }
                .sheet(isPresented: $showAuth) { AuthView() }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            // Модификаторы вешаем на один вид, а не на Section: иначе SwiftUI размножает их
            // на каждую строку, заголовок и подпись, и окна начинают конфликтовать.
            Text("Аккаунт")
                .onAppear { name = session.user?.displayName ?? "" }
                .onChange(of: session.user) { _, user in name = user?.displayName ?? "" }
        } footer: {
            if session.isLoggedIn {
                Text("Под этим именем публикуются ваши сборки и отзывы. Напоминания о ценах приходят не чаще раза в день.")
            } else {
                Text("Нужен, чтобы делиться сборками, ставить оценки и получать уведомления.")
            }
        }
        .disabled(isWorking)
    }

    private func saveName() async {
        guard !name.trimmed.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.update(displayName: name.trimmed)
            message = "Имя сохранено"
        } catch {
            message = error.localizedDescription
        }
    }

    private func delete() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.deleteAccount()
            message = "Аккаунт удалён"
        } catch {
            message = error.localizedDescription
        }
    }
}
