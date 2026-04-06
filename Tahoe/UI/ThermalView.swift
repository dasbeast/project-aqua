import SwiftUI

/// Grid of temperature chips — one per sensor that returned a valid reading.
/// Each chip is individually tappable, opening a popover with a history chart
/// for that sensor only. "All sensors" expands the card inline.
struct ThermalView: View {
    let temp: TemperatureState

    @State private var showAllSensors = false
    @AppStorage("useFahrenheit") private var useFahrenheit = false

    private var chips: [ThermalChip] {
        var result: [ThermalChip] = []

        if temp.cpuDie > 0 {
            result.append(ThermalChip(
                label:   "CPU",
                icon:    "cpu",
                temp:    temp.cpuDie,
                danger:  90,
                warning: 75,
                history: temp.cpuHistory,
                reading: temp.readings.first(where: { $0.kind == .cpu })
            ))
        }
        if temp.gpuDie > 0 {
            result.append(ThermalChip(
                label:   temp.gpuDie2 > 0 ? "GPU 0" : "GPU",
                icon:    "display",
                temp:    temp.gpuDie,
                danger:  95,
                warning: 80,
                history: temp.gpuHistory,
                reading: temp.readings.first(where: { $0.kind == .gpu })
            ))
        }
        if temp.gpuDie2 > 0 {
            result.append(ThermalChip(
                label:   "GPU 1",
                icon:    "display",
                temp:    temp.gpuDie2,
                danger:  95,
                warning: 80,
                history: temp.gpuHistory,
                reading: temp.readings.first(where: { $0.kind == .gpu2 })
            ))
        }
        if temp.memoryTemp > 0 {
            result.append(ThermalChip(
                label:   "Memory",
                icon:    "memorychip",
                temp:    temp.memoryTemp,
                danger:  85,
                warning: 65,
                history: temp.memoryHistory,
                reading: temp.readings.first(where: { $0.kind == .memory })
            ))
        }
        if temp.ambientTemp > 0 {
            result.append(ThermalChip(
                label:   "Ambient",
                icon:    "thermometer.medium",
                temp:    temp.ambientTemp,
                danger:  75,   // internal board/calibration sensor, not outside air
                warning: 60,
                history: temp.ambientHistory,
                reading: temp.readings.first(where: { $0.kind == .ambient })
            ))
        }

        return result
    }

    var body: some View {
        if chips.isEmpty {
            Text("No thermal sensors available")
                .font(TahoeTokens.FontStyle.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 10) {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: min(chips.count, 5))
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(chips) { chip in
                        ThermalChipView(chip: chip)
                    }
                }

                // Inline "All sensors" disclosure
                if !temp.readings.isEmpty {
                    VStack(spacing: 0) {
                        Divider().opacity(0.35)

                        // Toggle row
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                showAllSensors.toggle()
                            }
                        } label: {
                            HStack {
                                Text(showAllSensors ? "Hide sensors" : "All sensors")
                                    .font(TahoeTokens.FontStyle.pill)
                                    .foregroundStyle(TahoeTokens.Color.textTertiary)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(TahoeTokens.Color.textQuaternary)
                                    .rotationEffect(.degrees(showAllSensors ? 180 : 0))
                                    .animation(.easeInOut(duration: 0.22), value: showAllSensors)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Expanded sensor list
                        if showAllSensors {
                            AllSensorsInlineView(readings: temp.readings)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Inline sensor list

private struct AllSensorsInlineView: View {
    let readings: [TemperatureReading]
    @AppStorage("useFahrenheit") private var useFahrenheit = false

    private var groups: [(title: String, icon: String, tint: Color, rows: [TemperatureReading])] {
        let order: [TemperatureReading.Kind] = [.cpu, .gpu, .gpu2, .memory, .ambient]
        return order.compactMap { kind in
            let rows = readings.filter { $0.kind == kind }
            guard !rows.isEmpty else { return nil }
            return (groupTitle(kind), groupIcon(kind), groupTint(kind), rows)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 6) {
                    // Group label
                    HStack(spacing: 4) {
                        Image(systemName: group.icon)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(group.tint)
                        Text(group.title)
                            .font(TahoeTokens.FontStyle.label)
                            .foregroundStyle(group.tint.opacity(0.85))
                            .textCase(.uppercase)
                            .kerning(0.8)
                    }

                    // CPU with multiple probes → die grid; everything else → rows
                    if group.title == "CPU" && group.rows.count > 1 {
                        cpuDieGrid(group.rows, tint: group.tint)
                    } else {
                        ForEach(group.rows) { reading in
                            sensorRow(reading, tint: group.tint)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - CPU die grid

    @ViewBuilder
    private func cpuDieGrid(_ rows: [TemperatureReading], tint: Color) -> some View {
        let sorted = rows.sorted { dieIndex($0.source) < dieIndex($1.source) }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(sorted.enumerated()), id: \.offset) { i, reading in
                VStack(spacing: 3) {
                    Text("Die \(i + 1)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(TahoeTokens.Color.textQuaternary)
                    Text(useFahrenheit
                         ? String(format: "%.0f°", reading.value.toFahrenheit)
                         : String(format: "%.0f°", reading.value))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(0.06))
                }
            }
        }
    }

    /// Extracts a sort index from a source string like "PMU tdie3" → 3.
    /// Falls back to alphabetical order if no trailing number is found.
    private func dieIndex(_ source: String) -> Int {
        let digits = source.reversed().prefix(while: { $0.isNumber })
        return Int(String(digits.reversed())) ?? 0
    }

    // MARK: - Standard sensor row

    @ViewBuilder
    private func sensorRow(_ reading: TemperatureReading, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(reading.value.tempFormatted(fahrenheit: useFahrenheit))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(reading.meaning)
                    .font(TahoeTokens.FontStyle.body)
                    .foregroundStyle(TahoeTokens.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(reading.source)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(TahoeTokens.Color.textQuaternary)
                    .lineLimit(1)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.06))
        }
    }

    private func groupTitle(_ kind: TemperatureReading.Kind) -> String {
        switch kind {
        case .cpu:     return "CPU"
        case .gpu:     return "GPU"
        case .gpu2:    return "GPU 1"
        case .memory:  return "Memory"
        case .ambient: return "Ambient"
        }
    }

    private func groupIcon(_ kind: TemperatureReading.Kind) -> String {
        switch kind {
        case .cpu:        return "cpu"
        case .gpu, .gpu2: return "display"
        case .memory:     return "memorychip"
        case .ambient:    return "thermometer.medium"
        }
    }

    private func groupTint(_ kind: TemperatureReading.Kind) -> Color {
        switch kind {
        case .cpu:        return TahoeTokens.Color.cpuTint
        case .gpu, .gpu2: return TahoeTokens.Color.gpuTint
        case .memory:     return TahoeTokens.Color.memTint
        case .ambient:    return TahoeTokens.Color.tempTint
        }
    }
}

// MARK: - Model

struct ThermalChip: Identifiable {
    var id:      String { label }   // stable across re-renders so @State is preserved
    let label:   String
    let icon:    String
    let temp:    Double
    let danger:  Double
    let warning: Double
    let history: [Double]
    let reading: TemperatureReading?

    var tint: Color {
        Self.thermalColor(temp: temp, danger: danger)
    }

    /// Smooth hue ramp: blue (cool) → teal (normal) → yellow (warm) → orange (hot) → red (danger+)
    static func thermalColor(temp: Double, danger: Double) -> Color {
        let frac = min(temp / danger, 1.0)

        struct Stop { let at: Double; let hue: Double; let sat: Double; let bri: Double }
        let stops: [Stop] = [
            Stop(at: 0.00, hue: 0.60, sat: 0.60, bri: 0.90),  // blue   — cool / light use
            Stop(at: 0.50, hue: 0.50, sat: 0.55, bri: 0.88),  // teal   — normal operating
            Stop(at: 0.72, hue: 0.14, sat: 0.82, bri: 0.92),  // yellow — warm
            Stop(at: 0.87, hue: 0.07, sat: 0.88, bri: 0.90),  // orange — hot
            Stop(at: 1.00, hue: 0.00, sat: 0.90, bri: 0.88),  // red    — at/above danger
        ]

        guard let hi = stops.first(where: { $0.at >= frac }) else {
            return Color(hue: 0, saturation: 0.90, brightness: 0.88)
        }
        guard let lo = stops.last(where: { $0.at <= frac }), lo.at < hi.at else {
            return Color(hue: hi.hue, saturation: hi.sat, brightness: hi.bri)
        }

        let t = (frac - lo.at) / (hi.at - lo.at)
        return Color(
            hue:        lo.hue + (hi.hue - lo.hue) * t,
            saturation: lo.sat + (hi.sat - lo.sat) * t,
            brightness: lo.bri + (hi.bri - lo.bri) * t
        )
    }
}

// MARK: - Chip view

private struct ThermalChipView: View {
    let chip: ThermalChip
    @State private var showPopover = false
    @AppStorage("useFahrenheit") private var useFahrenheit = false

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: chip.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(chip.tint)

            Text(useFahrenheit
                 ? String(format: "%.0f°", chip.temp.toFahrenheit)
                 : String(format: "%.0f°", chip.temp))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text(chip.label)
                .font(TahoeTokens.FontStyle.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(chip.tint.opacity(0.07))
        }
        .contentShape(Rectangle())
        .onTapGesture { showPopover.toggle() }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            ThermalChipDetail(chip: chip)
        }
    }
}

// MARK: - Per-chip popover detail

private struct ThermalChipDetail: View {
    let chip: ThermalChip
    @AppStorage("useFahrenheit") private var useFahrenheit = false

    private var maxTemp: Double {
        max(chip.history.max() ?? chip.danger, chip.danger)
    }

    // History is always stored in °C; convert for display only
    private var displayHistory: [Double] {
        useFahrenheit ? chip.history.map(\.toFahrenheit) : chip.history
    }
    private var displayMax: Double {
        useFahrenheit ? maxTemp.toFahrenheit : maxTemp
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: chip.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(chip.tint)
                Text(chip.label)
                    .font(TahoeTokens.FontStyle.label)
                    .foregroundStyle(chip.tint)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Spacer()
                Text(chip.temp.tempFormatted(fahrenheit: useFahrenheit))
                    .font(.system(size: 13, weight: .light))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            if !chip.history.isEmpty {
                HistoryChartView(
                    history:  displayHistory,
                    tint:     chip.tint,
                    maxValue: displayMax,
                    unit:     useFahrenheit ? "°F" : "°C"
                )

                HStack(spacing: 0) {
                    statCell("Min", value: displayHistory.min() ?? 0)
                    Spacer()
                    statCell("Avg", value: displayHistory.reduce(0, +) / Double(displayHistory.count))
                    Spacer()
                    statCell("Max", value: displayHistory.max() ?? 0)
                }
                .padding(.top, 2)
            }

            Divider().opacity(0.4)

            if let reading = chip.reading {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reading.meaning)
                        .font(TahoeTokens.FontStyle.body)
                        .foregroundStyle(TahoeTokens.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(reading.source)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(TahoeTokens.Color.textQuaternary)
                }
            }

            HStack {
                thresholdLabel(TahoeTokens.Color.warning, "Warm ≥ \(chip.warning.tempFormatted(fahrenheit: useFahrenheit))")
                Spacer()
                thresholdLabel(TahoeTokens.Color.danger,  "Hot ≥ \(chip.danger.tempFormatted(fahrenheit: useFahrenheit))")
            }
        }
        .padding(16)
        .frame(width: 240)
    }

    @ViewBuilder
    private func statCell(_ label: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(TahoeTokens.FontStyle.label)
                .foregroundStyle(TahoeTokens.Color.textQuaternary)
                .textCase(.uppercase)
                .kerning(0.8)
            Text(useFahrenheit
                 ? String(format: "%.0f°F", value)
                 : String(format: "%.0f°C", value))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(TahoeTokens.Color.textSecondary)
        }
    }

    @ViewBuilder
    private func thresholdLabel(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text)
                .font(TahoeTokens.FontStyle.body)
                .foregroundStyle(TahoeTokens.Color.textSecondary)
        }
    }
}
