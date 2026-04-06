import Foundation
import IOKit

struct GPUState {
    var utilization:  Double = 0    // overall device % (averaged across all GPUs)
    var tilerUtil:    Double = 0    // geometry/tiler %
    var rendererUtil: Double = 0    // renderer/shader %
    var gpuCount:     Int    = 0    // number of discrete GPU devices found
    var history:      [Double] = []
}

final class GPUMonitor {
    // Accumulated GPU time per IOKit entry (Apple Silicon IOGPU only).
    // Keyed by IORegistryEntryID so multiple GPUs are tracked independently.
    private var previousAccTime:   [UInt64: UInt64] = [:]
    private var previousSampleTime: CFAbsoluteTime?

    func sample() -> GPUState {
        let now = CFAbsoluteTimeGetCurrent()

        // Apple Silicon exposes GPU via "IOGPU".
        // Intel/AMD discrete GPUs register under "IOAccelerator" (superclass).
        // Try IOGPU first; if nothing found, fall back to IOAccelerator.
        var services = collectServices(matching: "IOGPU", requirePerfStats: false)
        if services.isEmpty {
            services = collectServices(matching: "IOAccelerator", requirePerfStats: true)
        }

        var utilReadings:     [Double] = []
        var tilerReadings:    [Double] = []
        var rendererReadings: [Double] = []
        var newAccTime = previousAccTime

        let elapsed = previousSampleTime.map { now - $0 } ?? -1

        for svc in services {
            let tiler    = Self.d(svc.stats?["Tiler Utilization %"])
            let renderer = Self.d(svc.stats?["Renderer Utilization %"])
            tilerReadings.append(tiler)
            rendererReadings.append(renderer)

            let util: Double
            if svc.isIOGPU, elapsed > 0, let prev = previousAccTime[svc.entryID] {
                // Preferred path for Apple Silicon: delta accumulated GPU nanoseconds.
                let delta = svc.accumulatedNs >= prev ? svc.accumulatedNs - prev : 0
                util = (Double(delta) / (elapsed * 1_000_000_000.0) * 100.0).clamped(to: 0...100)
            } else {
                // Intel/AMD (IOAccelerator) or first IOGPU sample: use PerformanceStatistics.
                util = Self.d(svc.stats?["Device Utilization %"]).clamped(to: 0...100)
            }

            newAccTime[svc.entryID] = svc.accumulatedNs
            utilReadings.append(util)
        }

        previousAccTime    = newAccTime
        previousSampleTime = now

        guard !utilReadings.isEmpty else { return GPUState() }

        let count = Double(utilReadings.count)
        return GPUState(
            utilization:  utilReadings.reduce(0, +) / count,
            tilerUtil:    tilerReadings.reduce(0, +) / count,
            rendererUtil: rendererReadings.reduce(0, +) / count,
            gpuCount:     utilReadings.count
        )
    }

    // MARK: - Service collection

    private struct ServiceInfo {
        let entryID:       UInt64
        let isIOGPU:       Bool
        let stats:         [String: Any]?
        let accumulatedNs: UInt64
    }

    private func collectServices(matching className: String, requirePerfStats: Bool) -> [ServiceInfo] {
        let matching = IOServiceMatching(className)
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iter) }

        var result: [ServiceInfo] = []
        var service = IOIteratorNext(iter)
        while service != 0 {
            var propsRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let props = propsRef?.takeRetainedValue() as? [String: Any] {
                let stats = props["PerformanceStatistics"] as? [String: Any]
                if !requirePerfStats || stats != nil {
                    var entryID: UInt64 = 0
                    IORegistryEntryGetRegistryEntryID(service, &entryID)
                    let accNs = className == "IOGPU" ? Self.totalAccumulatedNs(startingAt: service) : 0
                    result.append(ServiceInfo(
                        entryID:       entryID,
                        isIOGPU:       className == "IOGPU",
                        stats:         stats,
                        accumulatedNs: accNs
                    ))
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iter)
        }
        return result
    }

    // MARK: - Accumulated GPU time (Apple Silicon IOGPU only)

    private static func totalAccumulatedNs(startingAt service: io_registry_entry_t) -> UInt64 {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(
            service, kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively), &iterator
        ) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        var total: UInt64 = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var propsRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let props = propsRef?.takeRetainedValue() as? [String: Any],
               let appUsage = props["AppUsage"] as? [[String: Any]] {
                for usage in appUsage {
                    total += Self.u64(usage["accumulatedGPUTime"])
                }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return total
    }

    // MARK: - Type helpers

    private static func d(_ raw: Any?) -> Double {
        switch raw {
        case let v as Double:   return v
        case let v as NSNumber: return v.doubleValue
        default:                return 0
        }
    }

    private static func u64(_ raw: Any?) -> UInt64 {
        switch raw {
        case let v as UInt64:   return v
        case let v as Int:      return UInt64(max(v, 0))
        case let v as NSNumber: return v.uint64Value
        default:                return 0
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
