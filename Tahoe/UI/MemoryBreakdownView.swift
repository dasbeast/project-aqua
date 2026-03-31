import SwiftUI

struct MemoryBreakdownView: View {
    let state:     MemoryState
    let processes: [AppProcess]

    @State private var selectedSegment: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Segment model

    private struct Segment: Identifiable {
        let id:          String
        let value:       Double
        let tint:        Color
        let description: String
    }

    private var segments: [Segment] { [
        Segment(id: "Wired",
                value:       state.wiredGB,
                tint:        TahoeTokens.Color.cpuTint,
                description: "Memory the kernel has locked down. Can't be compressed or moved to your SSD — it stays physically in RAM no matter what. Mostly used by the OS itself."),
        Segment(id: "Active",
                value:       state.activeGB,
                tint:        TahoeTokens.Color.memTint,
                description: "The \"hot\" RAM — memory your apps are actively reading or writing right now."),
        Segment(id: "Compressed",
                value:       state.compressedGB,
                tint:        TahoeTokens.Color.pwrTint,
                description: "Instead of writing idle pages to your SSD, macOS squeezes them smaller and keeps them in RAM. Faster than swap, slower than active memory."),
        Segment(id: "Inactive",
                value:       state.inactiveGB,
                tint:        TahoeTokens.Color.textSecondary,
                description: "Memory from apps you used recently but aren't using right now. macOS keeps it handy in case you come back — and it's instantly reclaimed the moment something else needs RAM."),
        Segment(id: "Free",
                value:       freeGB,
                tint:        TahoeTokens.Color.textQuaternary,
                description: "Completely unused RAM that is available immediately. This memory is not currently holding app state or cached data."),
    ] }

    private var freeGB: Double {
        max(state.totalGB - state.wiredGB - state.activeGB - state.compressedGB - state.inactiveGB, 0)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            segmentBar
            legendGrid

            if state.swapUsedGB > 0.001 {
                swapRow
                    .tooltip("RAM overflow stored on your SSD. Your Mac ran out of physical memory and had to use slower disk space. More swap = time to add RAM (or close some apps).")
            }

            if let sel = selectedSegment,
               let seg = segments.first(where: { $0.id == sel }) {
                processPanel(for: seg)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82),
            value: selectedSegment
        )
    }

    // MARK: - Segmented bar

    private var segmentBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(segments) { seg in
                    let frac      = seg.value / max(state.totalGB, 1)
                    let isSelected = selectedSegment == seg.id
                    let dimmed    = selectedSegment != nil && !isSelected
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(seg.tint.opacity(dimmed ? 0.28 : 1.0))
                        .frame(width: max(geo.size.width * frac, 2))
                        .scaleEffect(y: isSelected ? 1.25 : 1.0, anchor: .center)
                        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: selectedSegment)
                        .onTapGesture { toggleSegment(seg.id) }
                        .tooltip(hoverLabel(for: seg), delay: 0.2)
                }
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: state.usedGB)
    }

    // MARK: - Legend grid

    private var legendGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(segments) { seg in
                let isSelected = selectedSegment == seg.id
                let dimmed     = selectedSegment != nil && !isSelected
                legendRow(seg: seg, selected: isSelected, dimmed: dimmed)
                    .onTapGesture { toggleSegment(seg.id) }
                    .tooltip(tooltipText(for: seg), delay: 0.35)
            }
        }
    }

    @ViewBuilder
    private func legendRow(seg: Segment, selected: Bool, dimmed: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(seg.tint.opacity(dimmed ? 0.35 : 1.0))
                .frame(width: 6, height: 6)
            Text(seg.id)
                .font(TahoeTokens.FontStyle.body)
                .foregroundStyle(dimmed ? TahoeTokens.Color.textMuted : TahoeTokens.Color.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(String(format: "%.2f", seg.value))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(dimmed ? TahoeTokens.Color.textMuted : (selected ? seg.tint : TahoeTokens.Color.textPrimary))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(seg.tint.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(seg.tint.opacity(0.20), lineWidth: 0.5)
                    }
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Swap row

    private var swapRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.2.squarepath")
                .font(.system(size: 9))
                .foregroundStyle(TahoeTokens.Color.danger.opacity(0.75))
            Text("Swap")
                .font(TahoeTokens.FontStyle.body)
                .foregroundStyle(TahoeTokens.Color.textSecondary)
            Spacer()
            Text(String(format: "%.2f GB in use", state.swapUsedGB))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(TahoeTokens.Color.danger.opacity(0.85))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(TahoeTokens.Color.danger.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(TahoeTokens.Color.danger.opacity(0.15), lineWidth: 0.5)
                }
        }
    }

    // MARK: - Process panel

    @ViewBuilder
    private func processPanel(for seg: Segment) -> some View {
        let procs  = processesFor(seg)
        let maxMem = procs.first?.memoryGB ?? 1.0

        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Circle().fill(seg.tint).frame(width: 6, height: 6)
                Text(seg.id)
                    .font(TahoeTokens.FontStyle.label)
                    .foregroundStyle(seg.tint)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Spacer()
                Text(String(format: "%.2f GB", seg.value))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(TahoeTokens.Color.textSecondary)
            }

            Text(seg.description)
                .font(.system(size: 9))
                .foregroundStyle(TahoeTokens.Color.textTertiary)
                .italic()
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.3)

            if procs.isEmpty {
                Text(emptyStateMessage(for: seg))
                    .font(TahoeTokens.FontStyle.body)
                    .foregroundStyle(TahoeTokens.Color.textQuaternary)
            } else {
                HStack {
                    Text("Process")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Memory")
                        .frame(width: 54, alignment: .trailing)
                }
                .font(TahoeTokens.FontStyle.label)
                .foregroundStyle(TahoeTokens.Color.textTertiary)
                .textCase(.uppercase)
                .kerning(0.8)

                ForEach(Array(procs.enumerated()), id: \.element.id) { idx, p in
                    processPanelRow(rank: idx + 1, process: p, maxMem: maxMem, tint: seg.tint)
                    if idx < procs.count - 1 {
                        Divider().opacity(0.2)
                    }
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: TahoeTokens.Radius.pill, style: .continuous)
                .fill(seg.tint.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: TahoeTokens.Radius.pill, style: .continuous)
                        .strokeBorder(seg.tint.opacity(0.14), lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    private func processPanelRow(rank: Int, process p: AppProcess, maxMem: Double, tint: Color) -> some View {
        HStack(spacing: 0) {
            Text("\(rank)")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(TahoeTokens.Color.textQuaternary)
                .frame(width: 16, alignment: .leading)
            Text(p.name.isEmpty ? "—" : p.name)
                .font(TahoeTokens.FontStyle.body)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(TahoeTokens.Color.textPrimary.opacity(0.08))
                    Capsule()
                        .fill(tint.opacity(0.5))
                        .frame(width: geo.size.width * min(p.memoryGB / max(maxMem, 0.001), 1))
                }
            }
            .frame(width: 36, height: 4)
            .padding(.horizontal, 6)
            Text(memLabel(p.memoryGB))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(tint.opacity(0.9))
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Helpers

    private func toggleSegment(_ id: String) {
        selectedSegment = selectedSegment == id ? nil : id
    }

    private func processesFor(_ seg: Segment) -> [AppProcess] {
        let byMem = processes.sorted { $0.memoryGB > $1.memoryGB }
        switch seg.id {
        case "Free":
            return []
        case "Wired":
            // Wired is kernel-managed. Surface known system processes first,
            // then fill with highest-memory apps.
            let system = byMem.filter { p in
                let n = p.name.lowercased()
                return p.id < 200
                    || n == "kernel_task" || n == "windowserver" || n == "launchd"
                    || n.hasSuffix("d") && p.id < 1000   // system daemons (e.g. coreaudiod)
            }
            let rest = byMem.filter { p in !system.contains(where: { $0.id == p.id }) }
            return Array((system + rest).prefix(8))
        case "Inactive":
            // Inactive = idle/background. Low CPU, still holding memory.
            let idle = byMem.filter { $0.cpuPercent < 0.3 }
            return Array((idle.isEmpty ? byMem : idle).prefix(8))
        default:
            // Active & Compressed: highest memory consumers are the culprits.
            return Array(byMem.prefix(8))
        }
    }

    private func memLabel(_ gb: Double) -> String {
        gb >= 1.0 ? String(format: "%.1f G", gb)
                  : String(format: "%.0f M", gb * 1024)
    }

    private func tooltipText(for seg: Segment) -> String {
        "\(seg.id): \(String(format: "%.2f GB", seg.value))\n\(seg.description)"
    }

    private func hoverLabel(for seg: Segment) -> String {
        "\(seg.id): \(String(format: "%.2f GB", seg.value))"
    }

    private func emptyStateMessage(for seg: Segment) -> String {
        if seg.id == "Free" {
            return "Free memory is unused RAM, so it isn't attributed to any process."
        }
        return "No process data"
    }
}
