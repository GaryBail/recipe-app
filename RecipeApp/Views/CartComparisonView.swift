import SwiftUI

/// Сравнение корзины по магазинам выбранного города и переход в магазин.
struct CartComparisonView: View {
    let lines: [CartLine]
    /// Для превью/тестов; по умолчанию источник выбирается по настройкам.
    var providerOverride: (any PriceProvider)? = nil

    @AppStorage("cityId") private var cityId = AppConfig.defaultCityId
    @AppStorage(PriceProviderFactory.serverURLKey) private var serverURL = ""

    private var provider: any PriceProvider {
        providerOverride ?? PriceProviderFactory.current()
    }
    @Environment(\.openURL) private var openURL

    @State private var cities: [City] = []
    @State private var quotes: [CartQuote] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var prompt: LaunchPrompt?
    @State private var preparing: String?

    var body: some View {
        List {
            Section {
                Picker("Город", selection: $cityId) {
                    ForEach(cities) { Text($0.name).tag($0.id) }
                }
            }

            Section {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let errorText {
                    Text(errorText).foregroundStyle(.red)
                } else if quotes.isEmpty {
                    Text("Нет магазинов с доставкой").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(quotes.enumerated()), id: \.element.id) { index, quote in
                        Button { Task { await choose(quote) } } label: {
                            QuoteRow(quote: quote, isBest: index == 0 && quote.isComplete,
                                     transfersCart: CartTransfer.stores.contains(quote.store.id))
                        }
                        .buttonStyle(.plain)
                        .disabled(preparing != nil)
                        .overlay(alignment: .trailing) {
                            if preparing == quote.id { ProgressView().padding(.trailing, 4) }
                        }
                    }
                }
            } header: {
                Text("Магазины")
            } footer: {
                Text("Цены на момент проверки. Перед оплатой сверьте их в магазине. Во ВкусВилл корзина передаётся целиком, для остальных магазинов копируем список покупок.")
            }
        }
        .navigationTitle("Где дешевле")
        .task(id: serverURL) { await loadCities() }
        .task(id: "\(cityId)|\(serverURL)") { await loadQuotes() }
        .alert(prompt?.title ?? "",
               isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
               presenting: prompt) { p in
            Button(p.actionTitle) {
                if let list = p.shoppingList { UIPasteboard.general.string = list }
                openURL(p.url)
            }
            Button("Отмена", role: .cancel) {}
        } message: { p in
            Text(p.message)
        }
    }

    private func loadCities() async {
        cities = (try? await provider.cities()) ?? []
    }

    private func loadQuotes() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        let all = (try? await provider.cities()) ?? cities
        guard let city = all.first(where: { $0.id == cityId }) ?? all.first else {
            quotes = []
            return
        }
        do {
            quotes = try await CartComparisonService(provider: provider).compare(lines: lines, in: city)
        } catch is CancellationError {
            return
        } catch {
            errorText = "Не удалось получить цены: \(error.localizedDescription)"
        }
    }

    private func choose(_ quote: CartQuote) async {
        if CartTransfer.stores.contains(quote.store.id) {
            preparing = quote.id
            defer { preparing = nil }
            do {
                if let link = try await provider.cartLink(for: quote) {
                    prompt = LaunchPrompt(title: "Корзина \(quote.store.name) готова",
                                          message: "Откроем \(quote.store.name) с уже собранной корзиной (\(quote.lines.count) товаров). Останется проверить и оформить заказ.",
                                          actionTitle: "Открыть корзину", url: link, shoppingList: nil)
                    return
                }
            } catch {
                errorText = "Не удалось собрать корзину: \(error.localizedDescription)"
            }
        }
        let deepLink = provider.cartDeepLink(for: quote)
        let list = deepLink == nil ? StoreLauncher.shoppingList(for: quote) : nil
        let listNote = list == nil ? "" : "\n\nСписок покупок будет скопирован — вставьте его в поиск магазина."

        switch StoreLauncher.destination(for: quote.store, cartDeepLink: deepLink) {
        case .app(let url):
            prompt = LaunchPrompt(title: "Открыть \(quote.store.name)?",
                                  message: "Перейдём в приложение магазина." + listNote,
                                  actionTitle: "Открыть", url: url, shoppingList: list)
        case .appStore(let url):
            prompt = LaunchPrompt(title: "Нужно приложение \(quote.store.name)",
                                  message: "Приложение магазина не установлено. Скачать его в App Store?",
                                  actionTitle: "Скачать", url: url, shoppingList: nil)
        case .web(let url):
            prompt = LaunchPrompt(title: "Открыть сайт \(quote.store.name)?",
                                  message: "Приложение магазина не установлено, откроем сайт." + listNote,
                                  actionTitle: "Открыть сайт", url: url, shoppingList: list)
        case .unavailable:
            errorText = "Для магазина \(quote.store.name) нет ссылки для перехода."
        }
    }
}

struct LaunchPrompt {
    let title: String
    let message: String
    let actionTitle: String
    let url: URL
    let shoppingList: String?
}

private struct QuoteRow: View {
    let quote: CartQuote
    let isBest: Bool
    var transfersCart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(quote.store.name).font(.headline)
                if isBest {
                    Text("Выгоднее всего")
                        .font(.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.green.opacity(0.2), in: Capsule())
                }
                if transfersCart {
                    AntTag(text: "корзина целиком", palette: Ant.green, systemImage: "cart.fill")
                }
                Spacer()
                Text(quote.total, format: .currency(code: "RUB").precision(.fractionLength(0)))
                    .font(.headline)
            }
            if let note = quote.store.deliveryNote {
                Text("Товары \(quote.itemsTotal.formatted(.currency(code: "RUB").precision(.fractionLength(0)))) · \(note.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Товары \(quote.itemsTotal.formatted(.currency(code: "RUB").precision(.fractionLength(0)))) · доставка \(quote.deliveryFee.formatted(.currency(code: "RUB").precision(.fractionLength(0))))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(quote.lines, id: \.line.productId) { item in
                if let title = item.offer.title {
                    Text("• \(title)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if !quote.missing.isEmpty {
                Text("Нет в наличии: " + quote.missing.map(\.title).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if quote.minOrderShortfall > 0 {
                Text("До минимального заказа не хватает \(quote.minOrderShortfall.formatted(.currency(code: "RUB").precision(.fractionLength(0))))")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
