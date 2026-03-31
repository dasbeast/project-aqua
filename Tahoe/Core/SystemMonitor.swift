import SwiftUI
import Combine
import Foundation

@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published var cpu          = CPUState()
    @Published var gpu          = GPUState()
    @Published var memory       = MemoryState()
    @Published var power        = PowerState()
    @Published var network      = NetworkState()
    @Published var disk         = DiskState()
    @Published var temperature  = TemperatureState()
    @Published var processes:   [AppProcess] = []
    @Published var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    private let cpuMon  = CPUMonitor()
    private let gpuMon  = GPUMonitor()
    private let memMon  = MemoryMonitor()
    private let pwrMon  = PowerMonitor()
    private let netMon  = NetworkMonitor()
    private let diskMon = DiskMonitor()
    private let smcMon  = SMCMonitor()
    private let procMon = ProcessMonitor()
    private let alerts  = AlertMonitor()

    private var timer:           DispatchSourceTimer?
    private var thermalObserver: Any?
    private var intervalObserver: AnyCancellable?
    private var currentInterval: TimeInterval = TahoeTokens.Timing.pollInterval

    private init() {
        AlertMonitor.requestPermission()
        start()
        observeThermal()
        observeInterval()
    }

    // MARK: - Snapshot for export

    func snapshot() -> String {
        """
        ── Tahoe Snapshot · \(Date().formatted(date: .abbreviated, time: .standard)) ──
        CPU      \(Int(cpu.total))%  (\(SystemInfo.cpuSubtitle))
        GPU      \(Int(gpu.utilization))%  (\(SystemInfo.gpuSubtitle))
        Memory   \(String(format: "%.2f", memory.usedGB)) / \(Int(memory.totalGB)) GB  (\(String(format: "%.0f", memory.usedGB / max(memory.totalGB,1) * 100))%)
          Wired       \(String(format: "%.2f", memory.wiredGB)) GB
          Active      \(String(format: "%.2f", memory.activeGB)) GB
          Inactive    \(String(format: "%.2f", memory.inactiveGB)) GB
          Compressed  \(String(format: "%.2f", memory.compressedGB)) GB
        Power    \(String(format: "%.1f", power.totalWatts)) W  (CPU \(String(format: "%.1f", power.cpuWatts)) · GPU \(String(format: "%.1f", power.gpuWatts)) · ANE \(String(format: "%.1f", power.aneWatts)))
        Disk     R \(String(format: "%.1f", disk.readMBps)) MB/s · W \(String(format: "%.1f", disk.writeMBps)) MB/s
        Network  ↓\(String(format: "%.2f", network.downMBps)) · ↑\(String(format: "%.2f", network.upMBps)) MB/s
        CPU Temp \(temperature.cpuDie > 0 ? String(format: "%.0f°C", temperature.cpuDie) : "n/a")
        ──────────────────────────────────────────
        """
    }

    // MARK: - Private

    private func start() {
        currentInterval = TahoeTokens.Timing.pollInterval
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now(), repeating: currentInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        var c     = cpuMon.sample()
        var g     = gpuMon.sample()
        var m     = memMon.sample()
        var p     = pwrMon.sample()
        var n     = netMon.sample()
        var d     = diskMon.sample()
        var temp  = smcMon.sample()
        let procs = procMon.sample()

        let memPct = m.usedGB / max(m.totalGB, 1) * 100

        // Alert check (background thread is fine for AlertMonitor)
        alerts.check(
            cpu:    c.total,
            memory: memPct,
            disk:   d.readMBps + d.writeMBps,
            power:  p.totalWatts,
            tempC:  temp.cpuDie
        )

        Task { @MainActor [self] in
            c.history    = Self.roll(self.cpu.history,         appending: c.total)
            g.history    = Self.roll(self.gpu.history,         appending: g.utilization)
            m.history    = Self.roll(self.memory.history,      appending: memPct)
            p.history    = Self.roll(self.power.history,       appending: p.totalWatts)
            n.history    = Self.roll(self.network.history,     appending: n.downMBps)
            d.history    = Self.roll(self.disk.history,        appending: d.readMBps + d.writeMBps)
            temp.history = Self.roll(self.temperature.history, appending: temp.cpuDie)

            withAnimation(.easeOut(duration: 0.35)) {
                self.cpu         = c
                self.gpu         = g
                self.memory      = m
                self.power       = p
                self.network     = n
                self.disk        = d
                self.temperature = temp
                self.processes   = procs
            }
        }
    }

    private func observeThermal() {
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.thermalState = ProcessInfo.processInfo.thermalState
        }
    }

    private func observeInterval() {
        // Watch UserDefaults for poll interval changes
        intervalObserver = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let new = TahoeTokens.Timing.pollInterval
                if abs(new - self.currentInterval) > 0.05 {
                    self.timer?.cancel()
                    self.start()
                }
            }
    }

    private static func roll(_ history: [Double], appending value: Double) -> [Double] {
        var h = history
        h.append(value)
        if h.count > TahoeTokens.Timing.sparklineHistory {
            h.removeFirst(h.count - TahoeTokens.Timing.sparklineHistory)
        }
        return h
    }
}
