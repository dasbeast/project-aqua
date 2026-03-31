# Project Aqua — macOS System Monitor

> **UI target:** Version Tahoe (bubbly, tinted glass cards, spring animations, warm + clean)
> **Reference UI:** Version Capitan (iOS 7 / El Capitan — frosted glass, 200-weight numerals) — keep for A/B toggle if desired

---

## Overview

A native macOS system monitor app. Beautiful, always-on, feels like it belongs on a power user's desktop. Displays CPU, GPU, memory, power draw, per-core load, process list, and network I/O. Ships with a compact menu bar widget.

**Platform:** macOS 14 Sonoma minimum  
**Language:** Swift 5.9+  
**Framework:** SwiftUI + AppKit (where needed for IOKit/Mach bridging)  
**No third-party UI frameworks**

---

## Project Structure

```
Tahoe.xcodeproj
└── Tahoe/
    ├── App/
    │   └── TahoeApp.swift
    ├── Core/
    │   ├── SystemMonitor.swift
    │   ├── CPUMonitor.swift
    │   ├── GPUMonitor.swift
    │   ├── MemoryMonitor.swift
    │   ├── PowerMonitor.swift
    │   ├── ProcessMonitor.swift
    │   └── NetworkMonitor.swift
    ├── UI/
    │   ├── DashboardView.swift
    │   ├── HeroCardView.swift
    │   ├── CoreBarsView.swift
    │   ├── MemoryBreakdownView.swift
    │   ├── ProcessListView.swift
    │   ├── SparklineView.swift
    │   └── MenuBarView.swift
    └── Design/
        └── TahoeTokens.swift
```

---

## Design Tokens — `TahoeTokens.swift`

```swift
import SwiftUI

enum TahoeTokens {
    enum Color {
        static let cpuTint   = SwiftUI.Color(red: 0.04, green: 0.48, blue: 1.0)
        static let gpuTint   = SwiftUI.Color(red: 0.55, green: 0.31, blue: 0.78)
        static let memTint   = SwiftUI.Color(red: 0.19, green: 0.69, blue: 0.31)
        static let pwrTint   = SwiftUI.Color(red: 0.94, green: 0.47, blue: 0.13)
        static let danger    = SwiftUI.Color(red: 0.91, green: 0.21, blue: 0.17)
        static let warning   = SwiftUI.Color(red: 1.0,  green: 0.58, blue: 0.0)
    }
    enum Radius {
        static let window: CGFloat = 24
        static let card: CGFloat   = 20
        static let pill: CGFloat   = 12
        static let bar: CGFloat    = 6
    }
    enum FontStyle {
        static let heroValue = SwiftUI.Font.system(size: 36, weight: .light,     design: .default)
        static let heroUnit  = SwiftUI.Font.system(size: 14, weight: .regular,   design: .default)
        static let label     = SwiftUI.Font.system(size: 10, weight: .semibold,  design: .default)
        static let body      = SwiftUI.Font.system(size: 11, weight: .regular,   design: .default)
        static let pill      = SwiftUI.Font.system(size: 10, weight: .medium,    design: .default)
    }
    enum Timing {
        static let pollInterval: TimeInterval = 1.0
        static let sparklineHistory = 36        // samples kept per metric
    }
}
```

---

## Data Layer

### `SystemMonitor.swift`

The single source of truth. All views bind to this one object.

```swift
import SwiftUI
import Combine

@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published var cpu     = CPUState()
    @Published var gpu     = GPUState()
    @Published var memory  = MemoryState()
    @Published var power   = PowerState()
    @Published var network = NetworkState()
    @Published var processes: [ProcessInfo] = []

    private let cpuMon  = CPUMonitor()
    private let gpuMon  = GPUMonitor()
    private let memMon  = MemoryMonitor()
    private let pwrMon  = PowerMonitor()
    private let netMon  = NetworkMonitor()
    private let procMon = ProcessMonitor()

    private var timer: DispatchSourceTimer?

    private init() { start() }

    private func start() {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now(), repeating: TahoeTokens.Timing.pollInterval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let c = self.cpuMon.sample()
            let g = self.gpuMon.sample()
            let m = self.memMon.sample()
            let p = self.pwrMon.sample()
            let n = self.netMon.sample()
            let procs = self.procMon.sample()
            Task { @MainActor in
                self.cpu      = c
                self.gpu      = g
                self.memory   = m
                self.power    = p
                self.network  = n
                self.processes = procs
            }
        }
        t.resume()
        timer = t
    }
}
```

---

### `CPUMonitor.swift`

```swift
import Darwin

struct CPUState {
    var total: Double = 0           // 0–100 aggregate
    var cores: [Double] = []        // per-core 0–100
    var history: [Double] = []      // rolling 36-sample history of total
}

final class CPUMonitor {
    private var prevTicks: [processor_cpu_load_info] = []

    func sample() -> CPUState {
        var count: mach_msg_type_number_t = 0
        var cpuInfo: processor_info_array_t?
        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &count,
            &cpuInfo,
            &count
        )
        guard kr == KERN_SUCCESS, let info = cpuInfo else { return CPUState() }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(count))
        }

        let stride = MemoryLayout<processor_cpu_load_info>.stride
        let numCores = Int(count) / stride
        var current: [processor_cpu_load_info] = (0..<numCores).map { i in
            info.advanced(by: i).withMemoryRebound(to: processor_cpu_load_info.self, capacity: 1) { $0.pointee }
        }

        var coreLoads: [Double] = []
        if prevTicks.count == numCores {
            for i in 0..<numCores {
                let prev = prevTicks[i]
                let cur  = current[i]
                let user   = Double(cur.cpu_ticks.0) - Double(prev.cpu_ticks.0)
                let sys    = Double(cur.cpu_ticks.1) - Double(prev.cpu_ticks.1)
                let idle   = Double(cur.cpu_ticks.2) - Double(prev.cpu_ticks.2)
                let nice   = Double(cur.cpu_ticks.3) - Double(prev.cpu_ticks.3)
                let total  = user + sys + idle + nice
                coreLoads.append(total > 0 ? ((user + sys + nice) / total) * 100 : 0)
            }
        } else {
            coreLoads = Array(repeating: 0, count: numCores)
        }
        prevTicks = current

        let aggregate = coreLoads.isEmpty ? 0 : coreLoads.reduce(0, +) / Double(coreLoads.count)
        // NOTE: history management lives in SystemMonitor — append aggregate there
        return CPUState(total: aggregate, cores: coreLoads, history: [])
    }
}
```

---

### `GPUMonitor.swift`

```swift
import IOKit

struct GPUState {
    var utilization: Double = 0     // 0–100
    var history: [Double] = []
}

final class GPUMonitor {
    func sample() -> GPUState {
        var util = 0.0
        let matching = IOServiceMatching("IOGPU")
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return GPUState()
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service) }
            if let props = IORegistryEntryCreateCFProperties(service, nil, kCFAllocatorDefault, 0)
                .takeRetainedValue() as? [String: Any],
               let stats = props["PerformanceStatistics"] as? [String: Any],
               let pct = stats["Device Utilization %"] as? Double {
                util = pct
                break
            }
            service = IOIteratorNext(iter)
        }
        return GPUState(utilization: util, history: [])
    }
}
```

---

### `MemoryMonitor.swift`

```swift
import Darwin

struct MemoryState {
    var wiredGB:      Double = 0
    var activeGB:     Double = 0
    var inactiveGB:   Double = 0
    var compressedGB: Double = 0
    var totalGB:      Double = 0
    var usedGB:       Double { wiredGB + activeGB + compressedGB }
    var history:      [Double] = []
}

final class MemoryMonitor {
    func sample() -> MemoryState {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return MemoryState() }

        let page = Double(vm_page_size)
        let gb   = 1024.0 * 1024.0 * 1024.0
        return MemoryState(
            wiredGB:      Double(stats.wire_count)       * page / gb,
            activeGB:     Double(stats.active_count)     * page / gb,
            inactiveGB:   Double(stats.inactive_count)   * page / gb,
            compressedGB: Double(stats.compressor_page_count) * page / gb,
            totalGB:      36.0   // read from sysctl hw.memsize in production
        )
    }
}
```

---

### `PowerMonitor.swift`

Uses `IOKit` to read Apple Silicon's `AppleARMPMU` power registers. This is the same path iStatMenus uses — technically private but stable across M1/M2/M3.

```swift
import IOKit

struct PowerState {
    var cpuWatts: Double = 0
    var gpuWatts: Double = 0
    var aneWatts: Double = 0
    var totalWatts: Double { cpuWatts + gpuWatts + aneWatts }
    var history: [Double] = []
}

final class PowerMonitor {
    // Uses IOReport channels — see implementation notes below
    func sample() -> PowerState {
        // Full implementation requires IOReportCreateSamples / IOReportCreateSamplesDelta
        // which are private but linkable. Stub returning zeros until linked.
        // Reference: https://github.com/nicowillis/powermetrics-swift
        return PowerState(cpuWatts: 0, gpuWatts: 0, aneWatts: 0)
    }
}
// IMPLEMENTATION NOTE: For a working power monitor on Apple Silicon, use
// the `powermetrics` approach — spawn `sudo powermetrics --samplers cpu_power
// -n 1 --format plist` and parse the output. This avoids private API linkage
// entirely and is what most indie apps do. Requires an entitlement or helper tool.
```

---

### `ProcessMonitor.swift`

```swift
import Darwin

struct ProcessInfo: Identifiable {
    let id: Int32           // PID
    let name: String
    var cpuPercent: Double
    var memoryGB:   Double
}

final class ProcessMonitor {
    private var prevTimes: [Int32: UInt64] = [:]
    private var prevWall:  Date = Date()

    func sample() -> [ProcessInfo] {
        var pids = [Int32](repeating: 0, count: 1024)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        let elapsed = Date().timeIntervalSince(prevWall)
        prevWall = Date()

        var result: [ProcessInfo] = []
        for i in 0..<Int(count) {
            let pid = pids[i]
            var info = proc_taskinfo()
            let size = MemoryLayout<proc_taskinfo>.size
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(size)) == size else { continue }

            let name = processName(pid)
            let totalTime = info.pti_total_user + info.pti_total_system
            let prev = prevTimes[pid] ?? totalTime
            let delta = totalTime > prev ? totalTime - prev : 0
            let cpuPct = elapsed > 0 ? (Double(delta) / 1_000_000_000.0 / elapsed) * 100.0 : 0
            prevTimes[pid] = totalTime

            let memGB = Double(info.pti_resident_size) / (1024 * 1024 * 1024)
            result.append(ProcessInfo(id: pid, name: name, cpuPercent: min(cpuPct, 100), memoryGB: memGB))
        }

        return result.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(8).map { $0 }
    }

    private func processName(_ pid: Int32) -> String {
        var name = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
        proc_name(pid, &name, UInt32(name.count))
        return String(cString: name)
    }
}
```

---

### `NetworkMonitor.swift`

```swift
import Darwin

struct NetworkState {
    var downMBps: Double = 0
    var upMBps:   Double = 0
    var history:  [Double] = []
}

final class NetworkMonitor {
    private var prevIn:  UInt64 = 0
    private var prevOut: UInt64 = 0
    private var prevTime: Date  = Date()

    func sample() -> NetworkState {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return NetworkState() }
        defer { freeifaddrs(first) }

        var bytesIn: UInt64 = 0; var bytesOut: UInt64 = 0
        var ptr = first
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            if ptr.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               flags & IFF_LOOPBACK == 0, flags & IFF_UP != 0,
               let name = ptr.pointee.ifa_name, String(cString: name).hasPrefix("en") {
                if let data = ptr.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    bytesIn  += UInt64(data.pointee.ifi_ibytes)
                    bytesOut += UInt64(data.pointee.ifi_obytes)
                }
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        let elapsed = Date().timeIntervalSince(prevTime)
        prevTime = Date()
        let down = elapsed > 0 ? Double(bytesIn  > prevIn  ? bytesIn  - prevIn  : 0) / elapsed / (1024*1024) : 0
        let up   = elapsed > 0 ? Double(bytesOut > prevOut ? bytesOut - prevOut : 0) / elapsed / (1024*1024) : 0
        prevIn = bytesIn; prevOut = bytesOut
        return NetworkState(downMBps: down, upMBps: up)
    }
}
```

---

## UI Layer

### `SparklineView.swift`

```swift
import SwiftUI

struct SparklineView: View {
    let history: [Double]       // values 0–100
    let tint: Color
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        Canvas { ctx, size in
            guard history.count > 1 else { return }
            let w = size.width, h = size.height
            let step = w / Double(history.count - 1)

            var path = Path()
            for (i, v) in history.enumerated() {
                let x = Double(i) * step
                let y = h - (v / 100.0) * h * 0.82 - h * 0.09
                i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
            }
            ctx.stroke(path, with: .color(tint.opacity(0.7)), lineWidth: 1.2)

            // Fill
            var fill = path
            fill.addLine(to: CGPoint(x: w, y: h))
            fill.addLine(to: CGPoint(x: 0, y: h))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(tint.opacity(0.1)))

            // End dot
            if let last = history.last {
                let lx = w, ly = h - (last / 100.0) * h * 0.82 - h * 0.09
                let dot = Path(ellipseIn: CGRect(x: lx-2.5, y: ly-2.5, width: 5, height: 5))
                ctx.fill(dot, with: .color(tint.opacity(0.85)))
            }
        }
        .frame(height: 28)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: history.count)
    }
}
```

---

### `HeroCardView.swift`

```swift
import SwiftUI

struct HeroCardView: View {
    let label: String
    let value: String
    let unit: String
    let subtitle: String
    let tint: Color
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(TahoeTokens.FontStyle.label)
                .foregroundStyle(tint.opacity(0.7))
                .kerning(0.8)
                .textCase(.uppercase)
                .padding(.bottom, 4)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(TahoeTokens.FontStyle.heroValue)
                    .foregroundStyle(.primary)
                Text(unit)
                    .font(TahoeTokens.FontStyle.heroUnit)
                    .foregroundStyle(.secondary)
                    .baselineOffset(12)
            }

            Text(subtitle)
                .font(TahoeTokens.FontStyle.body)
                .foregroundStyle(.tertiary)

            SparklineView(history: history, tint: tint)
                .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: TahoeTokens.Radius.card, style: .continuous)
                .fill(tint.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: TahoeTokens.Radius.card, style: .continuous)
                        .strokeBorder(tint.opacity(0.15), lineWidth: 0.5)
                }
                // Top-edge shimmer — the "lickable" highlight
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: TahoeTokens.Radius.card, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.6), .clear],
                                startPoint: .top, endPoint: .init(x: 0.5, y: 0.3)
                            )
                        )
                }
        }
        .shadow(color: tint.opacity(0.08), radius: 8, y: 2)
        .contentShape(Rectangle())
        .scaleEffect(1.0)
        .hoverEffect(.lift)   // macOS pointer lift on hover
    }
}
```

---

### `CoreBarsView.swift`

```swift
import SwiftUI

struct CoreBarsView: View {
    let cores: [Double]     // 0–100 per core

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(cores.enumerated()), id: \.offset) { i, load in
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            Spacer()
                            RoundedRectangle(cornerRadius: TahoeTokens.Radius.bar, style: .continuous)
                                .fill(coreColor(load))
                                .frame(height: geo.size.height * load / 100)
                        }
                    }
                    Text("\(i + 1)")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 56)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: cores)
    }

    private func coreColor(_ load: Double) -> Color {
        switch load {
        case ..<40:  return TahoeTokens.Color.cpuTint.opacity(0.4  + load/100 * 0.45)
        case ..<75:  return TahoeTokens.Color.pwrTint.opacity(0.55 + load/100 * 0.35)
        default:     return TahoeTokens.Color.danger.opacity(0.7   + load/100 * 0.25)
        }
    }
}
```

---

### `DashboardView.swift`

```swift
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        VStack(spacing: 12) {
            // Hero row
            HStack(spacing: 10) {
                HeroCardView(
                    label: "CPU", value: "\(Int(monitor.cpu.total))", unit: "%",
                    subtitle: "M3 Pro · 12 cores",
                    tint: TahoeTokens.Color.cpuTint,
                    history: monitor.cpu.history
                )
                HeroCardView(
                    label: "GPU", value: "\(Int(monitor.gpu.utilization))", unit: "%",
                    subtitle: "18-core · unified",
                    tint: TahoeTokens.Color.gpuTint,
                    history: monitor.gpu.history
                )
                HeroCardView(
                    label: "Memory", value: String(format: "%.1f", monitor.memory.usedGB), unit: "GB",
                    subtitle: "\(Int(monitor.memory.usedGB / monitor.memory.totalGB * 100))% of \(Int(monitor.memory.totalGB)) GB",
                    tint: TahoeTokens.Color.memTint,
                    history: monitor.memory.history
                )
                HeroCardView(
                    label: "Power", value: String(format: "%.1f", monitor.power.totalWatts), unit: "W",
                    subtitle: "CPU package",
                    tint: TahoeTokens.Color.pwrTint,
                    history: monitor.power.history
                )
            }

            // Cores + Memory breakdown
            HStack(spacing: 10) {
                panelCard {
                    CoreBarsView(cores: monitor.cpu.cores)
                } label: "Cores" tag: "avg \(Int(monitor.cpu.cores.reduce(0,+) / Double(max(monitor.cpu.cores.count,1))))%"

                panelCard {
                    MemoryBreakdownView(state: monitor.memory)
                } label: "Memory" tag: "36 GB unified"
            }

            // Process list
            panelCard {
                ProcessListView(processes: monitor.processes)
            } label: "Processes" tag: "by CPU"
        }
        .padding(18)
        .frame(width: 480)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func panelCard<Content: View>(
        @ViewBuilder content: () -> Content,
        label: String,
        tag: String
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(TahoeTokens.FontStyle.label).foregroundStyle(.tertiary).textCase(.uppercase).kerning(0.8)
                Spacer()
                Text(tag).font(TahoeTokens.FontStyle.pill).foregroundStyle(.tertiary)
                    .padding(.horizontal, 9).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Capsule())
            }
            .padding(.bottom, 14)
            content()
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: TahoeTokens.Radius.card, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: TahoeTokens.Radius.card, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
        }
    }
}
```

---

### `TahoeApp.swift`

```swift
import SwiftUI

@main
struct TahoeApp: App {
    @StateObject private var monitor = SystemMonitor.shared

    var body: some Scene {
        // Main window — fixed width, no resize
        WindowGroup {
            DashboardView()
                .environmentObject(monitor)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 560)

        // Menu bar widget
        MenuBarExtra {
            MenuBarView()
                .environmentObject(monitor)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                Text("\(Int(monitor.cpu.total))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)
    }
}
```

---

## Build Order

Work through these in sequence — don't start UI until the data layer is solid.

1. **`CPUMonitor`** — build, run, `print()` core loads every second. Verify numbers match Activity Monitor.
2. **`MemoryMonitor`** — same verification against Activity Monitor.
3. **`GPUMonitor`** — verify against GPU History in Activity Monitor.
4. **`NetworkMonitor`** — verify against the Network pane.
5. **`ProcessMonitor`** — verify top processes match Activity Monitor.
6. **`PowerMonitor`** — implement via `powermetrics` subprocess or IOReport. Verify against `sudo powermetrics --samplers cpu_power -n 1`.
7. **`SystemMonitor`** — wire all monitors together, add history rolling logic.
8. **`SparklineView`** — build in isolation with mock data in Xcode Preview.
9. **`HeroCardView`** — build with mock data.
10. **`CoreBarsView`** — build with mock data, tune spring animation.
11. **`DashboardView`** — assemble all components with live `SystemMonitor`.
12. **Window chrome** — `NSVisualEffectView` bridging if `.regularMaterial` isn't enough.
13. **`MenuBarView`** — compact 4-dot indicator + CPU%.
14. **Polish** — thermal state color shifting, `prefersReducedMotion`, launch-at-login via `SMAppService`.

---

## Key Implementation Notes

**History management** — each monitor returns raw current values. `SystemMonitor` is responsible for appending to history arrays and trimming to `TahoeTokens.Timing.sparklineHistory` (36 samples). Do not manage history inside individual monitors.

**Threading** — all monitors sample on a background `DispatchQueue`. All `@Published` updates must be dispatched to `@MainActor`. Use `Task { @MainActor in ... }` inside the timer handler.

**Power on Apple Silicon** — the cleanest public approach is spawning `powermetrics` as a subprocess with `--format plist` and parsing the output. This requires the app to request elevated privileges or ship a privileged helper tool via `SMJobBless`. An alternative is linking against IOReport privately — stable but technically unsupported.

**Window always-on-top** — set `NSWindow.level = .floating` via `NSWindowDelegate` or a `NSViewRepresentable` shim if the user wants the monitor to float above other apps.

**Thermal state integration:**
```swift
NotificationCenter.default.addObserver(
    forName: ProcessInfo.thermalStateDidChangeNotification,
    object: nil, queue: .main
) { _ in
    let state = ProcessInfo.processInfo.thermalState
    // shift window background tint toward amber at .serious, red at .critical
}
```

---

## Entitlements Required

```xml
<!-- Tahoe.entitlements -->
<key>com.apple.security.app-sandbox</key><false/>
<!-- Disable sandbox to allow IOKit + proc_* access -->
<!-- For Mac App Store distribution, sandbox must be re-enabled
     and privileged operations moved to a helper tool -->
```

---

*Project Aqua — Version Tahoe UI*
