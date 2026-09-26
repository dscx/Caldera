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
    /// Fans Caldera can override on this Mac, discovered once at launch.
    @Published private(set) var fanControls: [FanControlState] = []
    /// Keyed by FanControlState.acKey. A fan present here is in manual mode
    /// at this target RPM; absent means automatic. Never persisted — see
    /// FanControlState's doc comment.
    @Published private(set) var fanManualTargets: [String: Double] = [:]
    /// Set the first time a fan-target write is rejected by the driver
    /// (kIOReturnNotPrivileged, confirmed empirically: recent macOS refuses
    /// SMC key *writes* from an unprivileged, unentitled process even though
    /// reads are unrestricted — unlike the missing "FS! " key, this isn't
    /// something Caldera can route around by rewriting more aggressively).
    /// Once true, the UI stops offering manual control entirely rather than
    /// showing a slider that silently does nothing.
    @Published private(set) var fanControlUnsupported = false
    /// System-wide top CPU consumers, refreshed continuously on its own
    /// timer — see `refreshTopProcesses`.
    @Published private(set) var topProcesses: [ProcessCPUUsage] = []

    private let smc = SMC()
    private let queue = DispatchQueue(label: "com.dscx.caldera.smc")
    private var sensors: [DiscoveredSensor] = []
    /// `queue`-confined mirror of `fanControls`, for pollOnce's re-assertion
    /// loop — same read-only-after-launch/main-thread-copy split as `sensors`.
    private var fanControlDescriptors: [FanControlState] = []
    /// `queue`-confined source of truth for which fans are in manual mode
    /// and at what target — `fanManualTargets` is the main-thread mirror.
    private var activeManualFanTargets: [String: Double] = [:]
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
            // Dropping manual targets before close is the entire "restore
            // automatic" step on this SMC generation — see FanControlState.
            self?.activeManualFanTargets.removeAll()
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

        let fans = discoverFanControls(smc: smc)
        fanControlDescriptors = fans
        // Probed once, at launch, rather than waiting for the user to click
        // "Manual Control…" and hit the failure themselves: a write-back of
        // the exact bytes just read is a true no-op (not even a round-trip
        // through encodeSMCValue), so this can't itself change fan behavior
        // — it only answers whether writes are permitted at all on this Mac.
        let writable = probeFanWriteSupport(smc: smc, controls: fans)
        DispatchQueue.main.async { [weak self] in
            self?.fanControls = fans
            if !writable {
                self?.fanControlUnsupported = true
            }
        }

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

        // Re-assert every manual fan target on each poll tick rather than
        // write-once: this SMC generation's own thermal loop keeps
        // recalculating the target key on its own cadence, so a one-time
        // write would just get quietly overwritten again shortly after.
        for (acKey, target) in activeManualFanTargets {
            guard let control = fanControlDescriptors.first(where: { $0.acKey == acKey }) else { continue }
            if !writeFanTarget(control: control, rpm: target) {
                activeManualFanTargets.removeValue(forKey: acKey)
                DispatchQueue.main.async { [weak self] in
                    self?.fanControlUnsupported = true
                    self?.fanManualTargets.removeValue(forKey: acKey)
                }
            }
        }

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

    /// Overrides a fan's target RPM, clamped to its own SMC-reported
    /// min/max, and puts it in manual mode. Safe to call repeatedly (e.g.
    /// while dragging a slider) — each call replaces the previous target.
    /// If the write itself is rejected (see `fanControlUnsupported`), manual
    /// mode is never entered rather than showing a control that does
    /// nothing.
    func setFanManualTarget(acKey: String, rpm: Double) {
        queue.async { [weak self] in
            guard let self, let control = self.fanControlDescriptors.first(where: { $0.acKey == acKey }) else { return }
            let clamped = min(max(rpm, control.minRPM), control.maxRPM)
            guard self.writeFanTarget(control: control, rpm: clamped) else {
                DispatchQueue.main.async { [weak self] in
                    self?.fanControlUnsupported = true
                    self?.fanManualTargets.removeValue(forKey: acKey)
                }
                return
            }
            self.activeManualFanTargets[acKey] = clamped
            DispatchQueue.main.async { [weak self] in
                self?.fanManualTargets[acKey] = clamped
            }
        }
    }

    /// Returns a fan to automatic control by simply no longer rewriting its
    /// target key — see FanControlState's doc comment for why that alone is
    /// sufficient on this SMC generation.
    func setFanAutomatic(acKey: String) {
        queue.async { [weak self] in
            self?.activeManualFanTargets.removeValue(forKey: acKey)
        }
        DispatchQueue.main.async { [weak self] in
            self?.fanManualTargets.removeValue(forKey: acKey)
        }
    }

    /// Returns false if the write was rejected — confirmed empirically to
    /// happen with kIOReturnNotPrivileged on current macOS for an
    /// unprivileged, unentitled process, even though reads are unrestricted.
    @discardableResult
    private func writeFanTarget(control: FanControlState, rpm: Double) -> Bool {
        guard let bytes = encodeSMCValue(rpm, dataType: control.dataType) else { return false }
        do {
            try smc.writeRaw(forCode: fourCharCode(from: control.targetKey), bytes: bytes)
            return true
        } catch {
            return false
        }
    }

    /// Enumerates this Mac's fans via "FNum", then keeps only the ones whose
    /// min/max bounds and target key all read back cleanly — a fan Caldera
    /// can't read bounds for is one it won't guess bounds for either.
    private func discoverFanControls(smc: SMC) -> [FanControlState] {
        guard
            let countRaw = try? smc.readRaw(forCode: fourCharCode(from: "FNum")),
            let countValue = decodeSMCValue(dataType: countRaw.dataType, dataSize: countRaw.dataSize, bytes: countRaw.bytes)
        else { return [] }

        var result: [FanControlState] = []
        for index in 0..<Int(countValue) {
            let acKey = "F\(index)Ac"
            guard
                let mnRaw = try? smc.readRaw(forCode: fourCharCode(from: "F\(index)Mn")),
                let minRPM = decodeSMCValue(dataType: mnRaw.dataType, dataSize: mnRaw.dataSize, bytes: mnRaw.bytes),
                let mxRaw = try? smc.readRaw(forCode: fourCharCode(from: "F\(index)Mx")),
                let maxRPM = decodeSMCValue(dataType: mxRaw.dataType, dataSize: mxRaw.dataSize, bytes: mxRaw.bytes),
                let tgRaw = try? smc.readRaw(forCode: fourCharCode(from: "F\(index)Tg")),
                maxRPM > minRPM
            else { continue }

            let curatedName = SensorCatalog.name(for: acKey)
            let name = curatedName != acKey ? curatedName : "Fan \(index + 1)"
            result.append(FanControlState(
                acKey: acKey,
                targetKey: "F\(index)Tg",
                name: name,
                minRPM: minRPM,
                maxRPM: maxRPM,
                dataType: tgRaw.dataType
            ))
        }
        return result
    }

    /// Writes a fan's target key back to the exact bytes just read from it —
    /// a true no-op, not a round-trip through encodeSMCValue — purely to
    /// answer "does this Mac's SMC allow writes from this process at all."
    /// Testing the first fan is enough: the rejection is a process-level
    /// privilege check (kIOReturnNotPrivileged), not specific to one key.
    private func probeFanWriteSupport(smc: SMC, controls: [FanControlState]) -> Bool {
        guard let first = controls.first else { return true }
        guard let current = try? smc.readRaw(forCode: fourCharCode(from: first.targetKey)) else { return true }
        return (try? smc.writeRaw(forCode: fourCharCode(from: first.targetKey), bytes: current.bytes)) != nil
    }
}
