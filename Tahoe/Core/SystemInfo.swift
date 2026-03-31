import Darwin
import IOKit

/// Static hardware facts read once at launch.
enum SystemInfo {

    // MARK: - CPU / Chip

    /// e.g. "M3 Pro" (strips the "Apple " prefix)
    static let chipName: String = {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Apple Silicon" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        let raw = String(cString: buf)                          // "Apple M3 Pro"
        return raw.hasPrefix("Apple ") ? String(raw.dropFirst(6)) : raw
    }()

    static let logicalCoreCount: Int = {
        var n: Int32 = 0
        var len = MemoryLayout<Int32>.size
        sysctlbyname("hw.logicalcpu", &n, &len, nil, 0)
        return Int(n)
    }()

    static let performanceCoreCount: Int = {
        var n: Int32 = 0
        var len = MemoryLayout<Int32>.size
        // Apple Silicon exposes this via hw.perflevel0.logicalcpu
        sysctlbyname("hw.perflevel0.logicalcpu", &n, &len, nil, 0)
        return Int(n)
    }()

    static let efficiencyCoreCount: Int = {
        var n: Int32 = 0
        var len = MemoryLayout<Int32>.size
        sysctlbyname("hw.perflevel1.logicalcpu", &n, &len, nil, 0)
        return Int(n)
    }()

    // MARK: - GPU

    /// GPU core count read from IOKit IOGPU, or 0 if unavailable.
    static let gpuCoreCount: Int = {
        let matching = IOServiceMatching("IOGPU")
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let props = propsRef?.takeRetainedValue() as? [String: Any],
               let n = props["gpu-core-count"] as? Int {
                return n
            }
            service = IOIteratorNext(iter)
        }
        return 0
    }()

    // MARK: - Formatted subtitles

    static var cpuSubtitle: String {
        let p = performanceCoreCount
        let e = efficiencyCoreCount
        if p > 0, e > 0 {
            return "\(chipName) · \(p)P+\(e)E"
        }
        let total = logicalCoreCount
        return total > 0 ? "\(chipName) · \(total)-core" : chipName
    }

    static var gpuSubtitle: String {
        let n = gpuCoreCount
        return n > 0 ? "\(n)-core · unified" : "Integrated · unified"
    }
}
