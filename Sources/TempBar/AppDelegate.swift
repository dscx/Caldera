import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sensorStore = SensorStore()
    private let preferences = PreferencesStore()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(sensorStore: sensorStore, preferences: preferences)
        sensorStore.start(preferences: preferences)
        AlertNotifier.requestAuthorizationIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sensorStore.stop()
    }
}
