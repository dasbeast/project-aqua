import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        VStack(spacing: 0) {
            metricRow(
                label:   "CPU",
                value:   "\(Int(monitor.cpu.total))%",
                history: monitor.cpu.history,
                tint:    TahoeTokens.Color.cpuTint
            )
            rowDivider
            metricRow(
                label:   "GPU",
                value:   "\(Int(monitor.gpu.utilization))%",
                history: monitor.gpu.history,
                tint:    TahoeTokens.Color.gpuTint
            )
            rowDivider
            metricRow(
                label:   "MEM",
                value:   String(format: "%.1f GB", monitor.memory.usedGB),
                history: monitor.memory.history,
                tint:    TahoeTokens.Color.memTint
            )
            rowDivider
            metricRow(
                label:   "NET",
                value:   netLabel,
                history: monitor.network.history,
                tint:    TahoeTokens.Color.cpuTint
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 230)
    }

    private var netLabel: String {
        let d = monitor.network.downMBps
        let u = monitor.network.upMBps
        return String(format: "↓%.1f ↑%.1f", d, u)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.horizontal, 4)
            .opacity(0.3)
    }

    @ViewBuilder
    private func metricRow(label: String, value: String, history: [Double], tint: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(label)
                .font(TahoeTokens.FontStyle.label)
                .foregroundStyle(.tertiary)
                .kerning(0.8)
                .frame(width: 28, alignment: .leading)
            SparklineView(history: history, tint: tint)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 4-dot menu bar label

struct MenuBarLabel: View {
    let cpu:    Double
    let gpu:    Double
    let memPct: Double
    let pwr:    Double

    var body: some View {
        HStack(spacing: 3) {
            dot(TahoeTokens.Color.cpuTint, load: cpu)
            dot(TahoeTokens.Color.gpuTint, load: gpu)
            dot(TahoeTokens.Color.memTint, load: memPct)
            dot(TahoeTokens.Color.pwrTint, load: min(pwr * 2, 100)) // scale: 50W → full
            Text("\(Int(cpu))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
    }

    private func dot(_ color: Color, load: Double) -> some View {
        Circle()
            .fill(color.opacity(0.3 + (load / 100) * 0.7))
            .frame(width: 7, height: 7)
    }
}
