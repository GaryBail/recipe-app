import SwiftUI
import SwiftData

@main
struct RecipeAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            Recipe.self,
            Ingredient.self,
            Product.self,
            Build.self,
            BuildItem.self
        ])
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        RecipeListView()
            .task {
                SeedLoader.seedIfNeeded(context)
                await AuthSession.shared.refresh()
                if AuthSession.shared.isLoggedIn {
                    // Токен устройства мог смениться — Apple выдаст его заново.
                    await PushRegistration.requestAndRegister()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await NotificationCenterModel.shared.refresh() }
                }
            }
    }
}
