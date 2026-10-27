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
                Text(isLoading ? "Загрузка…" : "Пока нет уведомлений. Поделитесь сборкой — и здесь появятся оценки.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.items) { item in
                    NavigationLink {
                        CommunityBuildLoader(buildId: item.buildId)
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.kind == "comment" ? "text.bubble.fill" : "star.fill")
                .foregroundStyle(item.kind == "comment" ? Color.accentColor : .yellow)
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
