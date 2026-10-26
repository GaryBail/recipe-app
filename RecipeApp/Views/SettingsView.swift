import SwiftUI

struct SettingsView: View {
    @AppStorage(PriceProviderFactory.serverURLKey) private var serverURL = ""
    @AppStorage("cityId") private var cityId = "msk"
    @AppStorage(UserIdentity.nameKey) private var displayName = ""
    @Environment(\.dismiss) private var dismiss

    @State private var cities: [City] = []
    @State private var checkResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Имя или ник", text: $displayName)
                } header: {
                    Text("Профиль")
                } footer: {
                    Text("Под этим именем публикуются ваши сборки и отзывы.")
                }

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
