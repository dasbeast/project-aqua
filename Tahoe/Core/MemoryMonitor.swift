import Darwin

struct MemoryState {
    var wiredGB:      Double = 0
    var activeGB:     Double = 0
    var inactiveGB:   Double = 0
    var compressedGB: Double = 0
    var swapUsedGB:   Double = 0
    var totalGB:      Double = MemoryMonitor.physicalMemoryGB
    var usedGB:       Double { wiredGB + activeGB + compressedGB }
    var history:      [Double] = []
}

final class MemoryMonitor {
    static let physicalMemoryGB: Double = {
        var size: UInt64 = 0
        var mib: [Int32] = [CTL_HW, HW_MEMSIZE]
        var len = MemoryLayout<UInt64>.size
        sysctl(&mib, 2, &size, &len, nil, 0)
        return Double(size) / (1024.0 * 1024.0 * 1024.0)
    }()

    func sample() -> MemoryState {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return MemoryState() }

        let page = Double(vm_page_size)
        let gb   = 1024.0 * 1024.0 * 1024.0

        var swapUsed: Double = 0
        var swapInfo = xsw_usage()
        var swapLen  = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swapInfo, &swapLen, nil, 0) == 0 {
            swapUsed = Double(swapInfo.xsu_used) / gb
        }

        return MemoryState(
            wiredGB:      Double(stats.wire_count)            * page / gb,
            activeGB:     Double(stats.active_count)          * page / gb,
            inactiveGB:   Double(stats.inactive_count)        * page / gb,
            compressedGB: Double(stats.compressor_page_count) * page / gb,
            swapUsedGB:   swapUsed
        )
    }
}
