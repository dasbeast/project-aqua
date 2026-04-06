import Foundation
import IOKit

// MARK: - SMC temperature monitor
//
// Reads the Apple SMC via IOKit.  Works on Apple Silicon and Intel.
//
// Key naming conventions (for reference / fallback lists):
//   Tp__ = CPU cluster die temps (Apple Silicon — P/E clusters)
//   Tg__ = GPU die temps (Apple Silicon integrated — lowercase g)
//   TG__ = GPU die temps (Intel AMD discrete — uppercase G)
//   TC__ = CPU core/package (Intel)
//   Tm__ = Memory proximity (Apple Silicon)
//   TM__ = Memory (Intel)
//   TA__ / Ta__ = Ambient / case air
//
// Data type sp78: unsigned 8.8 fixed-point → temp = byte0 + byte1/256.

struct TemperatureState {
    var cpuDie:     Double = 0    // °C — CPU die / cluster average
    var gpuDie:     Double = 0    // °C — GPU 0 die (Tg__ AS or TG__ Intel)
    var gpuDie2:    Double = 0    // °C — GPU 1 die (dual-GPU Mac Pro 2013/2019)
    var memoryTemp: Double = 0    // °C — memory proximity
    var ambientTemp:Double = 0    // °C — ambient case air
    var readings:   [TemperatureReading] = []
    var history:    [Double] = []         // hottest sensor over time
    var cpuHistory:     [Double] = []
    var gpuHistory:     [Double] = []
    var memoryHistory:  [Double] = []
    var ambientHistory: [Double] = []
}

struct TemperatureReading: Identifiable {
    enum Kind: String {
        case cpu, gpu, gpu2, memory, ambient
    }

    let id = UUID()
    let kind: Kind
    let label: String
    let value: Double
    let source: String
    let meaning: String
}

// Flat struct matching the C layout of SMCKeyData_t (76 bytes).
private struct SMCKeyData {
    var key:           UInt32 = 0   // offset  0
    var versMajor:     UInt8  = 0   // offset  4
    var versMinor:     UInt8  = 0   // offset  5
    var versBuild:     UInt8  = 0   // offset  6
    var versReserved:  UInt8  = 0   // offset  7
    var versRelease:   UInt16 = 0   // offset  8
    var _pad0:         UInt16 = 0   // offset 10
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
    case getKeyInfo    = 5
    case readKey       = 1
    case getKeyByIndex = 8   // kSMCGetKeyFromIndex
}

// sp78 data-type FourCC: 's','p','7','8'
private let sp78Type: UInt32 = UInt32(ascii: "s") << 24
                             | UInt32(ascii: "p") << 16
                             | UInt32(ascii: "7") << 8
                             | UInt32(ascii: "8")

final class SMCMonitor {
    // HID path for Apple Silicon; SMC path for Intel.
    private let hid = AppleSiliconThermal()

    private var conn:   io_connect_t = 0
    private var isOpen = false

    // Keys discovered via SMC enumeration, grouped by sensor role.
    // Empty = enumeration failed or no keys found; sample() falls back to static lists.
    private var cpuKeys:     [String] = []
    private var gpuKeys:     [String] = []
    private var gpu2Keys:    [String] = []
    private var memoryKeys:  [String] = []
    private var ambientKeys: [String] = []

    init() {
        openSMC()
        if isOpen { discoverKeys() }
    }
    deinit { if isOpen { IOServiceClose(conn) } }

    // MARK: - Sample

    func sample() -> TemperatureState {
        let hidState = hid.isAvailable ? hid.sample() : TemperatureState()
        let smcState = readSMCState()

        // Prefer HID when available, but keep any non-zero SMC fallback values
        // so a partial sensor path still shows useful data.
        return TemperatureState(
            cpuDie:     coalesced(hidState.cpuDie,     smcState.cpuDie),
            gpuDie:     coalesced(hidState.gpuDie,     smcState.gpuDie),
            gpuDie2:    coalesced(hidState.gpuDie2,    smcState.gpuDie2),
            memoryTemp: coalesced(hidState.memoryTemp, smcState.memoryTemp),
            ambientTemp:coalesced(hidState.ambientTemp, smcState.ambientTemp),
            readings:   mergeReadings(hidState.readings, smcState.readings)
        )
    }

    private func readSMCState() -> TemperatureState {
        guard isOpen else { return TemperatureState() }
        let cpu = firstValid(cpuKeys.isEmpty     ? fallbackCPU     : cpuKeys)
        let gpu = firstValid(gpuKeys.isEmpty     ? fallbackGPU     : gpuKeys)
        let gpu2 = firstValid(gpu2Keys.isEmpty   ? fallbackGPU2    : gpu2Keys)
        let memory = firstValid(memoryKeys.isEmpty  ? fallbackMemory  : memoryKeys)
        let ambient = firstValid(ambientKeys.isEmpty ? fallbackAmbient : ambientKeys)
        return TemperatureState(
            cpuDie:     cpu.temp,
            gpuDie:     gpu.temp,
            gpuDie2:    gpu2.temp,
            memoryTemp: memory.temp,
            ambientTemp:ambient.temp,
            readings:   makeReadings(
                cpu: cpu.key.map { ($0, cpu.temp) },
                gpu: gpu.key.map { ($0, gpu.temp) },
                gpu2: gpu2.key.map { ($0, gpu2.temp) },
                memory: memory.key.map { ($0, memory.temp) },
                ambient: ambient.key.map { ($0, ambient.temp) },
                sourcePrefix: "SMC"
            )
        )
    }

    // MARK: - Key discovery

    /// Reads the total SMC key count (#KEY), then iterates with kSMCGetKeyFromIndex
    /// to find all temperature-type (sp78) keys and classify them by prefix.
    private func discoverKeys() {
        print("[SMC] discoverKeys() starting…")
        // Read total key count from the meta-key "#KEY" (returns ui32 big-endian).
        guard let cnt = readRawBytes("#KEY", verbose: true), cnt.count >= 4 else {
            print("[SMC] ⚠️ readRawBytes(#KEY) failed — trying fallback static lists")
            // Still try the fallback lists directly so we at least get one reading
            let testCPU = firstValid(fallbackCPU)
            print("[SMC] fallback CPU test: \(testCPU.temp > 0 ? String(format: "%.1f°C", testCPU.temp) : "no reading")")
            let testGPU = firstValid(fallbackGPU)
            print("[SMC] fallback GPU test: \(testGPU.temp > 0 ? String(format: "%.1f°C", testGPU.temp) : "no reading")")
            return
        }
        let total = UInt32(cnt[0]) << 24 | UInt32(cnt[1]) << 16
                  | UInt32(cnt[2]) << 8  | UInt32(cnt[3])
        print("[SMC] #KEY count = \(total)")
        guard total > 0 else { return }

        var found: [(name: String, role: Role)] = []

        for i in 0..<min(total, 1000) {
            // GetKeyFromIndex
            var ki = SMCKeyData(); var ko = SMCKeyData()
            ki.data8  = SMCCmd.getKeyByIndex.rawValue
            ki.data32 = UInt32(i)
            guard callSMC(&ki, &ko), ko.result == 0 else { continue }

            // Decode key name from the big-endian FourCC in output.key
            let k = ko.key
            guard k != 0 else { continue }
            let chars: [UInt8] = [
                UInt8((k >> 24) & 0xFF),
                UInt8((k >> 16) & 0xFF),
                UInt8((k >> 8)  & 0xFF),
                UInt8(k         & 0xFF),
            ]
            guard chars[0] == UInt8(ascii: "T"),
                  let name = String(bytes: chars, encoding: .ascii)
            else { continue }

            // Only care about sp78 (temperature) type
            var ii = SMCKeyData(); var oo = SMCKeyData()
            ii.key   = k
            ii.data8 = SMCCmd.getKeyInfo.rawValue
            guard callSMC(&ii, &oo), oo.result == 0, oo.dataType == sp78Type else { continue }

            if let role = classify(name) {
                found.append((name, role))
            }
        }

        // Populate groups in the order discovered (SMC returns keys in a stable order)
        cpuKeys     = found.filter { $0.role == .cpu     }.map(\.name)
        gpuKeys     = found.filter { $0.role == .gpu     }.map(\.name)
        gpu2Keys    = found.filter { $0.role == .gpu2    }.map(\.name)
        memoryKeys  = found.filter { $0.role == .memory  }.map(\.name)
        ambientKeys = found.filter { $0.role == .ambient }.map(\.name)

        print("[SMC] Discovered \(found.count) sp78 temp keys on this hardware:")
        for f in found { print("  \(f.name) → \(f.role)") }
        if found.isEmpty { print("[SMC] ⚠️ No sp78 keys found — using static fallback lists") }
        print("[SMC] CPU:\(cpuKeys) GPU:\(gpuKeys) Mem:\(memoryKeys) Amb:\(ambientKeys)")
    }

    private enum Role { case cpu, gpu, gpu2, memory, ambient }

    private func classify(_ name: String) -> Role? {
        let prefix = String(name.prefix(2))
        switch prefix {
        case "Tp", "TC": return .cpu
        case "Tg":       return .gpu          // Apple Silicon integrated GPU (lowercase g)
        case "TG":
            // Intel discrete GPU — distinguish GPU0 (TG0x) vs GPU1 (TG1x)
            let third = name.dropFirst(2).first
            return third == "1" ? .gpu2 : .gpu
        case "Tm", "TM", "TN": return .memory
        case "TA", "Ta":        return .ambient
        default: return nil
        }
    }

    // MARK: - Static fallback key lists
    // Used when GetKeyFromIndex is unavailable or returns nothing.

    private let fallbackCPU: [String] = [
        "Tp01", "Tp05", "Tp09",         // M1/M2/M3 P-cluster
        "Tp0D", "Tp0T", "Tp0b",         // M3 Pro/Max; M4 cluster variants
        "Tp0f", "Tp0j", "Tp0n", "Tp0r", // M-series Ultra / M4
        "Tp0X", "Tp0P",                  // Additional M4 candidates
        "TC0D", "TC0c", "TC0E",          // Intel CPU package
    ]
    private let fallbackGPU: [String] = [
        "Tg05", "Tg0D", "Tg0P",         // Apple Silicon integrated GPU (lowercase g)
        "Tg0S", "Tg0T", "Tg0b",         // Apple Silicon Pro/Max GPU
        "TG0D", "TG0P", "TGHP",          // Intel AMD discrete GPU 0
    ]
    private let fallbackGPU2: [String] = ["TG1D", "TG1P"]
    private let fallbackMemory: [String] = [
        "Tm0P", "Tm0Q",                  // Apple Silicon unified memory
        "TM0P", "TN0D",                  // Intel / other
    ]
    private let fallbackAmbient: [String] = [
        "TA0P", "TA0p",                  // Common ambient sensor
        "TaAP", "TaLP",                  // Mac Mini / Mac Pro enclosure
    ]

    // MARK: - SMC read helpers

    private func firstValid(_ keys: [String]) -> (key: String?, temp: Double) {
        for key in keys {
            if let t = readSp78(key), t > 0, t < 150 { return (key, t) }
        }
        return (nil, 0)
    }

    private func readSp78(_ key: String) -> Double? {
        guard let bytes = readRawBytes(key) else { return nil }
        return Double(bytes[0]) + Double(bytes[1]) / 256.0
    }

    /// Reads raw bytes for a key (first 4 data bytes). Returns nil on any failure.
    private func readRawBytes(_ key: String, verbose: Bool = false) -> [UInt8]? {
        var i1 = SMCKeyData(); var o1 = SMCKeyData()
        i1.key   = fourCC(key)
        i1.data8 = SMCCmd.getKeyInfo.rawValue
        let ok1  = callSMC(&i1, &o1)
        if verbose { print("[SMC]   \(key) getKeyInfo: ok=\(ok1) result=\(o1.result) dataSize=\(o1.dataSize)") }
        guard ok1, o1.result == 0 else { return nil }

        var i2 = SMCKeyData(); var o2 = SMCKeyData()
        i2.key      = fourCC(key)
        i2.data8    = SMCCmd.readKey.rawValue
        i2.dataSize = o1.dataSize
        let ok2     = callSMC(&i2, &o2)
        if verbose { print("[SMC]   \(key) readKey:    ok=\(ok2) result=\(o2.result) bytes=[\(o2.b0),\(o2.b1),\(o2.b2),\(o2.b3)]") }
        guard ok2, o2.result == 0 else { return nil }

        return [o2.b0, o2.b1, o2.b2, o2.b3]
    }

    // IOConnectCallStructMethod selector for the SMC "do command" method.
    // Historically selector 2 on Intel; some Apple Silicon / macOS 15 builds use 3.
    // Determined once at openSMC() time.
    private var smcSelector: UInt32 = 2

    private func callSMC(_ input: inout SMCKeyData, _ output: inout SMCKeyData) -> Bool {
        var outSize = MemoryLayout<SMCKeyData>.stride
        let kr = IOConnectCallStructMethod(
            conn, smcSelector,
            &input,  MemoryLayout<SMCKeyData>.stride,
            &output, &outSize
        )
        return kr == kIOReturnSuccess
    }

    private func openSMC() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            print("[SMC] ❌ AppleSMC service not found in IORegistry")
            return
        }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == kIOReturnSuccess else {
            print("[SMC] ❌ IOServiceOpen failed — kr=0x\(String(kr, radix: 16))")
            return
        }
        isOpen = true

        // Probe which IOConnectCallStructMethod selector responds to a simple
        // getKeyInfo call. Selector 2 is standard on Intel; Apple Silicon /
        // macOS 15 may use a different index.
        smcSelector = probeSelector() ?? 2
        print("[SMC] ✅ SMC opened — using selector \(smcSelector)")
    }

    /// Tries selectors 2, 3, 4 with a benign getKeyInfo probe.
    /// Returns the first one that gives kIOReturnSuccess, or nil if none work.
    private func probeSelector() -> UInt32? {
        // Use a well-known key ("ACID" = always present) as the probe key.
        // We don't care about the result value, just whether the call succeeds.
        let probeKey = fourCC("ACID")
        for sel in UInt32(2)...UInt32(4) {
            var input  = SMCKeyData()
            var output = SMCKeyData()
            input.key   = probeKey
            input.data8 = SMCCmd.getKeyInfo.rawValue
            var outSize = MemoryLayout<SMCKeyData>.stride
            let kr = IOConnectCallStructMethod(
                conn, sel,
                &input,  MemoryLayout<SMCKeyData>.stride,
                &output, &outSize
            )
            print("[SMC]   selector \(sel) probe → kr=0x\(String(kr, radix: 16)) result=\(output.result)")
            if kr == kIOReturnSuccess {
                return sel
            }
        }
        return nil
    }

    private func fourCC(_ s: String) -> UInt32 {
        let b = Array(s.utf8)
        guard b.count == 4 else { return 0 }
        return UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
    }

    private func coalesced(_ primary: Double, _ fallback: Double) -> Double {
        primary > 0 ? primary : fallback
    }

    private func mergeReadings(_ primary: [TemperatureReading], _ fallback: [TemperatureReading]) -> [TemperatureReading] {
        let primaryKinds = Set(primary.map(\.kind))
        return primary + fallback.filter { !primaryKinds.contains($0.kind) }
    }

    private func makeReadings(
        cpu: (String, Double)?,
        gpu: (String, Double)?,
        gpu2: (String, Double)?,
        memory: (String, Double)?,
        ambient: (String, Double)?,
        sourcePrefix: String
    ) -> [TemperatureReading] {
        var result: [TemperatureReading] = []
        if let cpu, cpu.1 > 0 { result.append(reading(kind: .cpu, label: "CPU", value: cpu.1, source: "\(sourcePrefix) \(cpu.0)", meaning: "CPU die or cluster temperature")) }
        if let gpu, gpu.1 > 0 { result.append(reading(kind: .gpu, label: "GPU", value: gpu.1, source: "\(sourcePrefix) \(gpu.0)", meaning: "Primary GPU die temperature")) }
        if let gpu2, gpu2.1 > 0 { result.append(reading(kind: .gpu2, label: "GPU 1", value: gpu2.1, source: "\(sourcePrefix) \(gpu2.0)", meaning: "Secondary GPU die temperature")) }
        if let memory, memory.1 > 0 { result.append(reading(kind: .memory, label: "Memory", value: memory.1, source: "\(sourcePrefix) \(memory.0)", meaning: "Memory or unified-memory proximity temperature")) }
        if let ambient, ambient.1 > 0 { result.append(reading(kind: .ambient, label: "Ambient", value: ambient.1, source: "\(sourcePrefix) \(ambient.0)", meaning: "Case or internal air temperature, not room temperature")) }
        return result
    }

    private func reading(kind: TemperatureReading.Kind, label: String, value: Double, source: String, meaning: String) -> TemperatureReading {
        TemperatureReading(kind: kind, label: label, value: value, source: source, meaning: meaning)
    }
}

private extension UInt32 {
    init(ascii c: Character) { self = c.asciiValue.map(UInt32.init) ?? 0 }
}

// MARK: - Temperature formatting

extension Double {
    /// Formats a Celsius value as "52°C" or "126°F" depending on the flag.
    func tempFormatted(fahrenheit: Bool) -> String {
        fahrenheit
            ? String(format: "%.0f°F", self * 9 / 5 + 32)
            : String(format: "%.0f°C", self)
    }

    /// Converts Celsius to Fahrenheit.
    var toFahrenheit: Double { self * 9 / 5 + 32 }
}
