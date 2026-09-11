import Foundation

struct SensorReading: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let name: String
    let category: SensorCategory
    let kind: MetricKind
    /// Canonical unit for `kind`: Celsius for temperature, RPM for fan, watts for power.
    var rawValue: Double

    /// The "icon" half of the menu bar's "icon value" display. Temperature
    /// readings use their hardware-area icon (CPU/GPU/battery/etc.); fan and
    /// power readings use a fixed icon since they aren't broken down by area.
    var icon: String {
        switch kind {
        case .temperature: return category.icon
        case .fan: return "🌀"
        case .power: return "⚡"
        }
    }

    /// Sub-group label for the (often long) temperature list: known
    /// categories get their normal name; sensors without a curated name are
    /// clustered by their SMC key's own 2-letter prefix so related raw keys
    /// (e.g. TD00, TD01, TD02…) sit together instead of all landing in one
    /// big undifferentiated bucket.
    var temperatureGroupLabel: String {
        category != .other ? category.rawValue : String(key.prefix(2))
    }

    func formattedShort(unit: TemperatureUnit) -> String {
        kind.formatted(rawValue, unit: unit, precise: false)
    }

    func formattedPrecise(unit: TemperatureUnit) -> String {
        kind.formatted(rawValue, unit: unit, precise: true)
    }
}
