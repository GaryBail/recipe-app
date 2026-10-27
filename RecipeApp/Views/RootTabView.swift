import SwiftData
import SwiftUI

/// Вкладка «Покупки» со счётчиком некупленного.
private struct ShoppingTab: View {
    @Query(filter: #Predicate<ShoppingItem> { !$0.isChecked }) private var open: [ShoppingItem]

    var body: some View {
        ShoppingListView()
            .badge(open.count)
    }
}

/// Главная навигация: нижняя панель вкладок.
struct RootTabView: View {
    private var notifications: NotificationCenterModel { .shared }

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Рецепты", systemImage: "fork.knife") }

            FavoritesView()
                .tabItem { Label("Избранное", systemImage: "heart") }

            ShoppingTab()
                .tabItem { Label("Покупки", systemImage: "cart") }

            NavigationStack {
                CommunityFeedView()
                    .navigationDestination(for: Build.self) { BuildDetailView(build: $0) }
                    .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            }
            .tabItem { Label("Сообщество", systemImage: "person.3") }

            SettingsView(showsDone: false)
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
        }
        // Нажали на push об оценке — открываем сборку сообщества.
        .sheet(isPresented: Binding(get: { notifications.pendingBuildId != nil },
                                    set: { if !$0 { notifications.pendingBuildId = nil } })) {
            if let id = notifications.pendingBuildId {
                NavigationStack {
                    CommunityBuildLoader(buildId: id)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Закрыть") { notifications.pendingBuildId = nil }
                            }
                        }
                        .navigationDestination(for: Build.self) { BuildDetailView(build: $0) }
                }
            }
        }
        // Нажали на push о цене — открываем свою сборку.
        .sheet(isPresented: Binding(get: { notifications.pendingLocalBuildId != nil },
                                    set: { if !$0 { notifications.pendingLocalBuildId = nil } })) {
            if let id = notifications.pendingLocalBuildId {
                NavigationStack {
                    LocalBuildLoader(buildId: id)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Закрыть") { notifications.pendingLocalBuildId = nil }
                            }
                        }
                }
            }
        }
    }
}
