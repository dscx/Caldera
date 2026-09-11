import IOKit

// Layout mirrors the AppleSMC user-client's expected wire struct exactly.
// This is not Apple API — it's the long-standing reverse-engineered protocol
// used by SMCKit, smcFanControl, and other SMC tools. Field order and types
// matter: this struct is passed as a raw byte buffer to IOConnectCallStructMethod,
// so any change to field order/types changes the byte layout the kernel reads.

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfoData {
    // Intentionally UInt32, not IOByteCount: IOByteCount resolves to UInt64
    // on this SDK/arch, but the AppleSMC user client's wire struct expects a
    // 4-byte field here — confirmed empirically (an 8-byte field makes the
    // driver reject every call with kIOReturnBadArgument).
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

let smcZeroBytes: SMCBytes = (
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0
)

struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    // Confirmed empirically against the running AppleSMC driver: without this
    // 2-byte pad the whole struct is 4 bytes short of the 80 the driver
    // validates against, and every call is rejected with kIOReturnBadArgument.
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = smcZeroBytes
}

enum SMCSelector: UInt8 {
    case handleYPCEvent = 2
    case readKey = 5
    case writeKey = 6
    case getKeyFromIndex = 8
    case getKeyInfo = 9
}

enum SMCReturnCode: UInt8 {
    case success = 0
    case keyNotFound = 132
}

enum SMCError: Error {
    case driverNotFound
    case failedToOpen(kern: kern_return_t)
    case callFailed(kern: kern_return_t)
    case keyError(result: UInt8, key: String)
}

func fourCharCode(from string: String) -> UInt32 {
    string.utf8.prefix(4).reduce(UInt32(0)) { sum, byte in
        (sum << 8) | UInt32(byte)
    }
}

func fourCharString(from code: UInt32) -> String {
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xFF),
        UInt8((code >> 16) & 0xFF),
        UInt8((code >> 8) & 0xFF),
        UInt8(code & 0xFF)
    ]
    return String(bytes: bytes, encoding: .ascii) ?? "????"
}
