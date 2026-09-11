import Foundation

enum SensorCategory: String, CaseIterable {
    case cpu = "CPU"
    case gpu = "GPU"
    case battery = "Battery"
    case system = "System"
    case other = "Other"

    /// The "icon" half of the menu bar's "icon::value" display.
    var icon: String {
        switch self {
        case .cpu: return "💻"
        case .gpu: return "🎮"
        case .battery: return "🔋"
        case .system: return "🖥️"
        case .other: return "🌡️"
        }
    }
}

/// Friendly names for SMC keys that are stable and well documented — almost
/// entirely long-standing Intel-era keys. Apple Silicon temperature key
/// *names* are known to shift meaning between chip generations (even the
/// maintainers of popular open-source sensor apps have documented the same
/// key meaning different things on M1 vs M2), so unmapped keys intentionally
/// fall back to their raw SMC code rather than guessing a label.
enum SensorCatalog {
    private static let knownSensors: [String: (name: String, category: SensorCategory)] = [
        "TC0P": ("CPU Proximity", .cpu),
        "TC0D": ("CPU Die", .cpu),
        "TC0E": ("CPU 1", .cpu),
        "TC0F": ("CPU 2", .cpu),
        "TCXC": ("CPU PECI", .cpu),
        "TG0P": ("GPU Proximity", .gpu),
        "TG0D": ("GPU Die", .gpu),
        "TA0P": ("Ambient", .system),
        "TA1P": ("Ambient 2", .system),
        "TH0P": ("Heatsink", .system),
        "TM0P": ("Memory", .system),
        "TS0P": ("Palm Rest", .system),
        "TB0T": ("Battery", .battery),
        "TB1T": ("Battery 2", .battery),
        "TB2T": ("Battery 3", .battery),
        "TW0P": ("Airport / Wireless", .system),
        "F0Ac": ("Fan 1", .system),
        "F1Ac": ("Fan 2", .system),
        "F2Ac": ("Fan 3", .system),
        "PSTR": ("Total System Power", .system),
        "PPBR": ("Battery Power", .battery),
        "PDTR": ("Adapter Power", .system),
    ]

    /// Prefixes that reliably mean the same broad area across both Intel and
    /// Apple Silicon Macs, even where the exact key isn't in the curated
    /// table above — e.g. every "TC*" key observed (curated or not) is some
    /// flavor of CPU-area sensor. This is deliberately coarse: it's enough
    /// to group related unknown sensors together, not to claim which
    /// specific core/component a key measures.
    private static let inferredCategoryByPrefix: [String: SensorCategory] = [
        "TC": .cpu,
        "TG": .gpu,
        "TB": .battery,
        "TA": .system,
        "TH": .system,
        "TM": .system,
        "TS": .system,
        "TW": .system,
    ]

    static func name(for key: String) -> String {
        knownSensors[key]?.name ?? key
    }

    static func category(for key: String) -> SensorCategory {
        if let known = knownSensors[key] { return known.category }
        return inferredCategoryByPrefix[String(key.prefix(2))] ?? .other
    }

    /// For CPU-category keys that aren't individually curated above: Apple's
    /// own SMC key scheme has no fixed meaning across Mac models — confirmed
    /// via the Linux kernel's Apple Silicon SMC driver discussion, which
    /// describes the FourCC keys as "almost random" between devices, with no
    /// way to enumerate or deduce which physical core/component one measures.
    /// Inventing a specific name (e.g. "P-core 3") would just be a confident
    /// guess that could be flat wrong. A stable "CPU Sensor N" — numbered by
    /// sorted key, so it stays the same across launches on this Mac — is
    /// more approachable than a raw 4-character code without overclaiming.
    static func assignDescriptiveNames(for keys: [String]) -> [String: String] {
        let uncuratedCPUKeys = keys.filter { knownSensors[$0] == nil && category(for: $0) == .cpu }.sorted()
        var result: [String: String] = [:]
        for (index, key) in uncuratedCPUKeys.enumerated() {
            result[key] = "CPU Sensor \(index + 1)"
        }
        return result
    }
}
