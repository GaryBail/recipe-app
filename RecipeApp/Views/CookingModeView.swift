import SwiftUI
import UIKit
import UserNotifications

/// Режим готовки: шаги крупно по одному, таймеры из текста шага, экран не гаснет.
struct CookingModeView: View {
    let recipe: Recipe
    let servings: Int

    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var showIngredients = false
    @StateObject private var timers = CookingTimers()

    private var steps: [String] { recipe.steps }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(max(steps.count, 1)))
                    .tint(Ant.primary)
                    .padding(.horizontal)
                    .animation(.snappy, value: step)

                TabView(selection: $step) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                        StepPage(index: index, count: steps.count, text: text, recipeId: recipe.id,
                                 showsPhoto: recipe.isUserCreated, timers: timers)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if !timers.running.isEmpty {
                    RunningTimersBar(timers: timers, steps: steps) { step = $0 }
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation { step = max(0, step - 1) }
                    } label: {
                        Label("Назад", systemImage: "chevron.left")
                    }
                    .buttonStyle(AntButtonStyle(kind: .default))
                    .disabled(step == 0)

                    if step < steps.count - 1 {
                        Button {
                            withAnimation { step += 1 }
                        } label: {
                            Label("Дальше", systemImage: "chevron.right")
                        }
                        .buttonStyle(AntButtonStyle(kind: .primary))
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Label("Готово", systemImage: "checkmark")
                        }
                        .buttonStyle(AntButtonStyle(kind: .primary))
                    }
                }
                .padding()
            }
            .background(Ant.bgLayout)
            .navigationTitle(recipe.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showIngredients = true } label: {
                        Label("Ингредиенты", systemImage: "list.bullet")
                    }
                }
            }
            .sheet(isPresented: $showIngredients) {
                NavigationStack {
                    List(recipe.sortedIngredients) { ingredient in
                        HStack {
                            Text(ingredient.title).font(.title3)
                            Spacer()
                            Text(ingredient.amountText(servings: servings))
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(Ant.textSecondary)
                        }
                    }
                    .navigationTitle("На \(servings) \(ShareText.portions(servings))")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Готово") { showIngredients = false } }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            timers.cancelAll()
        }
    }
}

private struct StepPage: View {
    let index: Int
    let count: Int
    let text: String
    let recipeId: String
    let showsPhoto: Bool
    @ObservedObject var timers: CookingTimers

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Шаг \(index + 1) из \(count)")
                    .font(.headline)
                    .foregroundStyle(Ant.primary)
                if showsPhoto, let image = StepPhotoStore.image(recipeId: recipeId, step: index) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: Ant.radiusLG, style: .continuous))
                }
                Text(text)
                    .font(.system(.title, design: .rounded).weight(.medium))
                    .foregroundStyle(Ant.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let duration = StepTimer.duration(in: text) {
                    TimerCard(step: index, duration: duration, timers: timers, title: "Шаг \(index + 1)")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TimerCard: View {
    let step: Int
    let duration: TimeInterval
    @ObservedObject var timers: CookingTimers
    let title: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let state = timers.state(for: step)
            let remaining = state.map { timers.remaining($0, at: context.date) } ?? duration
            HStack(spacing: 16) {
                Image(systemName: remaining <= 0 && state != nil ? "bell.fill" : "timer")
                    .font(.title)
                    .foregroundStyle(remaining <= 0 && state != nil ? Ant.error : Ant.primary)
                    .symbolEffect(.pulse, isActive: remaining <= 0 && state != nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text(StepTimer.format(max(0, remaining)))
                        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                    Text(state == nil ? "Таймер на этот шаг" : (remaining <= 0 ? "Время вышло!" : "Идёт"))
                        .font(.footnote)
                        .foregroundStyle(Ant.textSecondary)
                }
                Spacer()
                if state == nil {
                    Button { timers.start(step: step, duration: duration, title: title) } label: {
                        Image(systemName: "play.fill").font(.title2)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Запустить таймер")
                } else {
                    Button { timers.cancel(step: step) } label: {
                        Image(systemName: "stop.fill").font(.title2)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Остановить таймер")
                }
            }
            .padding()
            .antCard(padding: nil)
        }
    }
}

private struct RunningTimersBar: View {
    @ObservedObject var timers: CookingTimers
    let steps: [String]
    let go: (Int) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(timers.running.keys.sorted(), id: \.self) { step in
                        let left = timers.running[step].map { timers.remaining($0, at: context.date) } ?? 0
                        Button { go(step) } label: {
                            AntTag(text: "Шаг \(step + 1) · \(StepTimer.format(max(0, left)))",
                                   palette: left <= 0 ? Ant.red : Ant.blue, systemImage: "timer")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 6)
    }
}

/// Таймеры шагов. В фоне о конце таймера сообщит локальное уведомление.
@MainActor
final class CookingTimers: ObservableObject {
    struct State: Equatable {
        let endsAt: Date
        let notificationId: String
    }

    @Published private(set) var running: [Int: State] = [:]

    func state(for step: Int) -> State? { running[step] }

    func remaining(_ state: State, at date: Date) -> TimeInterval { state.endsAt.timeIntervalSince(date) }

    func start(step: Int, duration: TimeInterval, title: String) {
        let id = "cooking-\(UUID().uuidString)"
        running[step] = State(endsAt: Date().addingTimeInterval(duration), notificationId: id)
        guard !Motion.isUITesting else { return }  // в UI-тестах без системного запроса разрешений
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            let content = UNMutableNotificationContent()
            content.title = "Таймер: \(title)"
            content.body = "Время вышло — переходите к следующему шагу."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, duration), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    func cancel(step: Int) {
        if let state = running.removeValue(forKey: step) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [state.notificationId])
        }
    }

    func cancelAll() {
        let ids = running.values.map(\.notificationId)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        running = [:]
    }
}
