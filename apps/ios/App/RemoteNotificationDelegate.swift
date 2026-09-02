import UIKit

@MainActor
final class RemoteNotificationDelegate: NSObject, UIApplicationDelegate {
    let model = AppModel()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await model.registerPushToken(token, environment: .current) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        model.recordPushRegistrationFailure(error)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard userInfo["enzo"] as? String == "state-changed" else {
            completionHandler(.noData)
            return
        }

        Task {
            let refreshed = await model.refreshFromRemoteNotification()
            completionHandler(refreshed ? .newData : .failed)
        }
    }
}

enum PushEnvironment: String, Encodable {
    case sandbox
    case production

    static var current: PushEnvironment {
#if DEBUG
        .sandbox
#else
        .production
#endif
    }
}
