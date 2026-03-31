import Darwin
import Foundation

struct AppProcess: Identifiable {
    let id: Int32
    let name: String
    var cpuPercent: Double
    var memoryGB:   Double
}

final class ProcessMonitor {
    private var prevTimes: [Int32: UInt64] = [:]
    private var prevWall:  Date = Date()

    func sample() -> [AppProcess] {
        var pids = [Int32](repeating: 0, count: 1024)
        let count   = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        let now     = Date()
        let elapsed = now.timeIntervalSince(prevWall)
        prevWall    = now

        var result: [AppProcess] = []
        for i in 0..<Int(count) {
            let pid = pids[i]
            guard pid > 0 else { continue }
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }

            let name      = processName(pid)
            let totalTime = info.pti_total_user + info.pti_total_system
            let prev      = prevTimes[pid] ?? totalTime
            let delta     = totalTime > prev ? totalTime - prev : 0
            let cpuPct    = elapsed > 0 ? (Double(delta) / 1_000_000_000.0 / elapsed) * 100.0 : 0
            prevTimes[pid] = totalTime

            let memGB = Double(info.pti_resident_size) / (1024.0 * 1024.0 * 1024.0)
            result.append(AppProcess(
                id: pid,
                name: name,
                cpuPercent: min(cpuPct, 999),
                memoryGB: memGB
            ))
        }

        // Sort by memory so MemoryBreakdownView gets the heaviest consumers.
        // ProcessListView re-sorts by CPU when rendering.
        return result
            .sorted { $0.memoryGB > $1.memoryGB }
            .prefix(20)
            .map { $0 }
    }

    // Three-tier name resolution:
    //  1. proc_name   — reads pbi_name (2*MAXCOMLEN+1 = 33 chars), then pbi_comm (MAXCOMLEN+1)
    //  2. proc_pidpath — full executable path; extract last component for GUI/daemon bundles
    //  3. empty string — caller shows "–"
    private func processName(_ pid: Int32) -> String {
        var nameBuf = [CChar](repeating: 0, count: Int(2 * MAXCOMLEN) + 2)
        proc_name(pid, &nameBuf, UInt32(nameBuf.count))
        let name = String(cString: nameBuf)
        if !name.isEmpty { return name }

        var pathBuf = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_MAXSIZE = 4*MAXPATHLEN
        if proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count)) > 0 {
            let path = String(cString: pathBuf)
            if !path.isEmpty {
                return URL(fileURLWithPath: path).lastPathComponent
            }
        }
        return ""
    }
}
