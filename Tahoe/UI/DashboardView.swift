import SwiftUI
import Foundation

struct DashboardView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @AppStorage("compactMode")  private var compactMode  = false
    @AppStorage("alwaysOnTop")  private var alwaysOnTop  = true
    @AppStorage("uiTheme")      private var uiThemeRaw   = AppTheme.tahoe.rawValue
    @State private var showSettings  = false
    @State private var detailMetric: DetailMetric? = nil

    private var theme: AppTheme { AppTheme(rawValue: uiThemeRaw) ?? .tahoe }

    var body: some View {
        ZStack {
            VisualEffectView(
                material:     theme == .capitan ? .fullScreenUI : .sidebar,
                blendingMode: .behindWindow
            )
            .ignoresSafeArea()

            thermalOverlay

            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        toolbar

                        // Hero row — 4-up when ≥ 560 pt wide, 2×2 grid otherwise
                        if geo.size.width >= 560 {
                            HStack(spacing: 10) {
                                heroCard(.cpu,
                                    label: "CPU", value: "\(Int(monitor.cpu.total))", unit: "%",
                                    subtitle: SystemInfo.cpuSubtitle,
                                    tint: TahoeTokens.Color.cpuTint, history: monitor.cpu.history)
                                heroCard(.gpu,
                                    label: "GPU", value: "\(Int(monitor.gpu.utilization))", unit: "%",
                                    subtitle: SystemInfo.gpuSubtitle,
                                    tint: TahoeTokens.Color.gpuTint, history: monitor.gpu.history)
                                heroCard(.memory,
                                    label: "Memory", value: String(format: "%.1f", monitor.memory.usedGB), unit: "GB",
                                    subtitle: memSubtitle,
                                    tint: TahoeTokens.Color.memTint, history: monitor.memory.history)
                                heroCard(.power,
                                    label: "Power", value: String(format: "%.1f", monitor.power.totalWatts), unit: "W",
                                    subtitle: powerSubtitle,
                                    tint: TahoeTokens.Color.pwrTint, history: monitor.power.history)
                            }
                        } else {
                            // 2×2 grid for narrow windows
                            VStack(spacing: 10) {
                                HStack(spacing: 10) {
                                    heroCard(.cpu,
                                        label: "CPU", value: "\(Int(monitor.cpu.total))", unit: "%",
                                        subtitle: SystemInfo.cpuSubtitle,
                                        tint: TahoeTokens.Color.cpuTint, history: monitor.cpu.history)
                                    heroCard(.gpu,
                                        label: "GPU", value: "\(Int(monitor.gpu.utilization))", unit: "%",
                                        subtitle: SystemInfo.gpuSubtitle,
                                        tint: TahoeTokens.Color.gpuTint, history: monitor.gpu.history)
                                }
                                HStack(spacing: 10) {
                                    heroCard(.memory,
                                        label: "Memory", value: String(format: "%.1f", monitor.memory.usedGB), unit: "GB",
                                        subtitle: memSubtitle,
                                        tint: TahoeTokens.Color.memTint, history: monitor.memory.history)
                                    heroCard(.power,
                                        label: "Power", value: String(format: "%.1f", monitor.power.totalWatts), unit: "W",
                                        subtitle: powerSubtitle,
                                        tint: TahoeTokens.Color.pwrTint, history: monitor.power.history)
                                }
                            }
                        }

                        if !compactMode {
                            HStack(spacing: 10) {
                                panelCard(label: "CPU Cores", tag: coresTag) {
                                    CoreBarsView(
                                        cores:     monitor.cpu.cores,
                                        processes: monitor.processes
                                    )
                                }
                                panelCard(label: "Memory", tag: "\(Int(monitor.memory.totalGB)) GB unified") {
                                    MemoryBreakdownView(state: monitor.memory, processes: monitor.processes)
                                }
                            }

                            panelCard(label: "GPU", tag: gpuCoresTag) {
                                GPUBarsView(gpu: monitor.gpu)
                            }

                            panelCard(label: "Network & Disk", tag: tempTag) {
                                NetworkDiskView(network: monitor.network, disk: monitor.disk)
                            }

                            panelCard(label: "Processes", tag: "by CPU") {
                                ProcessListView(processes: monitor.processes)
                            }
                        }
                    }
                    .padding(18)
                }
            }
        }
        .frame(minWidth: 420, maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
        .environment(\.appTheme, theme)
        .configuredWindow(floating: alwaysOnTop, autosaveName: "TahoeMain")
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            if monitor.temperature.cpuDie > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 10))
                        .foregroundStyle(tempColor)
                    Text(String(format: "%.0f°C", monitor.temperature.cpuDie))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(tempColor)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(tempColor.opacity(0.1))
                .clipShape(Capsule())
                .accessibilityLabel("CPU temperature")
                .accessibilityValue(String(format: "%.0f degrees Celsius", monitor.temperature.cpuDie))
            }
            Spacer()
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel("Settings")
            .popover(isPresented: $showSettings, arrowEdge: .top) {
                SettingsView().environmentObject(monitor)
            }
        }
        .padding(.bottom, -6)
    }

    // MARK: - Thermal overlay

    @ViewBuilder
    private var thermalOverlay: some View {
        let tint: Color? = {
            switch monitor.thermalState {
            case .serious:  return TahoeTokens.Color.warning.opacity(0.06)
            case .critical: return TahoeTokens.Color.danger.opacity(0.09)
            default:        return nil
            }
        }()
        if let tint {
            tint.ignoresSafeArea()
                .animation(.easeInOut(duration: 1.0), value: monitor.thermalState.rawValue)
        }
    }

    // MARK: - Hero card with popover

    @ViewBuilder
    private func heroCard(
        _ metric: DetailMetric,
        label: String, value: String, unit: String,
        subtitle: String, tint: Color, history: [Double]
    ) -> some View {
        HeroCardView(
            label: label, value: value, unit: unit,
            subtitle: subtitle, tint: tint, history: history
        ) {
            detailMetric = detailMetric == metric ? nil : metric
        }
        .environment(\.appTheme, theme)
        .popover(
            isPresented: Binding(
                get: { detailMetric == metric },
                set: { if !$0 { detailMetric = nil } }
            ),
            arrowEdge: .bottom
        ) {
            DetailView(metric: metric)
                .environmentObject(monitor)
                .environment(\.appTheme, theme)
        }
    }

    // MARK: - Panel card

    @ViewBuilder
    private func panelCard<Content: View>(
        label: String,
        tag: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(TahoeTokens.FontStyle.label)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Spacer()
                Text(tag)
                    .font(TahoeTokens.FontStyle.pill)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Capsule())
            }
            .padding(.bottom, 14)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            let radius = TahoeTokens.Radius.card
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                // Subtle top-edge specular
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .clear, .clear],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
            }
            .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
        }
    }

    // MARK: - Computed labels

    private var memSubtitle: String {
        let t = monitor.memory.totalGB
        guard t > 0 else { return "—" }
        return "\(Int(monitor.memory.usedGB / t * 100))% of \(Int(t)) GB"
    }
    private var powerSubtitle: String {
        let c = monitor.power.cpuWatts, g = monitor.power.gpuWatts
        return c + g > 0 ? String(format: "CPU %.1fW · GPU %.1fW", c, g) : "CPU + GPU + ANE"
    }
    private var coreAvg: Double {
        let c = monitor.cpu.cores
        return c.isEmpty ? 0 : c.reduce(0, +) / Double(c.count)
    }
    private var coresTag: String {
        let p = SystemInfo.performanceCoreCount
        let e = SystemInfo.efficiencyCoreCount
        if p > 0, e > 0 { return "\(p)P + \(e)E · avg \(Int(coreAvg))%" }
        return "avg \(Int(coreAvg))%"
    }
    private var gpuCoresTag: String {
        let n = SystemInfo.gpuCoreCount
        return n > 0 ? "\(n)-core · \(Int(monitor.gpu.utilization))%" : "\(Int(monitor.gpu.utilization))%"
    }
    private var tempTag: String {
        monitor.temperature.cpuDie > 0
            ? String(format: "%.0f°C", monitor.temperature.cpuDie) : "I/O"
    }
    private var tempColor: Color {
        let t = monitor.temperature.cpuDie
        if t > 90 { return TahoeTokens.Color.danger }
        if t > 75 { return TahoeTokens.Color.warning }
        return TahoeTokens.Color.tempTint
    }
}
