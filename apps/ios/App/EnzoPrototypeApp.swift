import SwiftUI

@main
struct EnzoPrototypeApp: App {
    @UIApplicationDelegateAdaptor(RemoteNotificationDelegate.self)
    private var notificationDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(model: notificationDelegate.model)
        }
    }
}
