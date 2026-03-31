import Foundation
import IOKit

struct GPUState {
    var utilization:  Double = 0    // overall device %
    var tilerUtil:    Double = 0    // geometry/tiler %
    var rendererUtil: Double = 0    // renderer/shader %
    var history:      [Double] = []
}

final class GPUMonitor {
    private var previousAccumulatedGPUTime: UInt64?
    private var previousSampleTime: CFAbsoluteTime?

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
               let props = propsRef?.takeRetainedValue() as? [String: Any] {

                let stats = props["PerformanceStatistics"] as? [String: Any]
                let fallbackOverall = Self.doubleValue(stats?["Device Utilization %"])
                let tiler           = Self.doubleValue(stats?["Tiler Utilization %"])
                let renderer        = Self.doubleValue(stats?["Renderer Utilization %"])
                let utilization     = utilizationFromAccumulatedTime(startingAt: service) ?? fallbackOverall

                return GPUState(
                    utilization:  utilization,
                    tilerUtil:    tiler,
                    rendererUtil: renderer
                )
            }
            service = IOIteratorNext(iter)
        }
        return GPUState()
    }

    private func utilizationFromAccumulatedTime(startingAt service: io_registry_entry_t) -> Double? {
        let currentTotal = Self.totalAccumulatedGPUTime(startingAt: service)
        let now = CFAbsoluteTimeGetCurrent()

        defer {
            previousAccumulatedGPUTime = currentTotal
            previousSampleTime = now
        }

        guard
            let previousTotal = previousAccumulatedGPUTime,
            let previousTime = previousSampleTime
        else {
            return nil
        }

        let elapsedSeconds = now - previousTime
        guard elapsedSeconds > 0 else { return nil }

        let deltaTime = currentTotal >= previousTotal ? currentTotal - previousTotal : 0
        let utilization = (Double(deltaTime) / (elapsedSeconds * 1_000_000_000.0)) * 100.0

        return utilization.clamped(to: 0...100)
    }

    private static func totalAccumulatedGPUTime(startingAt service: io_registry_entry_t) -> UInt64 {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(service, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        var total: UInt64 = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var propsRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let props = propsRef?.takeRetainedValue() as? [String: Any],
               let appUsage = props["AppUsage"] as? [[String: Any]] {
                for usage in appUsage {
                    total += integerValue(usage["accumulatedGPUTime"])
                }
            }

            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }

        return total
    }

    private static func doubleValue(_ raw: Any?) -> Double {
        switch raw {
        case let value as Double:
            return value
        case let value as NSNumber:
            return value.doubleValue
        default:
            return 0
        }
    }

    private static func integerValue(_ raw: Any?) -> UInt64 {
        switch raw {
        case let value as UInt64:
            return value
        case let value as Int:
            return UInt64(max(value, 0))
        case let value as NSNumber:
            return value.uint64Value
        default:
            return 0
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
