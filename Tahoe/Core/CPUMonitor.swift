import Darwin

struct CPUState {
    var total:       Double     = 0
    var cores:       [Double]   = []
    var history:     [Double]   = []
    var coreHistory: [[Double]] = []
}

final class CPUMonitor {
    private var prevTicks: [processor_cpu_load_info] = []

    func sample() -> CPUState {
        var processorCount: natural_t = 0
        var cpuInfoArray: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0

        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfoArray,
            &cpuInfoCount
        )
        guard kr == KERN_SUCCESS, let info = cpuInfoArray else { return CPUState() }
        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        let numCores = Int(processorCount)
        let current: [processor_cpu_load_info] = (0..<numCores).map { i in
            (info + i * Int(CPU_STATE_MAX)).withMemoryRebound(to: processor_cpu_load_info.self, capacity: 1) {
                $0.pointee
            }
        }

        var coreLoads: [Double]
        if prevTicks.count == numCores {
            coreLoads = (0..<numCores).map { i in
                let prev = prevTicks[i]
                let cur  = current[i]
                let user = Double(cur.cpu_ticks.0) - Double(prev.cpu_ticks.0)
                let sys  = Double(cur.cpu_ticks.1) - Double(prev.cpu_ticks.1)
                let idle = Double(cur.cpu_ticks.2) - Double(prev.cpu_ticks.2)
                let nice = Double(cur.cpu_ticks.3) - Double(prev.cpu_ticks.3)
                let total = user + sys + idle + nice
                return total > 0 ? ((user + sys + nice) / total) * 100 : 0
            }
        } else {
            coreLoads = Array(repeating: 0, count: numCores)
        }
        prevTicks = current

        let aggregate = coreLoads.isEmpty ? 0 : coreLoads.reduce(0, +) / Double(coreLoads.count)
        return CPUState(total: aggregate, cores: coreLoads, history: [])
    }
}
