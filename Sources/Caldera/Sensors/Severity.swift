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

    /// Higher = more severe. Used to pick the worst severity among a group
    /// of sensors collapsed into one averaged menu bar entry, so one hot
    /// outlier still reads as hot even if it's not dragging the average up.
    var rank: Int {
        switch self {
        case .normal: return 0
        case .warm: return 1
        case .hot: return 2
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
