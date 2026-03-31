import Foundation

struct PowerState {
    var cpuWatts:   Double = 0
    var gpuWatts:   Double = 0
    var aneWatts:   Double = 0
    var totalWatts: Double { cpuWatts + gpuWatts + aneWatts }
    var history:    [Double] = []
}

// MARK: - Stable power estimator
//
// The earlier IOReport implementation could crash in distributed builds on
// newer macOS releases. Until we have a safer direct telemetry path, estimate
// package power from live CPU/GPU utilization plus chip-specific ceilings.

final class PowerMonitor {
    private struct PowerProfile {
        let idleCPU: Double
        let maxCPU: Double
        let maxGPU: Double
        let maxANE: Double
    }

    private let profile: PowerProfile
    private var previous = PowerState()

    init() {
        profile = Self.makeProfile()
    }

    func sample(cpu: CPUState, gpu: GPUState, temperature: TemperatureState) -> PowerState {
        let cpuLoad = (cpu.total / 100).clamped(to: 0...1)
        let gpuLoad = (gpu.utilization / 100).clamped(to: 0...1)

        let thermalFactor: Double = {
            guard temperature.cpuDie > 0 else { return 1.0 }
            let normalized = ((temperature.cpuDie - 45) / 45).clamped(to: 0...1)
            return 0.95 + normalized * 0.15
        }()

        let cpuDynamic = (profile.maxCPU - profile.idleCPU) * pow(cpuLoad, 1.18) * thermalFactor
        let rawCPU = profile.idleCPU + cpuDynamic
        let rawGPU = profile.maxGPU * pow(gpuLoad, 1.12) * thermalFactor

        // We do not currently have a safe ANE utilization signal, so keep it at
        // zero unless the package is heavily loaded and GPU is mostly idle.
        let inferredANELoad = max(0, cpuLoad - gpuLoad * 0.6)
        let rawANE = profile.maxANE * pow(inferredANELoad, 1.6) * 0.35

        let unsmoothed = PowerState(
            cpuWatts: rawCPU.clamped(to: 0...profile.maxCPU),
            gpuWatts: rawGPU.clamped(to: 0...profile.maxGPU),
            aneWatts: rawANE.clamped(to: 0...profile.maxANE)
        )

        let smoothed = PowerState(
            cpuWatts: Self.smooth(previous.cpuWatts, unsmoothed.cpuWatts),
            gpuWatts: Self.smooth(previous.gpuWatts, unsmoothed.gpuWatts),
            aneWatts: Self.smooth(previous.aneWatts, unsmoothed.aneWatts)
        )

        previous = smoothed
        return smoothed
    }

    private static func smooth(_ previous: Double, _ current: Double) -> Double {
        if previous == 0 { return current }
        return (previous * 0.62) + (current * 0.38)
    }

    private static func makeProfile() -> PowerProfile {
        let chip = SystemInfo.chipName.lowercased()
        let pCores = max(SystemInfo.performanceCoreCount, 0)
        let eCores = max(SystemInfo.efficiencyCoreCount, 0)
        let gpuCores = max(SystemInfo.gpuCoreCount, 0)

        let baseCPU = max(7.0, Double(pCores) * 3.6 + Double(eCores) * 1.15)
        let baseGPU = max(8.0, Double(gpuCores) * 1.45)

        let cpuScale: Double
        let gpuScale: Double
        let idleCPU: Double
        let aneMax: Double

        if chip.contains("ultra") {
            cpuScale = 1.35
            gpuScale = 1.35
            idleCPU = 4.0
            aneMax = 10.0
        } else if chip.contains("max") {
            cpuScale = 1.18
            gpuScale = 1.25
            idleCPU = 3.0
            aneMax = 8.0
        } else if chip.contains("pro") {
            cpuScale = 1.05
            gpuScale = 1.1
            idleCPU = 2.4
            aneMax = 7.0
        } else {
            cpuScale = 0.92
            gpuScale = 0.9
            idleCPU = 1.8
            aneMax = 6.0
        }

        return PowerProfile(
            idleCPU: idleCPU,
            maxCPU: (baseCPU * cpuScale).clamped(to: 8...85),
            maxGPU: (baseGPU * gpuScale).clamped(to: 6...95),
            maxANE: aneMax
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
