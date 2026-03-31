import IOKit

struct GPUState {
    var utilization:  Double = 0    // overall device %
    var tilerUtil:    Double = 0    // geometry/tiler %
    var rendererUtil: Double = 0    // renderer/shader %
    var history:      [Double] = []
}

final class GPUMonitor {
    func sample() -> GPUState {
        let matching = IOServiceMatching("IOGPU")
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return GPUState()
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let props = propsRef?.takeRetainedValue() as? [String: Any],
               let stats = props["PerformanceStatistics"] as? [String: Any] {

                let overall   = stats["Device Utilization %"]   as? Double ?? 0
                let tiler     = stats["Tiler Utilization %"]    as? Double ?? 0
                let renderer  = stats["Renderer Utilization %"] as? Double ?? 0

                return GPUState(
                    utilization:  overall,
                    tilerUtil:    tiler,
                    rendererUtil: renderer
                )
            }
            service = IOIteratorNext(iter)
        }
        return GPUState()
    }
}
