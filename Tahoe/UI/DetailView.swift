import SwiftUI

// MARK: - Detail metric enum

enum DetailMetric: String, CaseIterable {
    case cpu, gpu, memory, power, disk, network, thermal
}

// MARK: - Tall history chart (Canvas-based)

struct HistoryChartView: View {
    let history:  [Double]   // 0–100 (normalised)
    let tint:     Color
    var maxValue: Double = 100   // for custom scales (e.g. watts, MB/s)
    var unit:     String = "%"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { ctx, size in
            guard history.count > 1 else { return }
            let w        = size.width
            let h        = size.height
            let maxCount = TahoeTokens.Timing.sparklineHistory
            let step     = w / Double(maxCount - 1)
            let offset   = maxCount - history.count

            // Grid lines at 25 / 50 / 75 %
            for pct in [0.25, 0.5, 0.75] {
                let y = h - pct * h * 0.88 - h * 0.06
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: w, y: y))
                ctx.stroke(grid, with: .color(.primary.opacity(0.07)), lineWidth: 0.5)
            }

            // Build line path
            var path = Path()
            for (i, v) in history.enumerated() {
                let norm = (v / maxValue).clamped(to: 0...1)
                let x    = Double(i + offset) * step
                let y    = h - norm * h * 0.88 - h * 0.06
                i == 0 ? path.move(to: CGPoint(x: x, y: y))
                       : path.addLine(to: CGPoint(x: x, y: y))
            }

            // Gradient fill
            var fill = path
            fill.addLine(to: CGPoint(x: w, y: h))
            fill.addLine(to: CGPoint(x: Double(offset) * step, y: h))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(tint.opacity(0.12)))

            // Stroke
            ctx.stroke(path, with: .color(tint.opacity(0.8)), lineWidth: 1.5)

            // Live dot
            if let last = history.last {
                let norm = (last / maxValue).clamped(to: 0...1)
                let lx   = w
                let ly   = h - norm * h * 0.88 - h * 0.06
                ctx.fill(
                    Path(ellipseIn: CGRect(x: lx - 3, y: ly - 3, width: 6, height: 6)),
                    with: .color(tint)
                )
            }
        }
        .frame(height: 80)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: history.count)
    }
}

// MARK: - Stats row (min / avg / max)

private struct StatsRow: View {
    let history: [Double]
    let unit:    String

    private var min: Double { history.min() ?? 0 }
    private var max: Double { history.max() ?? 0 }
    private var avg: Double { history.isEmpty ? 0 : history.reduce(0, +) / Double(history.count) }

    var body: some View {
        HStack(spacing: 0) {
            stat("Min", value: min)
            Spacer()
            stat("Avg", value: avg)
            Spacer()
            stat("Max", value: max)
        }
    }

    @ViewBuilder
    private func stat(_ label: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(TahoeTokens.FontStyle.label)
                .foregroundStyle(TahoeTokens.Color.textQuaternary)
                .textCase(.uppercase)
                .kerning(0.8)
            Text(String(format: "%.1f\(unit)", value))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(TahoeTokens.Color.textSecondary)
        }
    }
}

// MARK: - Per-metric detail view

struct DetailView: View {
    let metric: DetailMetric
    @EnvironmentObject var monitor: SystemMonitor
    @AppStorage("useFahrenheit") private var useFahrenheit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(title)
                    .font(TahoeTokens.FontStyle.label)
                    .foregroundStyle(tint)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Spacer()
                Text(currentValue)
                    .font(.system(size: 13, weight: .light, design: .default))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            // History chart
            HistoryChartView(history: normHistory, tint: tint, maxValue: maxValue, unit: unitStr)

            // Stats
            StatsRow(history: rawHistory, unit: unitStr)
                .padding(.top, 2)

            Divider().opacity(0.4)

            // Metric-specific breakdown
            breakdown
        }
        .padding(16)
        .frame(width: 280)
    }

    // MARK: - Metric routing

    private var title: String {
        switch metric {
        case .cpu:     return "CPU"
        case .gpu:     return "GPU"
        case .memory:  return "Memory"
        case .power:   return "Power"
        case .disk:    return "Disk I/O"
        case .network: return "Network"
        case .thermal: return "Thermals"
        }
    }

    private var tint: Color {
        switch metric {
        case .cpu:     return TahoeTokens.Color.cpuTint
        case .gpu:     return TahoeTokens.Color.gpuTint
        case .memory:  return TahoeTokens.Color.memTint
        case .power:   return TahoeTokens.Color.pwrTint
        case .disk:    return TahoeTokens.Color.diskTint
        case .network: return TahoeTokens.Color.netTint
        case .thermal: return TahoeTokens.Color.tempTint
        }
    }

    private var rawHistory: [Double] {
        switch metric {
        case .cpu:     return monitor.cpu.history
        case .gpu:     return monitor.gpu.history
        case .memory:  return monitor.memory.history
        case .power:   return monitor.power.history
        case .disk:    return monitor.disk.history
        case .network: return monitor.network.history
        case .thermal: return monitor.temperature.history
        }
    }

    // Normalised for the chart (0-100 scale)
    private var normHistory: [Double] { rawHistory }
    private var maxValue:    Double   {
        switch metric {
        case .cpu, .gpu, .memory: return 100
        case .power:   return max(monitor.power.history.max() ?? 50, 50)
        case .disk:    return max(monitor.disk.history.max() ?? 100, 100)
        case .network: return max(monitor.network.history.max() ?? 10, 10)
        case .thermal: return max(monitor.temperature.history.max() ?? 100, 100)
        }
    }
    private var unitStr: String {
        switch metric {
        case .cpu, .gpu, .memory: return "%"
        case .power:   return "W"
        case .disk, .network: return " MB/s"
        case .thermal: return "°C"
        }
    }
    private var currentValue: String {
        switch metric {
        case .cpu:     return "\(Int(monitor.cpu.total))%"
        case .gpu:     return "\(Int(monitor.gpu.utilization))%"
        case .memory:  return String(format: "%.1f GB", monitor.memory.usedGB)
        case .power:   return String(format: "%.1f W", monitor.power.totalWatts)
        case .disk:    return String(format: "%.1f MB/s", monitor.disk.readMBps + monitor.disk.writeMBps)
        case .network: return String(format: "↓%.1f ↑%.1f", monitor.network.downMBps, monitor.network.upMBps)
        case .thermal:
            return thermalHeadline
        }
    }

    // MARK: - Breakdown sections

    @ViewBuilder
    private var breakdown: some View {
        switch metric {
        case .cpu:     cpuBreakdown
        case .gpu:     gpuBreakdown
        case .memory:  memBreakdown
        case .power:   pwrBreakdown
        case .disk:    diskBreakdown
        case .network: netBreakdown
        case .thermal: thermalBreakdown
        }
    }

    private var cpuBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Core Load")
                .font(TahoeTokens.FontStyle.label).foregroundStyle(TahoeTokens.Color.textTertiary)
                .textCase(.uppercase).kerning(0.8)
            CoreBarsView(cores: monitor.cpu.cores, coreHistory: monitor.cpu.coreHistory, processes: monitor.processes, cpuTemp: monitor.temperature.cpuDie)
            if monitor.temperature.cpuDie > 0 {
                detailRow("Temperature", value: monitor.temperature.cpuDie.tempFormatted(fahrenheit: useFahrenheit), tint: TahoeTokens.Color.tempTint)
            }
        }
    }

    private var gpuBreakdown: some View {
        detailRow("GPU Cores", value: SystemInfo.gpuSubtitle, tint: tint)
    }

    private var memBreakdown: some View {
        VStack(spacing: 5) {
            detailRow("Wired",      value: String(format: "%.2f GB", monitor.memory.wiredGB),      tint: TahoeTokens.Color.cpuTint)
            detailRow("Active",     value: String(format: "%.2f GB", monitor.memory.activeGB),     tint: TahoeTokens.Color.memTint)
            detailRow("Inactive",   value: String(format: "%.2f GB", monitor.memory.inactiveGB),   tint: TahoeTokens.Color.textSecondary)
            detailRow("Compressed", value: String(format: "%.2f GB", monitor.memory.compressedGB), tint: TahoeTokens.Color.pwrTint)
        }
    }

    private var pwrBreakdown: some View {
        VStack(spacing: 5) {
            detailRow("CPU",   value: String(format: "%.1f W", monitor.power.cpuWatts), tint: TahoeTokens.Color.cpuTint)
            detailRow("GPU",   value: String(format: "%.1f W", monitor.power.gpuWatts), tint: TahoeTokens.Color.gpuTint)
            detailRow("ANE",   value: String(format: "%.1f W", monitor.power.aneWatts), tint: TahoeTokens.Color.memTint)
            detailRow("Total", value: String(format: "%.1f W", monitor.power.totalWatts), tint: tint)
        }
    }

    private var diskBreakdown: some View {
        VStack(spacing: 5) {
            detailRow("Read",  value: String(format: "%.2f MB/s", monitor.disk.readMBps),  tint: tint)
            detailRow("Write", value: String(format: "%.2f MB/s", monitor.disk.writeMBps), tint: tint.opacity(0.65))
        }
    }

    private var netBreakdown: some View {
        VStack(spacing: 5) {
            detailRow("Download", value: String(format: "%.2f MB/s", monitor.network.downMBps), tint: tint)
            detailRow("Upload",   value: String(format: "%.2f MB/s", monitor.network.upMBps),   tint: tint.opacity(0.65))
        }
    }

    private var thermalBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What these sensors mean")
                .font(TahoeTokens.FontStyle.label)
                .foregroundStyle(TahoeTokens.Color.textTertiary)
                .textCase(.uppercase)
                .kerning(0.8)

            if monitor.temperature.readings.isEmpty {
                Text("No thermal sensor metadata was available for this machine.")
                    .font(TahoeTokens.FontStyle.body)
                    .foregroundStyle(TahoeTokens.Color.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(monitor.temperature.readings) { reading in
                        thermalRow(reading)
                    }
                }
            }

            Divider().opacity(0.4)

            Text("Accuracy note")
                .font(TahoeTokens.FontStyle.label)
                .foregroundStyle(TahoeTokens.Color.textTertiary)
                .textCase(.uppercase)
                .kerning(0.8)

            Text("These labels are normalized categories. On Apple Silicon they come from IOHID temperature services; on Intel they come from SMC keys. 'Ambient' can mean case or internal air, not room temperature.")
                .font(TahoeTokens.FontStyle.body)
                .foregroundStyle(TahoeTokens.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func thermalRow(_ reading: TemperatureReading) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(tintForThermal(reading)).frame(width: 5, height: 5)
                Text(reading.label)
                    .font(TahoeTokens.FontStyle.body)
                    .foregroundStyle(TahoeTokens.Color.textPrimary)
                Spacer()
                Text(reading.value.tempFormatted(fahrenheit: useFahrenheit))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(TahoeTokens.Color.textPrimary)
            }
            Text(reading.meaning)
                .font(.system(size: 10))
                .foregroundStyle(TahoeTokens.Color.textSecondary)
            Text(reading.source)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(TahoeTokens.Color.textQuaternary)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tintForThermal(reading).opacity(0.06))
        }
    }

    private func tintForThermal(_ reading: TemperatureReading) -> Color {
        switch reading.kind {
        case .cpu: return TahoeTokens.Color.cpuTint
        case .gpu, .gpu2: return TahoeTokens.Color.gpuTint
        case .memory: return TahoeTokens.Color.memTint
        case .ambient: return TahoeTokens.Color.tempTint
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, value: String, tint: Color) -> some View {
        HStack {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(label).font(TahoeTokens.FontStyle.body).foregroundStyle(TahoeTokens.Color.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(TahoeTokens.Color.textPrimary)
        }
    }

    private var thermalHeadline: String {
        let values = [
            monitor.temperature.cpuDie,
            monitor.temperature.gpuDie,
            monitor.temperature.gpuDie2,
            monitor.temperature.memoryTemp,
            monitor.temperature.ambientTemp
        ].filter { $0 > 0 }
        guard let hottest = values.max() else { return "n/a" }
        return hottest.tempFormatted(fahrenheit: useFahrenheit)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
