import Combine
import StoreKit
import SwiftUI
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions:
        [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if !ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            UNUserNotificationCenter.current().delegate = self
        }
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                          withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
@MainActor
struct DinnerPrepApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.store)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: StoreAccess
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @State private var editorOpen = false
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        HomeView(editorOpen: $editorOpen)
            .disabled(!model.ready)
            .overlay(alignment: .top) {
                if !model.ready { ProgressView().padding(12).panel() }
            }
            .sheet(item: $model.route) { route in
                switch route {
                case .library: LibraryView()
                case .fileImport(let values): LibraryView(importing: values)
                case .settings: SettingsView()
                case .planCard:
                    if let timing = model.timing { CardView(timing: timing, prep: model.meal.prep) }
                case .milestone: CardView()
                case .paywall: PaywallView()
                }
            }
            .task { await model.start() }
            .onReceive(timer) { _ in if scenePhase == .active { model.tick() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { model.wasBackgrounded() }
                if phase == .active { Task { await model.becameActive() } }
            }
            .task(id: reviewIdle) {
                guard reviewIdle else { return }
                do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
                if reviewIdle && model.consumeReviewRequest() { requestReview() }
            }
    }

    private var reviewIdle: Bool {
        model.reviewPending && model.route == nil && !editorOpen && scenePhase == .active &&
            model.notice == nil && !model.storageWarning && !store.busy &&
            (model.meal.recipe == nil || model.timing != nil) &&
            model.data.reminder == model.confirmedReminder
    }
}
