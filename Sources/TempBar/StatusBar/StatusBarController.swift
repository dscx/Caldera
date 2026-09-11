import AppKit
import SwiftUI
import Combine

/// Owns the menu bar status item(s) for pinned sensors — either one item per
/// sensor ("<icon> <value>" each) or a single combined item with "::" joining
/// each sensor's "<icon> <value>" ("<icon> <value>::<icon> <value>"),
/// depending on the user's display-mode preference — plus a single shared
/// popover (the detail/picker view) that opens below whichever status item
/// was clicked.
final class StatusBarController: NSObject {
    private static let maxStatusItems = 20

    private let sensorStore: SensorStore
    private let preferences: PreferencesStore
    private var statusItems: [String: NSStatusItem] = [:]
    private var combinedStatusItem: NSStatusItem?
    private let popover = NSPopover()
    private let settingsWindowController: SettingsWindowController
    private var cancellables = Set<AnyCancellable>()
    private var didSelectDefault = false

    init(sensorStore: SensorStore, preferences: PreferencesStore) {
        self.sensorStore = sensorStore
        self.preferences = preferences
        self.settingsWindowController = SettingsWindowController(sensorStore: sensorStore, preferences: preferences)
        super.init()

        popover.behavior = .transient
        // NSPopover otherwise sizes itself once from the hosting controller's
        // *initial* SwiftUI layout — which at cold launch is the tiny
        // "Scanning sensors…" placeholder — and doesn't grow when the real
        // (much taller) sensor list appears afterward. An explicit fixed
        // content size sidesteps that stale-size bug entirely.
        popover.contentSize = NSSize(width: 340, height: 480)
        popover.contentViewController = NSHostingController(
            rootView: DetailView(
                sensorStore: sensorStore,
                preferences: preferences,
                onOpenSettings: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.settingsWindowController.show()
                }
            )
        )

        let prefsStream = preferences.$visibleKeys
            .combineLatest(preferences.$temperatureUnit, preferences.$displayMode)

        // The threshold publishers aren't destructured below — they're only
        // in the chain so a threshold edit (default or per-sensor) refreshes
        // the menu bar coloring immediately rather than waiting for the next
        // poll. `segment(for:)` always reads the live threshold itself.
        sensorStore.$readings
            .combineLatest(prefsStream, preferences.$defaultAlertThreshold, preferences.$customAlertThresholds)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] readings, prefs, _, _ in
                let (visibleKeys, unit, displayMode) = prefs
                self?.selectDefaultIfNeeded(readings: readings)
                self?.rebuildStatusItems(
                    readings: readings,
                    visibleKeys: visibleKeys,
                    unit: unit,
                    displayMode: displayMode
                )
            }
            .store(in: &cancellables)
    }

    private func selectDefaultIfNeeded(readings: [SensorReading]) {
        guard !didSelectDefault, let first = readings.first else { return }
        didSelectDefault = true
        preferences.selectFirstSensorIfFirstLaunch(first.key)
    }

    private func rebuildStatusItems(
        readings: [SensorReading],
        visibleKeys: Set<String>,
        unit: TemperatureUnit,
        displayMode: DisplayMode
    ) {
        let byKey = Dictionary(uniqueKeysWithValues: readings.map { ($0.key, $0) })
        // Defense in depth: regardless of how `visibleKeys` got this large
        // (a bulk-select, a hand-edited defaults file, a future bug), never
        // actually materialize more than a sane number of live status
        // items — that's the difference between a cluttered menu bar and a
        // frozen one.
        let visibleReadings = visibleKeys.sorted().compactMap { byKey[$0] }.prefix(Self.maxStatusItems)

        switch displayMode {
        case .separate:
            removeCombinedItem()
            let keysToKeep = Set(visibleReadings.map(\.key))
            let keysToRemove = statusItems.keys.filter { !keysToKeep.contains($0) }
            for key in keysToRemove {
                if let item = statusItems[key] {
                    NSStatusBar.system.removeStatusItem(item)
                }
                statusItems.removeValue(forKey: key)
            }
            for reading in visibleReadings {
                let item = statusItems[reading.key] ?? makeStatusItem()
                statusItems[reading.key] = item
                item.button?.attributedTitle = segment(for: reading, unit: unit)
            }

        case .combined:
            removeAllPerSensorItems()
            let item = combinedStatusItem ?? makeStatusItem()
            combinedStatusItem = item
            if visibleReadings.isEmpty {
                item.button?.attributedTitle = NSAttributedString(string: "🌡️ --")
            } else {
                let combined = NSMutableAttributedString()
                for (index, reading) in visibleReadings.enumerated() {
                    if index > 0 {
                        combined.append(NSAttributedString(string: "::"))
                    }
                    combined.append(segment(for: reading, unit: unit))
                }
                item.button?.attributedTitle = combined
            }
        }
    }

    /// "<icon> <value>" — the "::" that separates sensors in combined mode
    /// is added between segments by the caller, not here.
    private func segment(for reading: SensorReading, unit: TemperatureUnit) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        let hotThreshold = preferences.alertThreshold(for: reading.key)
        let color = severity(for: reading, hotThresholdCelsius: hotThreshold).nsColor
        let text = "\(reading.icon) \(reading.formattedShort(unit: unit))"
        return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }

    private func removeCombinedItem() {
        if let item = combinedStatusItem {
            NSStatusBar.system.removeStatusItem(item)
            combinedStatusItem = nil
        }
    }

    private func removeAllPerSensorItems() {
        for item in statusItems.values {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItems.removeAll()
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        return item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
