import SwiftUI

struct ProcessListView: View {
    let processes: [AppProcess]

    private var sorted: [AppProcess] {
        Array(processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(10))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("CPU")
                    .frame(width: 46, alignment: .trailing)
                Text("Mem")
                    .frame(width: 52, alignment: .trailing)
            }
            .font(TahoeTokens.FontStyle.label)
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .kerning(0.8)
            .padding(.bottom, 7)

            ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, p in
                HStack(spacing: 0) {
                    // Rank badge
                    Text("\(idx + 1)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.quaternary)
                        .frame(width: 16, alignment: .leading)

                    Text(p.name.isEmpty ? "–" : p.name)
                        .font(TahoeTokens.FontStyle.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // CPU bar + value
                    HStack(spacing: 4) {
                        cpuBar(p.cpuPercent)
                        Text(String(format: "%.1f%%", p.cpuPercent))
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(cpuColor(p.cpuPercent))
                    }
                    .frame(width: 72, alignment: .trailing)

                    Text(memLabel(p.memoryGB))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
                .padding(.vertical, 4)

                if idx < sorted.count - 1 {
                    Divider().opacity(0.35)
                }
            }
        }
    }

    @ViewBuilder
    private func cpuBar(_ pct: Double) -> some View {
        let clamped = min(pct / 100, 1.0)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(cpuColor(pct).opacity(0.55))
                    .frame(width: geo.size.width * clamped)
            }
        }
        .frame(width: 28, height: 5)
        .animation(.easeOut(duration: 0.4), value: pct)
    }

    private func cpuColor(_ pct: Double) -> Color {
        switch pct {
        case ..<20:  return TahoeTokens.Color.cpuTint
        case ..<50:  return TahoeTokens.Color.warning
        default:     return TahoeTokens.Color.danger
        }
    }

    private func memLabel(_ gb: Double) -> String {
        gb >= 1.0 ? String(format: "%.2f G", gb)
                  : String(format: "%.0f M", gb * 1024)
    }
}
