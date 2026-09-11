import AppKit
import SwiftUI

/// A regular window (not another popover) for the settings that don't need
/// to be one click away — section visibility, ordering, and hidden sensors.
/// Accessory apps (no Dock icon) can still show and focus normal windows.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let sensorStore: SensorStore
    private let preferences: PreferencesStore

    init(sensorStore: SensorStore, preferences: PreferencesStore) {
        self.sensorStore = sensorStore
        self.preferences = preferences
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(sensorStore: sensorStore, preferences: preferences))
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "Caldera Settings"
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.setContentSize(NSSize(width: 380, height: 520))
        newWindow.minSize = NSSize(width: 320, height: 360)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
