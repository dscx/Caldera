import SwiftUI

/// The settings window: which sections/sensors are hidden from the main
/// list, section order, and the general preferences that used to crowd the
/// main popover's header.
struct SettingsView: View {
    @ObservedObject var sensorStore: SensorStore
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        List {
            Section("General") {
                Picker("Temperature unit", selection: $preferences.temperatureUnit) {
                    Text("Celsius").tag(TemperatureUnit.celsius)
                    Text("Fahrenheit").tag(TemperatureUnit.fahrenheit)
                }
                Picker("Menu bar display", selection: $preferences.displayMode) {
                    Text("Separate items").tag(DisplayMode.separate)
                    Text("Combined item").tag(DisplayMode.combined)
                }
                Stepper(
                    "Refresh every \(Int(preferences.pollIntervalSeconds))s",
                    value: $preferences.pollIntervalSeconds,
                    in: PreferencesStore.pollIntervalRange
                )
                Stepper(
                    "Default alert \u{2265} \(Int(preferences.defaultAlertThreshold))\u{00B0}C",
                    value: $preferences.defaultAlertThreshold,
                    in: PreferencesStore.alertThresholdRange,
                    step: 5
                )
                Toggle("Launch at login", isOn: Binding(
                    get: { LaunchAtLogin.isEnabled },
                    set: { LaunchAtLogin.setEnabled($0) }
                ))
                Toggle("Alert on any sensor, not just pinned", isOn: $preferences.alertForAllSensors)
            }

            Section("Sections") {
                ForEach(preferences.sectionOrder.indices, id: \.self) { index in
                    let label = preferences.sectionOrder[index]
                    // These are always the all-caps section titles
                    // ("TEMPERATURES"), so .capitalized reliably gives
                    // "Temperatures" — safe here specifically.
                    sectionRow(label, displayText: label.capitalized, index: index)
                }
            }

            if !temperatureSubgroups.isEmpty {
                Section("Temperature Groups") {
                    ForEach(temperatureSubgroups, id: \.self) { label in
                        // Verbatim, not .capitalized: these are either
                        // already-correct acronyms ("CPU") or raw 2-letter
                        // SMC key prefixes ("TD", "Tz") where case is part
                        // of the identity — "TP" and "Tp" are genuinely
                        // different clusters, and .capitalized would show
                        // both as "Tp", indistinguishable.
                        sectionRow(label, displayText: label)
                    }
                }
            }

            if !preferences.hiddenKeys.isEmpty {
                Section("Hidden Sensors") {
                    ForEach(Array(preferences.hiddenKeys).sorted(), id: \.self) { key in
                        HStack {
                            Text(SensorCatalog.name(for: key))
                            Spacer()
                            Button("Unhide") { preferences.unhideKey(key) }
                                .buttonStyle(.link)
                        }
                    }
                }
            }

        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .frame(minWidth: 340, minHeight: 420)
    }

    /// `index` is only passed for the top-level, reorderable Sections list;
    /// the Temperature Groups list omits it and gets no move buttons.
    private func sectionRow(_ label: String, displayText: String, index: Int? = nil) -> some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { !preferences.isSectionHidden(label) },
                set: { _ in preferences.toggleHiddenSection(label) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            Text(displayText)
            Spacer()
            if let index {
                Button(action: { preferences.swapSections(index, index - 1) }) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                Button(action: { preferences.swapSections(index, index + 1) }) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(index == preferences.sectionOrder.count - 1)
            }
        }
    }

    /// Only the subgroups actually present on this Mac right now — no point
    /// offering to hide "GPU" if this machine never reported one.
    private var temperatureSubgroups: [String] {
        let priority = ["CPU", "GPU", "Battery", "System"]
        let present = Set(sensorStore.readings.filter { $0.kind == .temperature }.map(\.temperatureGroupLabel))
        let known = priority.filter { present.contains($0) }
        let unknown = present.subtracting(priority).sorted()
        return known + unknown
    }
}
