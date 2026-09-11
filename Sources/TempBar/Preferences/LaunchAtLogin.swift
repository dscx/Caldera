import ServiceManagement

/// Wraps SMAppService.mainApp. Deliberately doesn't cache enabled/disabled
/// state anywhere — the user can toggle this from System Settings directly,
/// so `.status` is read live on every access rather than trusted from a
/// stored preference.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Best-effort: if registration fails, the toggle just reflects
            // the unchanged actual status the next time it's read.
        }
    }
}
