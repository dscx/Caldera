import Foundation

/// A fan Caldera can override, discovered once at launch from its SMC
/// "F<n>Mn"/"F<n>Mx" bounds. `acKey` matches the corresponding
/// SensorReading (the live-speed row shown in the popover); `targetKey` is
/// the separate writable key Caldera actually writes to.
///
/// This Mac's SMC generation has no separate force-manual key — the classic
/// Intel "FS! " bitmask this app's ancestors relied on isn't present here —
/// so writing the target key directly is the entire override mechanism, and
/// its own thermal control loop reclaims the key the moment Caldera stops
/// rewriting it. That's why manual mode is "keep rewriting the target every
/// poll" rather than "write once and remember," and why it's never
/// persisted to UserDefaults: every launch starts in automatic, and quitting
/// (or crashing) just stops the rewrites rather than needing an explicit
/// "restore automatic" call. See SensorStore.pollOnce and .stop().
struct FanControlState: Equatable, Identifiable {
    var id: String { acKey }
    let acKey: String
    let targetKey: String
    let name: String
    let minRPM: Double
    let maxRPM: Double
    let dataType: UInt32
}
