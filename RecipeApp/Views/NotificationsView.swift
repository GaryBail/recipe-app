import SwiftData
import SwiftUI

struct NotificationsView: View {
    private var model: NotificationCenterModel { .shared }
    @State private var isLoading = true

    var body: some View {
        List {
            if !AuthSession.shared.isLoggedIn {
                Section {
                    Text("Войдите, чтобы получать уведомления об оценках и отзывах на ваши сборки.")
                        .foregroundStyle(.secondary)
                    LoginRequiredButton(title: "Войти")
                }
            } else if model.items.isEmpty {
                Text(isLoading ? "Загрузка…" : "Пока нет уведомлений. Поделитесь сборкой или включите «Следить за ценой» в сборке.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.items) { item in
                    NavigationLink {
                        if item.isPrice {
                            LocalBuildLoader(buildId: item.buildId)
                        } else {
                            CommunityBuildLoader(buildId: item.buildId)
                        }
                    } label: {
                        NotificationRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("Уведомления")
        .refreshable { await model.refresh() }
        .task {
            await model.refresh()
            isLoading = false
        }
        .onDisappear { Task { await model.markAllRead() } }
    }
}

private struct NotificationRow: View {
    let item: AppNotificationDTO

    private var icon: String {
        switch item.kind {
        case "comment": return "text.bubble.fill"
        case "price_drop": return "tag.fill"
        case "reminder": return "fork.knife"
        default: return "star.fill"
        }
    }

    private var color: Color {
        switch item.kind {
        case "comment": return .accentColor
        case "price_drop": return .green
        case "reminder": return .orange
        default: return .yellow
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(item.isRead ? .regular : .semibold))
                Text(item.body).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer(minLength: 0)
            if !item.isRead {
                Circle().fill(Color.accentColor).frame(width: 8, height: 8).padding(.top, 6)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Колокольчик с числом непрочитанных.
struct NotificationsBell: View {
    private var model: NotificationCenterModel { .shared }

    var body: some View {
        NavigationLink {
            NotificationsView()
        } label: {
            Image(systemName: model.unreadCount > 0 ? "bell.badge" : "bell")
                .overlay(alignment: .topTrailing) {
                    if model.unreadCount > 0 {
                        Text(model.unreadCount > 99 ? "99+" : "\(model.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(.red, in: Capsule())
                            .offset(x: 10, y: -8)
                    }
                }
        }
        .accessibilityLabel(model.unreadCount > 0 ? "Уведомления, непрочитанных: \(model.unreadCount)" : "Уведомления")
    }
}

/// Открывает свою сборку по локальному id (из уведомления о цене).
struct LocalBuildLoader: View {
    let buildId: String
    @Environment(\.modelContext) private var context
    @State private var build: Build?
    @State private var notFound = false

    var body: some View {
        Group {
            if let build {
                BuildDetailView(build: build)
            } else if notFound {
                ContentUnavailableView("Сборка не найдена", systemImage: "questionmark.folder",
                                       description: Text("Возможно, она удалена с этого телефона."))
            } else {
                ProgressView()
            }
        }
        .task(id: buildId) {
            guard let uuid = UUID(uuidString: buildId) else { notFound = true; return }
            let descriptor = FetchDescriptor<Build>(predicate: #Predicate { $0.id == uuid })
            build = try? context.fetch(descriptor).first
            notFound = build == nil
        }
    }
}
