import SwiftUI

/// The popover content: every discovered (and not hidden) sensor, grouped
/// by category, with a checkbox to pin each one to the menu bar. Section
/// visibility/order, hidden sensors, and general preferences live in the
/// separate Settings window instead — this stays focused on the live list.
struct DetailView: View {
    @ObservedObject var sensorStore: SensorStore
    @ObservedObject var preferences: PreferencesStore
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            // Anchored above the footer, not the header, so it doesn't
            // change the sensor list's position — only this bottom strip's
            // row count varies as the process list refreshes.
            Divider()
            topProcessesPanel
            Divider()
            footer
        }
        .frame(width: 340, height: 480)
    }

    private var header: some View {
        HStack {
            Text("Sensors")
                .font(.headline)
            Spacer()
            Text("\(preferences.visibleKeys.count) in menu bar")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// Always visible, refreshed continuously on its own timer — an
    /// Activity-Monitor-style "what's using CPU right now" panel, not an
    /// alert tied to any sensor being hot. (There's also no API mapping a
    /// specific sensor to a specific process, so it's system-wide context
    /// rather than a claimed cause even when something is hot.)
    private var topProcessesPanel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("TOP CPU PROCESSES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            if sensorStore.topProcesses.isEmpty {
                Text("Loading…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sensorStore.topProcesses) { proc in
                    HStack {
                        Text(proc.name)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.0f%%", proc.cpuPercent))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if sensorStore.isScanning {
            ProgressView("Scanning sensors…")
                .padding(24)
                .frame(maxWidth: .infinity)
        } else if sensorStore.readings.isEmpty {
            Text(sensorStore.errorMessage ?? "No sensors found.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: .infinity)
        } else {
            sensorList
        }
    }

    private var sensorList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(preferences.sectionOrder, id: \.self) { sectionKey in
                    if let kind = MetricKind.allCases.first(where: { $0.sectionTitle.uppercased() == sectionKey }),
                       !preferences.isSectionHidden(sectionKey) {
                        let items = sensorStore.readings.filter {
                            $0.kind == kind && !preferences.hiddenKeys.contains($0.key)
                        }
                        if !items.isEmpty {
                            sectionHeader(sectionKey, items: items)
                            if !preferences.isCollapsed(sectionKey) {
                                if kind == .temperature {
                                    // The temperature list can run into the hundreds
                                    // of sensors, so it gets a second grouping level:
                                    // known hardware areas first, then any sensors
                                    // without a curated name clustered by their
                                    // shared SMC key prefix (e.g. TD00, TD01, TD02…
                                    // together) rather than dumped into one flat list.
                                    ForEach(orderedSubgroups(of: items), id: \.self) { label in
                                        if !preferences.isSectionHidden(label) {
                                            let subItems = items.filter { $0.temperatureGroupLabel == label }
                                            subgroupHeader(label, items: subItems)
                                            if !preferences.isCollapsed(label) {
                                                ForEach(subItems) { reading in
                                                    sensorRow(reading)
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    ForEach(items) { reading in
                                        sensorRow(reading)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// Known hardware areas first (in a fixed, sensible order), then any
    /// prefix-derived clusters for unrecognized sensors, alphabetically.
    private func orderedSubgroups(of items: [SensorReading]) -> [String] {
        let priority = ["CPU", "GPU", "Battery", "System"]
        let present = Set(items.map(\.temperatureGroupLabel))
        let known = priority.filter { present.contains($0) }
        let unknown = present.subtracting(priority).sorted()
        return known + unknown
    }

    /// Section/subgroup headers double as collapse toggles — clicking the
    /// chevron/title hides the group's rows so a section the user doesn't
    /// care about (a mystery cluster of raw keys, or a whole "Fans"/"Power"
    /// section) can be tucked away instead of always eating scroll space.
    /// The leading checkbox is a separate control: it pins/unpins every
    /// sensor in the group to the menu bar at once, showing a dash when the
    /// group is partially pinned. To hide a section entirely (not just
    /// collapse it), or reorder sections, see Settings.
    private func sectionHeader(_ title: String, items: [SensorReading]) -> some View {
        headerRow(title: title, items: items, indent: 12, titleSize: 10, chevronSize: 8, style: .secondary)
    }

    private func subgroupHeader(_ label: String, items: [SensorReading]) -> some View {
        headerRow(title: label, items: items, indent: 20, titleSize: 9, chevronSize: 7, style: .tertiary)
    }

    /// A group larger than this doesn't get a bulk-select checkbox — pinning
    /// dozens of sensors to the menu bar at once (e.g. all ~340 sensors
    /// under the top-level "Temperatures" header) isn't a real use case,
    /// just a footgun: it floods the menu bar with that many status items
    /// and drives CPU with that many extra live-updating labels.
    private static let bulkSelectLimit = 20

    private func headerRow(
        title: String,
        items: [SensorReading],
        indent: CGFloat,
        titleSize: CGFloat,
        chevronSize: CGFloat,
        style: HierarchicalShapeStyle
    ) -> some View {
        let keys = items.map(\.key)
        let collapsed = preferences.isCollapsed(title)
        let allOn = preferences.allVisible(keys)
        let anyOn = preferences.anyVisible(keys)

        return HStack(spacing: 4) {
            if keys.count <= Self.bulkSelectLimit {
                Button(action: { preferences.setVisible(!allOn, for: keys) }) {
                    Image(systemName: allOn ? "checkmark.square.fill" : (anyOn ? "minus.square.fill" : "square"))
                        .font(.system(size: titleSize))
                        .foregroundStyle(allOn || anyOn ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: titleSize, height: titleSize)
            }

            Button(action: { preferences.toggleCollapsed(title) }) {
                HStack(spacing: 4) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: chevronSize, weight: .bold))
                    Text(title)
                        .font(.system(size: titleSize, weight: .semibold))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(style)
        .padding(.leading, indent)
        .padding(.trailing, 12)
        .padding(.top, indent == 12 ? 10 : 6)
        .padding(.bottom, indent == 12 ? 2 : 1)
    }

    private func sensorRow(_ reading: SensorReading) -> some View {
        SensorRow(
            reading: reading,
            unit: preferences.temperatureUnit,
            threshold: preferences.alertThreshold(for: reading.key),
            hasCustomThreshold: preferences.hasCustomAlertThreshold(for: reading.key),
            history: sensorStore.history[reading.key] ?? [],
            isVisible: preferences.visibleKeys.contains(reading.key),
            fanControl: sensorStore.fanControls.first(where: { $0.acKey == reading.key }),
            manualFanTarget: sensorStore.fanManualTargets[reading.key],
            onToggle: { preferences.toggle(reading.key) },
            onThresholdChange: { newValue in
                let clamped = min(max(newValue, PreferencesStore.alertThresholdRange.lowerBound), PreferencesStore.alertThresholdRange.upperBound)
                preferences.setCustomAlertThreshold(clamped, for: reading.key)
            },
            onThresholdReset: { preferences.resetAlertThreshold(for: reading.key) },
            onFanTargetChange: { rpm in sensorStore.setFanManualTarget(acKey: reading.key, rpm: rpm) },
            onFanAutomatic: { sensorStore.setFanAutomatic(acKey: reading.key) }
        )
        .contextMenu {
            Button("Hide This Sensor") {
                preferences.hideKey(reading.key)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(10)
    }
}

private struct SensorRow: View {
    let reading: SensorReading
    let unit: TemperatureUnit
    let threshold: Double
    let hasCustomThreshold: Bool
    let history: [Double]
    let isVisible: Bool
    let fanControl: FanControlState?
    let manualFanTarget: Double?
    let onToggle: () -> Void
    let onThresholdChange: (Double) -> Void
    let onThresholdReset: () -> Void
    let onFanTargetChange: (Double) -> Void
    let onFanAutomatic: () -> Void

    private var currentSeverity: Severity {
        severity(for: reading, hotThresholdCelsius: threshold)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // The threshold +/- controls below need their own tap targets,
            // so only checkbox/icon/name/value are inside the toggle button
            // — nesting a Button inside a Button makes the inner one
            // unreachable on macOS.
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: isVisible ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isVisible ? Color.accentColor : Color.secondary)
                    Text(reading.icon)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(reading.name)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                        if reading.name != reading.key {
                            Text(reading.key)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if history.count > 1 {
                        Sparkline(values: history, color: Color(currentSeverity.nsColor))
                            .frame(width: 36, height: 14)
                    }
                    Text(reading.formattedPrecise(unit: unit))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color(currentSeverity.nsColor))
                        .frame(width: 56, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isVisible && reading.kind == .temperature {
                thresholdControl
                    .padding(.leading, 40)
            }

            if reading.kind == .fan, let fanControl {
                fanControlRow(fanControl)
                    .padding(.leading, 40)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    /// "Manual Control…" seeds the target at the fan's current live speed —
    /// no jump when engaging override — then a slider (clamped to the fan's
    /// own SMC-reported min/max) adjusts it. "Auto" hands control back;
    /// quitting Caldera does the same automatically.
    private func fanControlRow(_ control: FanControlState) -> some View {
        Group {
            if let manualFanTarget {
                HStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { manualFanTarget },
                            set: { onFanTargetChange($0) }
                        ),
                        in: control.minRPM...control.maxRPM
                    )
                    .frame(width: 110)
                    Text("\(Int(manualFanTarget)) RPM")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button("Auto", action: onFanAutomatic)
                        .buttonStyle(.plain)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            } else {
                Button("Manual Control…") {
                    onFanTargetChange(reading.rawValue)
                }
                .buttonStyle(.plain)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .help("Override this fan's speed. Reverts to automatic when Caldera quits.")
            }
        }
    }

    private var thresholdControl: some View {
        HStack(spacing: 4) {
            Text(hasCustomThreshold ? "Alert ≥ \(Int(threshold))°C" : "Alert ≥ \(Int(threshold))°C (default)")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            Button(action: { onThresholdChange(threshold - 5) }) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .font(.system(size: 9))
            Button(action: { onThresholdChange(threshold + 5) }) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
            .font(.system(size: 9))
            if hasCustomThreshold {
                Button(action: onThresholdReset) {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .buttonStyle(.plain)
                .font(.system(size: 9))
            }
        }
    }
}

/// A minimal min/max-normalized line graph of recent values — just enough
/// to show "trending up/down/flat" at a glance in a 36x14pt row accessory.
private struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard values.count > 1 else { return }
                let minValue = values.min() ?? 0
                let maxValue = values.max() ?? 1
                let range = max(maxValue - minValue, 0.001)
                let stepX = geo.size.width / CGFloat(values.count - 1)

                for (index, value) in values.enumerated() {
                    let x = CGFloat(index) * stepX
                    let normalized = (value - minValue) / range
                    let y = geo.size.height * (1 - CGFloat(normalized))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
    }
}
