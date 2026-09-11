import Foundation

/// The three kinds of live SMC readings this app surfaces. Each has its own
/// discovery rule (which keys count as this kind), plausible value range for
/// filtering out garbage reads, and display format — but they all flow
/// through the same generic SMC decode/poll/pin machinery.
enum MetricKind: String, CaseIterable {
    case temperature
    case fan
    case power

    var sectionTitle: String {
        switch self {
        case .temperature: return "Temperatures"
        case .fan: return "Fans"
        case .power: return "Power"
        }
    }

    var plausibleRange: ClosedRange<Double> {
        switch self {
        case .temperature: return -5...150
        case .fan: return 0...10000
        case .power: return 0...500
        }
    }

    func formatted(_ rawValue: Double, unit: TemperatureUnit, precise: Bool) -> String {
        switch self {
        case .temperature:
            let converted = unit.convert(fromCelsius: rawValue)
            return precise ? String(format: "%.1f%@", converted, unit.symbol) : String(format: "%.0f%@", converted, unit.symbol)
        case .fan:
            return String(format: "%.0f RPM", rawValue)
        case .power:
            return precise ? String(format: "%.2fW", rawValue) : String(format: "%.1fW", rawValue)
        }
    }
}

/// Curated: unlike temperature/fan, most SMC "P"-prefixed keys are noisy
/// per-rail sub-components rather than meaningful readings for a general
/// user, so power uses an allowlist instead of broad prefix discovery.
private let curatedPowerKeys: Set<String> = ["PSTR", "PPBR", "PDTR"]

/// Which metric kind a raw SMC key belongs to, if any — nil means "not a
/// key this app surfaces" (most of the ~3,700 keys on a modern Mac).
func metricKind(forKey key: String) -> MetricKind? {
    if key.hasPrefix("T") {
        return .temperature
    }
    // Fan keys are 4 chars: 'F' + fan index + 2-letter suffix. Only "Ac"
    // (actual live RPM) is a live reading — Tg/Mn/Mx/Md/Num are
    // targets/limits/config, not sensor data, and would otherwise show up
    // as bogus "fan readings" of a handful of RPM.
    if key.hasPrefix("F"), key.count == 4, key.hasSuffix("Ac") {
        return .fan
    }
    if curatedPowerKeys.contains(key) {
        return .power
    }
    return nil
}
