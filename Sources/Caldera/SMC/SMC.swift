import IOKit

/// Low-level access to the Apple System Management Controller.
///
/// Reading SMC keys does not require elevated privileges or special
/// entitlements — it just requires the app not to be sandboxed, since the
/// App Sandbox blocks IOKit user-client connections to "AppleSMC".
final class SMC {
    private var connection: io_connect_t = 0

    func open() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            throw SMCError.driverNotFound
        }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        guard result == kIOReturnSuccess else {
            throw SMCError.failedToOpen(kern: result)
        }
    }

    func close() {
        guard connection != 0 else { return }
        IOServiceClose(connection)
        connection = 0
    }

    @discardableResult
    private func call(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
        var output = SMCParamStruct()
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let kr = IOConnectCallStructMethod(
            connection,
            UInt32(SMCSelector.handleYPCEvent.rawValue),
            &input,
            inputSize,
            &output,
            &outputSize
        )
        guard kr == kIOReturnSuccess else {
            throw SMCError.callFailed(kern: kr)
        }
        guard output.result == SMCReturnCode.success.rawValue else {
            throw SMCError.keyError(result: output.result, key: fourCharString(from: input.key))
        }
        return output
    }

    /// Total number of keys the SMC exposes on this Mac (read via the "#KEY" pseudo-key).
    func keyCount() throws -> Int {
        let output = try readRaw(forCode: fourCharCode(from: "#KEY"))
        let b = output.bytes
        let n = (UInt32(b.0) << 24) | (UInt32(b.1) << 16) | (UInt32(b.2) << 8) | UInt32(b.3)
        return Int(n)
    }

    /// The 4-character key code stored at a given SMC key index (0..<keyCount()).
    func keyCode(atIndex index: Int) throws -> UInt32 {
        var input = SMCParamStruct()
        input.data8 = SMCSelector.getKeyFromIndex.rawValue
        input.data32 = UInt32(index)
        let output = try call(&input)
        return output.key
    }

    private func keyInfo(forCode code: UInt32) throws -> SMCKeyInfoData {
        var input = SMCParamStruct()
        input.key = code
        input.data8 = SMCSelector.getKeyInfo.rawValue
        let output = try call(&input)
        return output.keyInfo
    }

    /// Reads the raw value + type info for a key, given its 4-character code.
    ///
    /// The type/size only come back populated on the getKeyInfo response —
    /// the readKey response's own `keyInfo` field is not populated by the
    /// driver, so both calls are needed and the type info must be carried
    /// over from the first one.
    func readRaw(forCode code: UInt32) throws -> SMCReading {
        let info = try keyInfo(forCode: code)
        var input = SMCParamStruct()
        input.key = code
        input.keyInfo.dataSize = info.dataSize
        input.data8 = SMCSelector.readKey.rawValue
        let output = try call(&input)
        return SMCReading(dataType: info.dataType, dataSize: info.dataSize, bytes: output.bytes)
    }
}

struct SMCReading {
    let dataType: UInt32
    let dataSize: UInt32
    let bytes: SMCBytes
}
