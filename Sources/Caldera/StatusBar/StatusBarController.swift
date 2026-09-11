import AppKit
import SwiftUI
import Combine

/// Owns the menu bar status item(s) for pinned sensors — either one item per
/// sensor ("<icon> <value>" each) or a single combined item with a middle
/// dot joining each sensor's "<icon> <value>" ("<icon> <value> · <icon>
/// <value>"), depending on the user's display-mode preference — plus a
/// single shared popover (the detail/picker view) that opens below
/// whichever status item was clicked.
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
            .combineLatest(preferences.$averageGroupsInMenuBar)
            .map { lhs, averageGroups in (lhs.0, lhs.1, lhs.2, averageGroups) }

        // The threshold publishers aren't destructured below — they're only
        // in the chain so a threshold edit (default or per-sensor) refreshes
        // the menu bar coloring immediately rather than waiting for the next
        // poll. `attributedText(for:)` always reads the live threshold itself.
        sensorStore.$readings
            .combineLatest(prefsStream, preferences.$defaultAlertThreshold, preferences.$customAlertThresholds)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] readings, prefs, _, _ in
                let (visibleKeys, unit, displayMode, averageGroups) = prefs
                self?.selectDefaultIfNeeded(readings: readings)
                self?.rebuildStatusItems(
                    readings: readings,
                    visibleKeys: visibleKeys,
                    unit: unit,
                    displayMode: displayMode,
                    averageGroups: averageGroups
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
        displayMode: DisplayMode,
        averageGroups: Bool
    ) {
        let byKey = Dictionary(uniqueKeysWithValues: readings.map { ($0.key, $0) })
        // Defense in depth: regardless of how `visibleKeys` got this large
        // (a bulk-select, a hand-edited defaults file, a future bug), never
        // actually materialize more than a sane number of live status
        // items — that's the difference between a cluttered menu bar and a
        // frozen one.
        let visibleReadings = Array(visibleKeys.sorted().compactMap { byKey[$0] }.prefix(Self.maxStatusItems))
        let threshold: (String) -> Double = { [preferences] key in preferences.alertThreshold(for: key) }
        let entries = averageGroups
            ? MenuBarEntryBuilder.averagedEntries(from: visibleReadings, unit: unit, threshold: threshold)
            : MenuBarEntryBuilder.individualEntries(from: visibleReadings, unit: unit, threshold: threshold)

        switch displayMode {
        case .separate:
            removeCombinedItem()
            let idsToKeep = Set(entries.map(\.id))
            let idsToRemove = statusItems.keys.filter { !idsToKeep.contains($0) }
            for id in idsToRemove {
                if let item = statusItems[id] {
                    NSStatusBar.system.removeStatusItem(item)
                }
                statusItems.removeValue(forKey: id)
            }
            for entry in entries {
                let item = statusItems[entry.id] ?? makeStatusItem()
                statusItems[entry.id] = item
                item.button?.attributedTitle = attributedText(for: entry)
            }

        case .combined:
            removeAllPerSensorItems()
            let item = combinedStatusItem ?? makeStatusItem()
            combinedStatusItem = item
            if entries.isEmpty {
                item.button?.attributedTitle = NSAttributedString(string: "🌡️ --")
            } else {
                let combined = NSMutableAttributedString()
                for (index, entry) in entries.enumerated() {
                    if index > 0 {
                        combined.append(entrySeparator)
                    }
                    combined.append(attributedText(for: entry))
                }
                item.button?.attributedTitle = combined
            }
        }
    }

    /// "<icon> <value>" — the middle-dot separator between entries in
    /// combined mode is added by the caller, not here. An SF Symbol icon
    /// (averaged entries only) renders as a template image so it tracks the
    /// menu bar's light/dark appearance the same way native icons do; only
    /// the value text carries the severity color, keeping the glyph itself
    /// neutral rather than fighting the system's own icon coloring.
    private func attributedText(for entry: MenuBarEntry) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        let color = entry.severity.nsColor
        let result = NSMutableAttributedString()

        switch entry.icon {
        case .emoji(let glyph):
            result.append(NSAttributedString(string: "\(glyph) ", attributes: [.font: font, .foregroundColor: color]))
        case .symbol(let name):
            let attachment = NSTextAttachment()
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            image?.isTemplate = true
            attachment.image = image
            attachment.bounds = CGRect(x: 0, y: -3, width: 13, height: 13)
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: " ", attributes: [.font: font]))
        }

        result.append(NSAttributedString(string: entry.valueText, attributes: [.font: font, .foregroundColor: color]))
        return result
    }

    private var entrySeparator: NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        return NSAttributedString(string: " · ", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
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
