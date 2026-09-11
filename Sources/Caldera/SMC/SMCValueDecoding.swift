import Foundation

/// Decodes a raw SMC value into a plain Double, based on its 4-character
/// data type. The caller (via MetricKind) is responsible for knowing what
/// unit that number is in — this layer only knows how to turn bytes into a
/// number.
///
/// Three wire formats are in play here:
/// - `flt ` (used by temperature/fan/power keys on Apple Silicon) is a
///   native-endian IEEE 754 float — read directly, no byte swap.
/// - `fpe2` (Intel-era fan speeds) is a big-endian 14.2 fixed point: divide
///   the big-endian 16-bit value by 4.
/// - The `spXY` fixed-point family (other Intel-era keys, X/Y are hex digit
///   bit-widths) is also big-endian on the wire and must be byte-swapped
///   before dividing by 2^Y.
/// Mixing up the endianness/format silently produces garbage, not a crash,
/// so the distinction matters.
func decodeSMCValue(dataType: UInt32, dataSize: UInt32, bytes: SMCBytes) -> Double? {
    let type = fourCharString(from: dataType)

    switch type {
    case "flt ":
        // Deliberately not `withUnsafeBytes(of:)` on the raw tuple here: under
        // release-mode optimization that pattern was observed to sometimes
        // read back zero instead of the real bytes. Plain bit-shifting avoids
        // the unsafe-pointer-to-tuple pattern entirely and is easy to verify.
        guard dataSize >= 4 else { return nil }
        let bits = UInt32(bytes.0) | (UInt32(bytes.1) << 8) | (UInt32(bytes.2) << 16) | (UInt32(bytes.3) << 24)
        let value = Float(bitPattern: bits)
        guard value.isFinite else { return nil }
        return Double(value)

    case "fpe2":
        guard dataSize >= 2 else { return nil }
        let raw = (UInt16(bytes.0) << 8) | UInt16(bytes.1)
        return Double(raw) / 4.0

    case "ui8 ":
        guard dataSize >= 1 else { return nil }
        return Double(bytes.0)

    case "si8 ":
        guard dataSize >= 1 else { return nil }
        return Double(Int8(bitPattern: bytes.0))

    case "ui16":
        guard dataSize >= 2 else { return nil }
        return Double((UInt16(bytes.0) << 8) | UInt16(bytes.1))

    case "si16":
        guard dataSize >= 2 else { return nil }
        let raw = (UInt16(bytes.0) << 8) | UInt16(bytes.1)
        return Double(Int16(bitPattern: raw))

    default:
        // The "spXY" fixed-point family: X = integer bits, Y = fractional bits,
        // both expressed as a single hex digit (e.g. "sp78" -> 8 fractional bits).
        guard type.hasPrefix("sp"), type.count == 4, dataSize >= 2 else { return nil }
        let fracChar = type[type.index(type.startIndex, offsetBy: 3)]
        guard let fracBits = fracChar.hexDigitValue else { return nil }
        let raw = (UInt16(bytes.0) << 8) | UInt16(bytes.1)
        return Double(Int16(bitPattern: raw)) / Double(1 << fracBits)
    }
}

struct DiscoveredSensor {
    let key: String
    let code: UInt32
    let kind: MetricKind
}

/// Enumerates every SMC key on this Mac and keeps the ones that map to a
/// known MetricKind, decode cleanly under a known numeric type, and read a
/// plausible value for that kind. Run once at launch — the key set is fixed
/// for the boot session, so there's no need to repeat the ~3,700-key scan on
/// every poll.
func discoverSensors(smc: SMC) -> [DiscoveredSensor] {
    guard let count = try? smc.keyCount() else { return [] }

    var found: [DiscoveredSensor] = []
    for index in 0..<count {
        guard let code = try? smc.keyCode(atIndex: index) else { continue }
        let keyStr = fourCharString(from: code)
        guard let kind = metricKind(forKey: keyStr) else { continue }
        guard let output = try? smc.readRaw(forCode: code) else { continue }
        guard let value = decodeSMCValue(
            dataType: output.dataType,
            dataSize: output.dataSize,
            bytes: output.bytes
        ) else { continue }
        guard kind.plausibleRange.contains(value) else { continue }
        found.append(DiscoveredSensor(key: keyStr, code: code, kind: kind))
    }
    return found
}
