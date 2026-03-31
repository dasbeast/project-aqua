import SwiftUI

/// Full-width panel showing live network ↓/↑ and disk R/W side by side.
struct NetworkDiskView: View {
    let network: NetworkState
    let disk:    DiskState

    var body: some View {
        HStack(spacing: 24) {
            metricGroup(
                title:   "Network",
                rows: [
                    MetricRow(label: "↓ Down", value: bwLabel(network.downMBps), tint: TahoeTokens.Color.netTint, history: network.history),
                    MetricRow(label: "↑ Up",   value: bwLabel(network.upMBps),   tint: TahoeTokens.Color.netTint.opacity(0.65), history: []),
                ]
            )

            Divider()
                .padding(.vertical, 4)
                .opacity(0.35)

            metricGroup(
                title:   "Disk I/O",
                rows: [
                    MetricRow(label: "Read",  value: bwLabel(disk.readMBps),  tint: TahoeTokens.Color.diskTint, history: disk.history),
                    MetricRow(label: "Write", value: bwLabel(disk.writeMBps), tint: TahoeTokens.Color.diskTint.opacity(0.65), history: []),
                ]
            )
        }
    }

    // MARK: - Subviews

    private struct MetricRow {
        let label:   String
        let value:   String
        let tint:    Color
        let history: [Double]
    }

    @ViewBuilder
    private func metricGroup(title: String, rows: [MetricRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Mini sparkline for the primary row
            if let primary = rows.first, !primary.history.isEmpty {
                SparklineView(history: primary.history, tint: primary.tint)
            }

            VStack(spacing: 5) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Circle()
                            .fill(row.tint)
                            .frame(width: 5, height: 5)
                        Text(row.label)
                            .font(TahoeTokens.FontStyle.body)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(row.value)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func bwLabel(_ mbps: Double) -> String {
        mbps >= 100  ? String(format: "%.0f MB/s",  mbps)
      : mbps >= 1    ? String(format: "%.1f MB/s",  mbps)
                     : String(format: "%.0f KB/s",  mbps * 1024)
    }
}
