import IOKit
import Foundation

struct DiskState {
    var readMBps:  Double = 0
    var writeMBps: Double = 0
    var history:   [Double] = []   // tracks (read+write) combined
}

final class DiskMonitor {
    private var prevRead:  UInt64 = 0
    private var prevWrite: UInt64 = 0
    private var prevTime:  Date   = Date()

    func sample() -> DiskState {
        var totalRead:  UInt64 = 0
        var totalWrite: UInt64 = 0

        let matching = IOServiceMatching("IOBlockStorageDriver")
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return DiskState()
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let props  = propsRef?.takeRetainedValue() as? [String: Any],
               let stats  = props["Statistics"] as? [String: Any] {
                if let n = stats["Bytes (Read)"]    as? NSNumber { totalRead  += n.uint64Value }
                if let n = stats["Bytes (Written)"] as? NSNumber { totalWrite += n.uint64Value }
            }
            service = IOIteratorNext(iter)
        }

        let now     = Date()
        let elapsed = now.timeIntervalSince(prevTime)
        prevTime    = now

        let mbps  = 1_048_576.0
        let read  = elapsed > 0 && totalRead  > prevRead  ? Double(totalRead  - prevRead)  / elapsed / mbps : 0
        let write = elapsed > 0 && totalWrite > prevWrite ? Double(totalWrite - prevWrite) / elapsed / mbps : 0
        prevRead  = totalRead
        prevWrite = totalWrite
        return DiskState(readMBps: read, writeMBps: write)
    }
}
