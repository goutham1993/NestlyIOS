import BackgroundTasks
import NestlyCore
import SwiftUI
import UIKit
import UserNotifications

@main
struct NestlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var app = AppModel.shared
    @State private var network = NetworkMonitor()

    init() {
        AppModel.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Palette.accent)
                .environment(app)
                .environment(app.family)
                .environment(app.prefs)
                .onOpenURL { app.open($0) }
                .onChange(of: network.isOnline) { _, online in
                    if online { app.repos.backend.bus.bumpAll() }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                app.prefs.reload()
                app.repos.backend.bus.bumpAll()
                app.scheduleReschedule()
                BackgroundRefresh.submit()
            }
        }
        .backgroundTask(.appRefresh(AppConfig.backgroundRefreshId)) {
            BackgroundRefresh.submit()
            await NotificationScheduler.rescheduleAll()
        }
    }
}

enum BackgroundRefresh {
    static func submit() {
        let request = BGAppRefreshTaskRequest(identifier: AppConfig.backgroundRefreshId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { Self.handle(item) }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    static func handle(_ item: UIApplicationShortcutItem) {
        guard item.type == "\(AppConfig.bundleId).addFeed" else { return }
        Task { @MainActor in AppModel.shared.quickBottleFromShortcut() }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let appointmentId = info[NotificationScheduler.appointmentIdKey] as? String
        await MainActor.run {
            if let appointmentId { AppModel.shared.openAppointment(appointmentId) } else { AppModel.shared.tab = .activity }
        }
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        AppDelegate.handle(shortcutItem)
        completionHandler(true)
    }
}
