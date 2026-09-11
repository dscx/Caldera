import UserNotifications

/// Best-effort local notifications for a pinned sensor crossing the hot
/// threshold. This is deliberately secondary: an ad-hoc-signed, non-notarized
/// app has no stable code-signing identity, and UNUserNotificationCenter is
/// documented to be unreliable in that configuration (silent failures,
/// invalidated connections). The menu bar's red/orange coloring is the
/// primary, guaranteed-reliable alert — this is a bonus that fails silently
/// rather than something the rest of the app depends on.
enum AlertNotifier {
    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func fireHotAlert(sensorName: String, valueText: String) {
        let content = UNMutableNotificationContent()
        content.title = "TempBar"
        content.body = "\(sensorName) is running hot: \(valueText)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
