import SwiftUI

// MARK: - Core type

private enum CoreKind {
    case performance, efficiency, unknown
    var label: String { self == .performance ? "P" : self == .efficiency ? "E" : "—" }
    var tint: Color {
        switch self {
        case .performance: return TahoeTokens.Color.cpuTint
        case .efficiency:  return TahoeTokens.Color.memTint
        case .unknown:     return TahoeTokens.Color.cpuTint
        }
    }
}

// MARK: - CoreBarsView

struct CoreBarsView: View {
    let cores:     [Double]          // 0–100 per logical core
    let processes: [AppProcess]      // for per-core process panel

    @State private var selectedCore: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // P/E split from SystemInfo
    private var pCount: Int { max(SystemInfo.performanceCoreCount, 0) }
    private var eCount: Int { max(SystemInfo.efficiencyCoreCount, 0) }
    private var hasClusters: Bool { pCount > 0 && eCount > 0 }

    private func kind(for index: Int) -> CoreKind {
        guard hasClusters else { return .unknown }
        return index < pCount ? .performance : .efficiency
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            barsRow
            if hasClusters { clusterLegend }
            if let sel = selectedCore { coreDetailPanel(sel) }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.78), value: selectedCore)
    }

    // MARK: - Bars

    private var barsRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(cores.enumerated()), id: \.offset) { i, load in
                coreBarItem(index: i, load: load)
                if hasClusters && i == pCount - 1 && i < cores.count - 1 {
                    clusterSeparator
                }
            }
        }
        .frame(height: 96)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.72), value: cores)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selectedCore)
    }

    @ViewBuilder
    private func coreBarItem(index: Int, load: Double) -> some View {
        let isSelected = selectedCore == index
        let dimmed     = selectedCore != nil && !isSelected
        let k          = kind(for: index)
        let fill       = barFill(load: load, kind: k, dimmed: dimmed, selected: isSelected)
        coreBarBody(index: index, load: load, kind: k, dimmed: dimmed, fill: fill)
    }

    @ViewBuilder
    private func coreBarBody(index: Int, load: Double, kind k: CoreKind, dimmed: Bool, fill: Color) -> some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer()
                    RoundedRectangle(cornerRadius: TahoeTokens.Radius.bar, style: .continuous)
                        .fill(fill)
                        .frame(height: max(geo.size.height * load / 100, 2))
                }
            }
            coreLabel(index: index, kind: k, dimmed: dimmed)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { selectedCore = (selectedCore == index) ? nil : index }
        .accessibilityElement()
        .accessibilityLabel("Core \(index + 1) \(k.label)")
        .accessibilityValue(String(format: "%.0f%%", load))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func coreLabel(index: Int, kind k: CoreKind, dimmed: Bool) -> some View {
        VStack(spacing: 1) {
            Text("\(index + 1)")
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(dimmed ? Color.primary.opacity(0.2) : Color.primary.opacity(0.45))
            if hasClusters {
                Text(k.label)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(dimmed ? Color.primary.opacity(0.2) : k.tint.opacity(0.7))
            }
        }
    }

    private var clusterSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 4)
            .padding(.horizontal, 3)
    }

    // MARK: - Cluster legend

    private var clusterLegend: some View {
        HStack(spacing: 12) {
            legendDot(TahoeTokens.Color.cpuTint, label: "\(pCount) Performance")
                .tooltip("The big, fast cores. They handle demanding tasks like video exports, games, and anything that needs raw speed. They use more power but get things done faster.")
            legendDot(TahoeTokens.Color.memTint, label: "\(eCount) Efficiency")
                .tooltip("The small, power-sipping cores. They handle light background work — syncing, notifications, small tasks — so the performance cores can rest and save battery.")
            Spacer()
            if selectedCore != nil {
                Button {
                    selectedCore = nil
                } label: {
                    Text("Clear")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func legendDot(_ color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Per-core detail panel

    @ViewBuilder
    private func coreDetailPanel(_ index: Int) -> some View {
        let k     = kind(for: index)
        let load  = index < cores.count ? cores[index] : 0
        let label = hasClusters ? "Core \(index + 1) · \(k.label)-Core" : "Core \(index + 1)"

        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Circle().fill(k.tint).frame(width: 6, height: 6)
                Text(label)
                    .font(TahoeTokens.FontStyle.label)
                    .foregroundStyle(k.tint)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Spacer()
                Text(String(format: "%.0f%%", load))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider().opacity(0.35)

            // Context note
            let contextNote = k == .efficiency
                ? "Background & low-priority work"
                : "Active & high-priority work"
            Text(contextNote)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(.tertiary)
                .italic()

            // Top processes
            if processes.isEmpty {
                Text("No process data")
                    .font(TahoeTokens.FontStyle.body)
                    .foregroundStyle(.quaternary)
            } else {
                // Filter: P-cores → higher CPU processes, E-cores → lower
                let filtered = processesFor(coreKind: k)
                VStack(spacing: 4) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, p in
                        HStack(spacing: 6) {
                            Text("\(idx + 1)")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.quaternary)
                                .frame(width: 12, alignment: .trailing)
                            Text(p.name.isEmpty ? "—" : p.name)
                                .font(TahoeTokens.FontStyle.body)
                                .lineLimit(1)
                            Spacer()
                            // Mini inline bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.05))
                                    Capsule()
                                        .fill(k.tint.opacity(0.55))
                                        .frame(width: geo.size.width * min(p.cpuPercent / 100, 1))
                                }
                            }
                            .frame(width: 32, height: 4)
                            Text(String(format: "%.1f%%", p.cpuPercent))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(k.tint.opacity(0.9))
                                .frame(width: 36, alignment: .trailing)
                        }
                        if idx < filtered.count - 1 {
                            Divider().opacity(0.25)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: TahoeTokens.Radius.pill, style: .continuous)
                .fill(k.tint.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: TahoeTokens.Radius.pill, style: .continuous)
                        .strokeBorder(k.tint.opacity(0.15), lineWidth: 0.5)
                }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Helpers

    private func processesFor(coreKind: CoreKind) -> [AppProcess] {
        let sorted = processes.sorted { $0.cpuPercent > $1.cpuPercent }
        switch coreKind {
        case .performance:
            // High-CPU → P-core (top 5)
            return Array(sorted.filter { $0.cpuPercent >= 0.1 }.prefix(5))
        case .efficiency:
            // Low-CPU background → E-core (bottom of active set, but still non-zero)
            let active = sorted.filter { $0.cpuPercent > 0 }
            let low    = active.filter { $0.cpuPercent < 2.0 }
            return Array((low.isEmpty ? active : low).prefix(5))
        case .unknown:
            return Array(sorted.prefix(5))
        }
    }

    private func barFill(load: Double, kind: CoreKind, dimmed: Bool, selected: Bool) -> Color {
        if dimmed {
            return Color.primary.opacity(0.12 + load / 100 * 0.10)
        }
        let base: Color
        switch load {
        case ..<40:  base = kind.tint.opacity(0.45 + load / 100 * 0.40)
        case ..<75:  base = TahoeTokens.Color.pwrTint.opacity(0.55 + load / 100 * 0.35)
        default:     base = TahoeTokens.Color.danger.opacity(0.70 + load / 100 * 0.25)
        }
        return selected ? base.opacity(1.0) : base
    }
}
