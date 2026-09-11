import Foundation

enum MenuBarIcon: Equatable {
    case emoji(String)
    case symbol(String)
}

/// One thing to render in the menu bar: either a single pinned sensor, or —
/// when PreferencesStore.averageGroupsInMenuBar is on — one hardware-area
/// group averaged together.
struct MenuBarEntry: Identifiable {
    let id: String
    let icon: MenuBarIcon
    let valueText: String
    let severity: Severity
}

enum MenuBarEntryBuilder {
    /// One entry per pinned sensor, unchanged from before averaging existed.
    static func individualEntries(
        from readings: [SensorReading],
        unit: TemperatureUnit,
        threshold: (String) -> Double
    ) -> [MenuBarEntry] {
        readings.map { reading in
            MenuBarEntry(
                id: reading.key,
                icon: .emoji(reading.icon),
                valueText: reading.formattedShort(unit: unit),
                severity: severity(for: reading, hotThresholdCelsius: threshold(reading.key))
            )
        }
    }

    /// One entry per hardware-area group: every pinned CPU sensor averages
    /// into a single "cpu 62°C" entry, every pinned Fan into one entry, etc.
    /// Severity is the *worst* among the group's members rather than
    /// derived from the average, so one genuinely hot sensor still shows
    /// red even while it's being averaged down by cooler siblings.
    static func averagedEntries(
        from readings: [SensorReading],
        unit: TemperatureUnit,
        threshold: (String) -> Double
    ) -> [MenuBarEntry] {
        struct GroupKey: Hashable {
            let kind: MetricKind
            let label: String
        }

        var groups: [GroupKey: [SensorReading]] = [:]
        for reading in readings {
            let label = reading.kind == .temperature ? reading.temperatureGroupLabel : reading.kind.sectionTitle
            groups[GroupKey(kind: reading.kind, label: label), default: []].append(reading)
        }

        let categoryPriority = ["CPU", "GPU", "Battery", "System"]
        let orderedKeys = groups.keys.sorted { a, b in
            if a.kind != b.kind {
                return MetricKind.allCases.firstIndex(of: a.kind)! < MetricKind.allCases.firstIndex(of: b.kind)!
            }
            let ai = categoryPriority.firstIndex(of: a.label)
            let bi = categoryPriority.firstIndex(of: b.label)
            switch (ai, bi) {
            case let (ai?, bi?): return ai < bi
            case (nil, nil): return a.label < b.label
            case (nil, _): return false
            case (_, nil): return true
            }
        }

        return orderedKeys.compactMap { key in
            guard let members = groups[key], !members.isEmpty else { return nil }
            let average = members.map(\.rawValue).reduce(0, +) / Double(members.count)
            let worst = members
                .map { severity(for: $0, hotThresholdCelsius: threshold($0.key)) }
                .max { $0.rank < $1.rank } ?? .normal
            let icon: MenuBarIcon = key.kind == .temperature
                ? .symbol(SensorCatalog.category(for: members[0].key).averagedSymbolName)
                : .symbol(key.kind.averagedSymbolName)
            return MenuBarEntry(
                id: "avg|\(key.kind.rawValue)|\(key.label)",
                icon: icon,
                valueText: key.kind.formatted(average, unit: unit, precise: false),
                severity: worst
            )
        }
    }
}
