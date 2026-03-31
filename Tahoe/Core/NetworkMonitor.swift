import Darwin
import Foundation

struct NetworkState {
    var downMBps: Double = 0
    var upMBps:   Double = 0
    var history:  [Double] = []
}

final class NetworkMonitor {
    private var prevIn:   UInt64 = 0
    private var prevOut:  UInt64 = 0
    private var prevTime: Date   = Date()

    func sample() -> NetworkState {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return NetworkState() }
        defer { freeifaddrs(first) }

        var bytesIn:  UInt64 = 0
        var bytesOut: UInt64 = 0
        var ptr = first
        repeat {
            let flags = Int32(ptr.pointee.ifa_flags)
            if ptr.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               flags & IFF_LOOPBACK == 0,
               flags & IFF_UP != 0,
               let namePtr = ptr.pointee.ifa_name,
               String(cString: namePtr).hasPrefix("en"),
               let data = ptr.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                bytesIn  += UInt64(data.pointee.ifi_ibytes)
                bytesOut += UInt64(data.pointee.ifi_obytes)
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        } while true

        let now     = Date()
        let elapsed = now.timeIntervalSince(prevTime)
        prevTime    = now

        let mbps = 1024.0 * 1024.0
        let down = elapsed > 0 && bytesIn  > prevIn  ? Double(bytesIn  - prevIn)  / elapsed / mbps : 0
        let up   = elapsed > 0 && bytesOut > prevOut ? Double(bytesOut - prevOut) / elapsed / mbps : 0
        prevIn  = bytesIn
        prevOut = bytesOut
        return NetworkState(downMBps: down, upMBps: up)
    }
}
