import SwiftData
import SwiftUI
import UIKit

/// Общий список покупок на несколько рецептов. Режим «в магазине» — крупные строки,
/// вычёркивание одним касанием, экран не гаснет.
struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShoppingItem.createdAt) private var items: [ShoppingItem]
    @AppStorage("shoppingStoreMode") private var storeMode = false
    @State private var confirmClear = false
    @State private var adding = ""

    private var open: [ShoppingItem] { items.filter { !$0.isChecked } }
    private var done: [ShoppingItem] { items.filter(\.isChecked) }

    private var groups: [(title: String, items: [ShoppingItem])] {
        Dictionary(grouping: open) { ShoppingList.department(for: $0.categoryId).order }
            .sorted { $0.key < $1.key }
            .map { group in
                (title: ShoppingList.department(for: group.value[0].categoryId).title,
                 items: group.value.sorted { $0.title.localizedCompare($1.title) == .orderedAscending })
            }
    }

    private var sources: [String] {
        Array(Set(open.flatMap(\.sources))).sorted()
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("Список пуст", systemImage: "cart")
                    } description: {
                        Text("Откройте рецепт или сборку и нажмите «В список покупок». Продукты из нескольких рецептов сложатся в один список.")
                    }
                } else {
                    list
                }
            }
            .navigationTitle(storeMode ? "В магазине" : "Покупки")
            .toolbar {
                if !items.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Toggle(isOn: $storeMode.animation(.snappy)) {
                            Label("В магазине", systemImage: "basket")
                        }
                        .toggleStyle(.button)
                        .accessibilityIdentifier("store-mode")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        ShareLink(item: ShoppingList.shareText(items)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Отправить список")
                        Menu {
                            Button("Удалить купленное", systemImage: "checkmark.circle") { removeDone() }
                                .disabled(done.isEmpty)
                            Button("Очистить список", systemImage: "trash", role: .destructive) { confirmClear = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Ещё")
                    }
                }
            }
            .confirmationDialog("Очистить весь список?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Очистить", role: .destructive) { clear() }
            }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = storeMode && !items.isEmpty }
            .onChange(of: storeMode) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }

    private var list: some View {
        List {
            if !storeMode {
                Section {
                    ProgressRow(done: done.count, total: items.count)
                    if !sources.isEmpty {
                        Text("Для: " + sources.joined(separator: ", "))
                            .font(.footnote)
                            .foregroundStyle(Ant.textSecondary)
                    }
                    HStack {
                        TextField("Добавить свой пункт", text: $adding)
                            .onSubmit(addCustom)
                        if !adding.trimmed.isEmpty {
                            Button("Добавить", action: addCustom)
                        }
                    }
                }
            } else {
                Section {
                    ProgressRow(done: done.count, total: items.count)
                }
            }

            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        ShoppingRow(item: item, large: storeMode) { toggle(item) }
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(group.items[i]) }
                        try? context.save()
                    }
                }
            }

            if !done.isEmpty {
                Section("Куплено") {
                    ForEach(done) { item in
                        ShoppingRow(item: item, large: storeMode) { toggle(item) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Ant.bgLayout)
    }

    private func toggle(_ item: ShoppingItem) {
        withAnimation(.snappy) { item.isChecked.toggle() }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        try? context.save()
    }

    private func addCustom() {
        let title = adding.trimmed
        guard !title.isEmpty else { return }
        context.insert(ShoppingItem(title: title, categoryId: "user-\(title.lowercased())", productId: nil,
                                    amount: 1, unit: .pieces, sources: []))
        try? context.save()
        adding = ""
    }

    private func removeDone() {
        for item in done { context.delete(item) }
        try? context.save()
    }

    private func clear() {
        for item in items { context.delete(item) }
        try? context.save()
        storeMode = false
    }
}

private struct ProgressRow: View {
    let done: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(done == total && total > 0 ? "Всё куплено 🎉" : "Куплено \(done) из \(total)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            ProgressView(value: total == 0 ? 0 : Double(done) / Double(total))
                .tint(done == total ? Ant.success : Ant.primary)
                .animation(.snappy, value: done)
        }
        .padding(.vertical, 2)
    }
}

private struct ShoppingRow: View {
    let item: ShoppingItem
    let large: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(large ? .title : .title3)
                    .foregroundStyle(item.isChecked ? Ant.success : Ant.border)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(large ? .title3.weight(.medium) : .body)
                        .strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? Ant.textTertiary : Ant.text)
                    if !large && !item.sources.isEmpty {
                        Text(item.sources.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(Ant.textTertiary)
                    }
                }
                Spacer()
                if !item.categoryId.hasPrefix("user-") || item.amount != 1 {
                    Text(item.amountText)
                        .font(large ? .title3.monospacedDigit() : .subheadline.monospacedDigit())
                        .foregroundStyle(item.isChecked ? Ant.textTertiary : Ant.textSecondary)
                }
            }
            .padding(.vertical, large ? 10 : 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(item.isChecked ? .isSelected : [])
    }
}

/// Кнопка «В список покупок» с отметкой, что добавлено.
struct AddToShoppingListButton: View {
    let entries: () -> [ShoppingEntry]

    @Environment(\.modelContext) private var context
    @Query private var existing: [ShoppingItem]
    @State private var added = false

    var body: some View {
        Button {
            ShoppingList.add(entries(), to: existing, context: context)
            withAnimation(.snappy) { added = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } label: {
            Label(added ? "Добавлено в покупки" : "В список покупок",
                  systemImage: added ? "checkmark.circle.fill" : "cart.badge.plus")
                .contentTransition(.symbolEffect(.replace))
        }
    }
}
