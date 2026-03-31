import IOKit

// MARK: - SMC temperature monitor
//
// Reads the Apple SMC via IOKit.  Works on Apple Silicon and Intel.
// Key "Tp01" = performance-cluster die temp (M-series).
// Key "TC0c" = CPU Core 0 die temp (Intel).
// Data type sp78: unsigned 8.8 fixed-point → temp = byte0 + byte1/256.

struct TemperatureState {
    var cpuDie:  Double = 0    // °C
    var history: [Double] = []
}

// Flat struct matching the C layout of SMCKeyData_t (76 bytes).
// Explicit _pad0 absorbs the 2-byte C alignment gap between SMCVersion
// (6 bytes, ends at offset 10) and SMCPLimitData (needs 4-byte align → starts at 12).
private struct SMCKeyData {
    var key:           UInt32 = 0   // offset  0
    var versMajor:     UInt8  = 0   // offset  4
    var versMinor:     UInt8  = 0   // offset  5
    var versBuild:     UInt8  = 0   // offset  6
    var versReserved:  UInt8  = 0   // offset  7
    var versRelease:   UInt16 = 0   // offset  8
    var _pad0:         UInt16 = 0   // offset 10  (alignment padding)
    var pLimVersion:   UInt16 = 0   // offset 12
    var pLimLength:    UInt16 = 0   // offset 14
    var cpuPLimit:     UInt32 = 0   // offset 16
    var gpuPLimit:     UInt32 = 0   // offset 20
    var memPLimit:     UInt32 = 0   // offset 24
    var dataSize:      UInt32 = 0   // offset 28
    var dataType:      UInt32 = 0   // offset 32
    var dataAttributes: UInt8 = 0   // offset 36
    var result:        UInt8  = 0   // offset 37
    var status:        UInt8  = 0   // offset 38
    var data8:         UInt8  = 0   // offset 39
    var data32:        UInt32 = 0   // offset 40
    var b0:  UInt8 = 0; var b1:  UInt8 = 0; var b2:  UInt8 = 0; var b3:  UInt8 = 0
    var b4:  UInt8 = 0; var b5:  UInt8 = 0; var b6:  UInt8 = 0; var b7:  UInt8 = 0
    var b8:  UInt8 = 0; var b9:  UInt8 = 0; var b10: UInt8 = 0; var b11: UInt8 = 0
    var b12: UInt8 = 0; var b13: UInt8 = 0; var b14: UInt8 = 0; var b15: UInt8 = 0
    var b16: UInt8 = 0; var b17: UInt8 = 0; var b18: UInt8 = 0; var b19: UInt8 = 0
    var b20: UInt8 = 0; var b21: UInt8 = 0; var b22: UInt8 = 0; var b23: UInt8 = 0
    var b24: UInt8 = 0; var b25: UInt8 = 0; var b26: UInt8 = 0; var b27: UInt8 = 0
    var b28: UInt8 = 0; var b29: UInt8 = 0; var b30: UInt8 = 0; var b31: UInt8 = 0
}   // total: 44 + 32 = 76 bytes

private enum SMCCmd: UInt8 {
    case getKeyInfo = 5
    case readKey    = 1
}

final class SMCMonitor {
    private var conn: io_connect_t = 0
    private var open = false

    // Prioritised key list.  Try each in order; use the first valid reading.
    // M-series: Tp01 (P-cluster), Tp09 (E-cluster).  Intel: TC0c, TC0D.
    private let tempKeys = ["Tp01", "Tp09", "Tp05", "TC0c", "TC0D", "TC0E"]

    init() { openSMC() }
    deinit { if open { IOServiceClose(conn) } }

    private func openSMC() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        open = IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess
    }

    func sample() -> TemperatureState {
        guard open else { return TemperatureState() }
        var readings: [Double] = []
        for key in tempKeys {
            if let t = readTemperature(key), t > 0, t < 150 {
                readings.append(t)
                if readings.count >= 2 { break }  // two sensors is enough
            }
        }
        let avg = readings.isEmpty ? 0.0 : readings.reduce(0, +) / Double(readings.count)
        return TemperatureState(cpuDie: avg)
    }

    // MARK: - Private

    private func readTemperature(_ key: String) -> Double? {
        // Step 1: kSMCGetKeyInfo → get dataSize
        var input  = SMCKeyData()
        var output = SMCKeyData()
        input.key  = fourCC(key)
        input.data8 = SMCCmd.getKeyInfo.rawValue
        guard callSMC(&input, &output), output.result == 0 else { return nil }
        let dataSize = output.dataSize

        // Step 2: kSMCReadKey → read bytes
        var input2  = SMCKeyData()
        var output2 = SMCKeyData()
        input2.key      = fourCC(key)
        input2.data8    = SMCCmd.readKey.rawValue
        input2.dataSize = dataSize
        guard callSMC(&input2, &output2), output2.result == 0 else { return nil }

        // sp78 decode: signed 8.8 fixed-point (temps are always positive)
        return Double(output2.b0) + Double(output2.b1) / 256.0
    }

    private func callSMC(_ input: inout SMCKeyData, _ output: inout SMCKeyData) -> Bool {
        var outSize = MemoryLayout<SMCKeyData>.stride
        let kr = IOConnectCallStructMethod(
            conn, UInt32(2),
            &input,  MemoryLayout<SMCKeyData>.stride,
            &output, &outSize
        )
        return kr == kIOReturnSuccess
    }

    private func fourCC(_ s: String) -> UInt32 {
        let b = Array(s.utf8)
        guard b.count == 4 else { return 0 }
        return UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
    }
}
