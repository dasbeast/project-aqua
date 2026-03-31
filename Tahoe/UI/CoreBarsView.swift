import SwiftUI

// MARK: - Core type

private enum CoreKind {
    case performance, efficiency, unknown
    var label: String { self == .performance ? "P" : self == .efficiency ? "E" : "Core" }
    var tint: Color {
        switch self {
        case .performance: return TahoeTokens.Color.cpuTint
        case .efficiency:  return TahoeTokens.Color.memTint
        case .unknown:     return TahoeTokens.Color.textSecondary
        }
    }
}

// MARK: - CoreBarsView

struct CoreBarsView: View {
    let cores:       [Double]       // 0–100 per logical core
    let coreHistory: [[Double]]     // rolling history per core
    let processes:   [AppProcess]

    @State private var selectedCore: Int?  = nil
    @State private var expanded:     Bool  = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func kind(for index: Int) -> CoreKind {
        .unknown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            barsRow
            if expanded    { expandedSection }
            if let sel = selectedCore { coreDetailPanel(sel) }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.78), value: selectedCore)
        .animation(reduceMotion ? nil : .spring(response: 0.5,  dampingFraction: 0.80), value: expanded)
    }

    // MARK: - Bars row

    private var barsRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(cores.enumerated()), id: \.offset) { i, load in
                coreBarItem(index: i, load: load)
            }
        }
        .frame(height: expanded ? 130 : 96)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.72), value: cores)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selectedCore)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { expanded.toggle(); selectedCore = nil }
        .onTapGesture(count: 1) { }   // absorbs single tap so double-tap fires correctly
        .overlay(alignment: .topTrailing) {
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(TahoeTokens.Color.textQuaternary)
                .padding(4)
                .allowsHitTesting(false)
        }
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
                .foregroundStyle(dimmed ? TahoeTokens.Color.textMuted : TahoeTokens.Color.textSecondary)
        }
    }

    // MARK: - Expanded section

    private var expandedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryStatsRow
            Divider().opacity(0.3)
            coreSparklineGrid
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // Summary: P avg, E avg, busiest core
    private var summaryStatsRow: some View {
        HStack(spacing: 0) {
            summaryCell(
                label: "Core Avg",
                value: overallAverage,
                tint:  TahoeTokens.Color.cpuTint
            )
            Spacer()
            summaryCell(
                label: "Core Count",
                value: "\(cores.count)",
                tint:  TahoeTokens.Color.memTint
            )
            Spacer()
            summaryCell(
                label: "Busiest",
                value: busiestCore,
                tint:  TahoeTokens.Color.pwrTint
            )
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func summaryCell(label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(TahoeTokens.Color.textQuaternary)
                .textCase(.uppercase)
                .kerning(0.6)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(tint)
        }
    }

    // Per-core mini sparklines
    private var coreSparklineGrid: some View {
        let cols = min(cores.count, 4)
        let rows = Int(ceil(Double(cores.count) / Double(cols)))
        return VStack(spacing: 6) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<cols, id: \.self) { col in
                        let idx = row * cols + col
                        if idx < cores.count {
                            coreSparklineCell(index: idx)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func coreSparklineCell(index: Int) -> some View {
        let k       = kind(for: index)
        let history = index < coreHistory.count ? coreHistory[index] : []
        let current = index < cores.count ? cores[index] : 0.0

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Circle().fill(k.tint).frame(width: 5, height: 5)
                Text("Core \(index + 1)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(TahoeTokens.Color.textSecondary)
                Spacer()
                Text(String(format: "%.0f%%", current))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(k.tint.opacity(0.9))
            }
            coreSparklineCanvas(history: history, tint: k.tint)
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(k.tint.opacity(0.05))
        }
        .frame(maxWidth: .infinity)
    }

    private func coreSparklineCanvas(history: [Double], tint: Color) -> some View {
        Canvas { ctx, size in
            guard history.count > 1 else { return }
            let w        = size.width
            let h        = size.height
            let maxCount = TahoeTokens.Timing.sparklineHistory
            let step     = w / Double(maxCount - 1)
            let offset   = maxCount - history.count

            var path = Path()
            for (i, v) in history.enumerated() {
                let x = Double(i + offset) * step
                let y = h - (v / 100.0) * h * 0.85 - h * 0.075
                i == 0 ? path.move(to: CGPoint(x: x, y: y))
                       : path.addLine(to: CGPoint(x: x, y: y))
            }
            ctx.stroke(path, with: .color(tint.opacity(0.75)), lineWidth: 1.0)

            var fill = path
            fill.addLine(to: CGPoint(x: w, y: h))
            fill.addLine(to: CGPoint(x: Double(offset) * step, y: h))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(tint.opacity(0.12)))
        }
        .frame(height: 24)
    }

    // MARK: - Per-core detail panel

    @ViewBuilder
    private func coreDetailPanel(_ index: Int) -> some View {
        let k     = kind(for: index)
        let load  = index < cores.count ? cores[index] : 0
        let label = "Core \(index + 1)"

        VStack(alignment: .leading, spacing: 8) {
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
                    .foregroundStyle(TahoeTokens.Color.textSecondary)
            }

            Divider().opacity(0.35)

            Text("Per-core type is currently unlabeled until cluster mapping is verified.")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(TahoeTokens.Color.textTertiary)
                .italic()

            if processes.isEmpty {
                Text("No process data")
                    .font(TahoeTokens.FontStyle.body)
                    .foregroundStyle(TahoeTokens.Color.textQuaternary)
            } else {
                let filtered = processesFor(coreKind: k)
                VStack(spacing: 4) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, p in
                        coreDetailRow(rank: idx + 1, process: p, kind: k)
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

    @ViewBuilder
    private func coreDetailRow(rank: Int, process p: AppProcess, kind k: CoreKind) -> some View {
        HStack(spacing: 6) {
            Text("\(rank)")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.quaternary)
                .frame(width: 12, alignment: .trailing)
            Text(p.name.isEmpty ? "—" : p.name)
                .font(TahoeTokens.FontStyle.body)
                .lineLimit(1)
            Spacer()
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
    }

    // MARK: - Helpers

    private var overallAverage: String {
        let avg = cores.isEmpty ? 0.0 : cores.reduce(0, +) / Double(cores.count)
        return String(format: "%.0f%%", avg)
    }

    private var busiestCore: String {
        guard let maxLoad = cores.max(),
              let idx = cores.firstIndex(of: maxLoad) else { return "—" }
        return "Core \(idx + 1) · \(String(format: "%.0f%%", maxLoad))"
    }

    private func processesFor(coreKind: CoreKind) -> [AppProcess] {
        let sorted = processes.sorted { $0.cpuPercent > $1.cpuPercent }
        switch coreKind {
        case .performance:
            return Array(sorted.filter { $0.cpuPercent >= 0.1 }.prefix(5))
        case .efficiency:
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
