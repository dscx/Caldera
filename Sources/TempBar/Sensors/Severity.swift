import AppKit

/// How hot a temperature reading is relative to the (user-configurable)
/// alert threshold. Only temperature readings are classified — fan RPM and
/// power draw ranges vary too much by Mac model to guess sensible cutoffs.
enum Severity {
    case normal
    case warm
    case hot

    var nsColor: NSColor {
        switch self {
        case .normal: return .labelColor
        case .warm: return .systemOrange
        case .hot: return .systemRed
        }
    }
}

func severity(forCelsius celsius: Double, hotThreshold: Double) -> Severity {
    let warmThreshold = hotThreshold - 20
    if celsius >= hotThreshold { return .hot }
    if celsius >= warmThreshold { return .warm }
    return .normal
}

func severity(for reading: SensorReading, hotThresholdCelsius: Double) -> Severity {
    guard reading.kind == .temperature else { return .normal }
    return severity(forCelsius: reading.rawValue, hotThreshold: hotThresholdCelsius)
}
