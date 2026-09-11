import Foundation
import Combine

/// Discovers this Mac's sensors (temperature, fan, power) once at launch,
/// then polls their current values on a user-configurable interval. All
/// SMC/IOKit calls happen on a private serial queue; published state is only
/// ever written on the main queue for SwiftUI/AppKit observers.
final class SensorStore: ObservableObject {
    @Published private(set) var readings: [SensorReading] = []
    /// Recent raw samples per sensor key, oldest first, capped to
    /// `historyLimit` — feeds the popover's per-row sparkline.
    @Published private(set) var history: [String: [Double]] = [:]
    @Published private(set) var isScanning = true
    @Published private(set) var errorMessage: String?
    /// System-wide top CPU consumers, refreshed continuously on its own
    /// timer — see `refreshTopProcesses`.
    @Published private(set) var topProcesses: [ProcessCPUUsage] = []

    private let smc = SMC()
    private let queue = DispatchQueue(label: "com.dscx.tempbar.smc")
    private var sensors: [DiscoveredSensor] = []
    /// CPU-category keys without a curated name get a stable "CPU Sensor N"
    /// label, computed once from the full discovered set so numbering
    /// doesn't shift if one sensor briefly fails to decode on a given poll.
    private var assignedNames: [String: String] = [:]
    private var timer: Timer?
    private var processTimer: Timer?
    private var intervalCancellable: AnyCancellable?
    private var preferences: PreferencesStore?
    private var previousSeverities: [String: Severity] = [:]
    private let historyLimit = 40
    /// Fixed, not tied to the user's (possibly very fast, down to 1s) sensor
    /// poll interval — there's no need to spawn `ps` that often for a list
    /// that's just informational context, not a live alert signal.
    private let processFetchInterval: TimeInterval = 3.0

    func start(preferences: PreferencesStore) {
        self.preferences = preferences

        intervalCancellable = preferences.$pollIntervalSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interval in
                self?.reschedule(interval: interval)
            }

        queue.async { [weak self] in
            self?.openAndDiscover()
            self?.refreshTopProcesses()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.processTimer = Timer.scheduledTimer(withTimeInterval: self.processFetchInterval, repeats: true) { [weak self] _ in
                self?.queue.async { self?.refreshTopProcesses() }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        processTimer?.invalidate()
        processTimer = nil
        intervalCancellable = nil
        queue.async { [weak self] in
            self?.smc.close()
        }
    }

    private func openAndDiscover() {
        do {
            try smc.open()
        } catch {
            publish(isScanning: false, errorMessage: "Couldn't connect to the sensor controller on this Mac.")
            return
        }

        let discovered = discoverSensors(smc: smc)
        sensors = discovered
        assignedNames = SensorCatalog.assignDescriptiveNames(for: discovered.map(\.key))

        if discovered.isEmpty {
            publish(isScanning: false, errorMessage: "No sensors were found on this Mac.")
            return
        }

        pollOnce()
        DispatchQueue.main.async { [weak self] in
            self?.isScanning = false
        }
    }

    private func reschedule(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.queue.async { self?.pollOnce() }
        }
    }

    private func pollOnce() {
        guard !sensors.isEmpty else { return }

        var updated: [SensorReading] = []
        updated.reserveCapacity(sensors.count)

        for sensor in sensors {
            guard let output = try? smc.readRaw(forCode: sensor.code) else { continue }
            guard let value = decodeSMCValue(
                dataType: output.dataType,
                dataSize: output.dataSize,
                bytes: output.bytes
            ) else { continue }
            updated.append(
                SensorReading(
                    key: sensor.key,
                    name: assignedNames[sensor.key] ?? SensorCatalog.name(for: sensor.key),
                    category: SensorCatalog.category(for: sensor.key),
                    kind: sensor.kind,
                    rawValue: value
                )
            )
        }

        let kindOrder = MetricKind.allCases
        let categoryOrder = SensorCategory.allCases
        updated.sort { a, b in
            if a.kind != b.kind {
                return kindOrder.firstIndex(of: a.kind)! < kindOrder.firstIndex(of: b.kind)!
            }
            if a.category != b.category {
                return categoryOrder.firstIndex(of: a.category)! < categoryOrder.firstIndex(of: b.category)!
            }
            return a.key < b.key
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.readings = updated
            for reading in updated {
                var series = self.history[reading.key] ?? []
                series.append(reading.rawValue)
                if series.count > self.historyLimit {
                    series.removeFirst(series.count - self.historyLimit)
                }
                self.history[reading.key] = series
            }
            self.checkAlerts(readings: updated)
        }
    }

    /// Fires a best-effort notification the moment a temperature sensor
    /// first crosses into "hot" — not on every poll while it stays hot. The
    /// menu bar's coloring (always up to date) is the reliable signal; this
    /// is a bonus nudge on top of it. Scoped to pinned sensors only, unless
    /// `alertForAllSensors` widens it to everything discovered.
    private func checkAlerts(readings: [SensorReading]) {
        guard let preferences else { return }
        let pinned = preferences.visibleKeys
        let alertAll = preferences.alertForAllSensors
        let unit = preferences.temperatureUnit

        for reading in readings where reading.kind == .temperature && (alertAll || pinned.contains(reading.key)) {
            let threshold = preferences.alertThreshold(for: reading.key)
            let newSeverity = severity(for: reading, hotThresholdCelsius: threshold)
            let oldSeverity = previousSeverities[reading.key] ?? .normal
            if newSeverity == .hot, oldSeverity != .hot {
                AlertNotifier.fireHotAlert(sensorName: reading.name, valueText: reading.formattedPrecise(unit: unit))
            }
            previousSeverities[reading.key] = newSeverity
        }
    }

    /// Runs on its own timer (`processFetchInterval`), independent of hot/
    /// cold state — an always-current "what's using CPU right now" panel,
    /// same idea as Activity Monitor's process list, not an alert-only hint.
    /// Called on `queue` (background); only the stateless result crosses
    /// back to the main queue.
    private func refreshTopProcesses() {
        let processes = ProcessMonitor.topProcesses(limit: 5)
        DispatchQueue.main.async { [weak self] in
            self?.topProcesses = processes
        }
    }

    private func publish(isScanning: Bool, errorMessage: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.isScanning = isScanning
            self?.errorMessage = errorMessage
        }
    }
}
