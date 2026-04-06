import Foundation
import IOKit

// MARK: - Private IOHIDEventSystem bindings
//
// Apple Silicon thermal sensors are exposed as HID events, not SMC keys.
// These symbols live in IOKit.framework but are not in public headers.
// Safe to call from an unsandboxed app.

fileprivate let kHIDTempEventType: Int32 = 15          // kIOHIDEventTypeTemperature
fileprivate let kHIDTempField:     Int32 = 15 << 16    // kIOHIDEventFieldTemperatureLevel

@_silgen_name("IOHIDEventSystemClientCreate")
fileprivate func IOHIDEventSystemClientCreate(
    _ allocator: CFAllocator?
) -> UnsafeMutableRawPointer?

@_silgen_name("IOHIDEventSystemClientCopyServices")
fileprivate func IOHIDEventSystemClientCopyServices(
    _ client: UnsafeMutableRawPointer
) -> UnsafeMutableRawPointer?        // returns retained CFArray

@_silgen_name("IOHIDServiceClientCopyEvent")
fileprivate func IOHIDServiceClientCopyEvent(
    _ service:   UnsafeMutableRawPointer,
    _ type:      Int32,
    _ options:   Int32,
    _ timestamp: Int64
) -> UnsafeMutableRawPointer?        // returns retained IOHIDEventRef

@_silgen_name("IOHIDEventGetFloatValue")
fileprivate func IOHIDEventGetFloatValue(
    _ event: UnsafeMutableRawPointer,
    _ field: Int32
) -> Double

@_silgen_name("IOHIDServiceClientCopyProperty")
fileprivate func IOHIDServiceClientCopyProperty(
    _ service: UnsafeMutableRawPointer,
    _ key:     CFString
) -> UnsafeMutableRawPointer?        // returns retained CFTypeRef

// MARK: -

/// Reads Apple Silicon thermal sensors via IOHIDEventSystem.
/// On Intel Macs this initialises but reports `isAvailable = false`,
/// so the caller can fall back to SMC.
final class AppleSiliconThermal {

    private var clientRef:   UnsafeMutableRawPointer?   // IOHIDEventSystemClientRef (retained)
    private var servicesArr: UnsafeMutableRawPointer?   // CFArray of service refs    (retained)

    private struct SensorInfo {
        let index: Int
        let name: String
        let role: Role
    }

    // Indices into servicesArr, pre-classified by sensor name at init time
    private var sensors: [SensorInfo] = []

    private(set) var isAvailable = false

    init() { setup() }

    deinit {
        servicesArr.map { cfRelease($0) }
        clientRef.map   { cfRelease($0) }
    }

    // MARK: - Sample

    func sample() -> TemperatureState {
        guard isAvailable, let raw = servicesArr else { return TemperatureState() }
        let arr = unsafeBitCast(raw, to: CFArray.self)
        let cpu = avgTemp(arr, role: .cpu)
        let gpu = avgTemp(arr, role: .gpu)
        let memory = avgTemp(arr, role: .memory)
        let ambient = avgTemp(arr, role: .ambient)
        return TemperatureState(
            cpuDie:      cpu,
            gpuDie:      gpu,
            gpuDie2:     0,
            memoryTemp:  memory,
            ambientTemp: ambient,
            readings:    makeReadings(arr)
        )
    }

    // MARK: - Setup

    private func setup() {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
            print("[HID] IOHIDEventSystemClientCreate returned nil")
            return
        }
        clientRef = client

        guard let rawArr = IOHIDEventSystemClientCopyServices(client) else {
            print("[HID] IOHIDEventSystemClientCopyServices returned nil")
            return
        }
        servicesArr = rawArr   // retained — released in deinit

        let arr   = unsafeBitCast(rawArr, to: CFArray.self)
        let count = CFArrayGetCount(arr)
        print("[HID] \(count) total HID services found")

        for i in 0..<count {
            guard let rawSvc = CFArrayGetValueAtIndex(arr, i) else { continue }
            let svc = UnsafeMutableRawPointer(mutating: rawSvc)

            // Only care about services that can produce temperature events
            guard let event = IOHIDServiceClientCopyEvent(svc, kHIDTempEventType, 0, 0) else { continue }
            cfRelease(event)   // just checking existence; release immediately

            let name = productName(svc)
            let role = classify(name)

            print("[HID]   [\(i)] \"\(name)\" → \(role.map { "\($0)" } ?? "ignored")")

            if let role {
                sensors.append(SensorInfo(index: i, name: name, role: role))
            }
        }

        isAvailable = !sensors.isEmpty
        print("[HID] Available=\(isAvailable)  CPU:\(sensors.filter { $0.role == .cpu }.count) GPU:\(sensors.filter { $0.role == .gpu }.count) Mem:\(sensors.filter { $0.role == .memory }.count) Amb:\(sensors.filter { $0.role == .ambient }.count)")
    }

    // MARK: - Reading

    private func avgTemp(_ arr: CFArray, role: Role) -> Double {
        let indices = sensors.filter { $0.role == role }.map(\.index)
        guard !indices.isEmpty else { return 0 }
        var sum = 0.0, n = 0
        for i in indices {
            guard let rawSvc = CFArrayGetValueAtIndex(arr, i) else { continue }
            let svc = UnsafeMutableRawPointer(mutating: rawSvc)
            guard let event = IOHIDServiceClientCopyEvent(svc, kHIDTempEventType, 0, 0) else { continue }
            let t = IOHIDEventGetFloatValue(event, kHIDTempField)
            cfRelease(event)
            if t > 0, t < 150 { sum += t; n += 1 }
        }
        return n > 0 ? sum / Double(n) : 0
    }

    private func makeReadings(_ arr: CFArray) -> [TemperatureReading] {
        var result: [TemperatureReading] = []
        for sensor in sensors {
            guard let rawSvc = CFArrayGetValueAtIndex(arr, sensor.index) else { continue }
            let svc = UnsafeMutableRawPointer(mutating: rawSvc)
            guard let event = IOHIDServiceClientCopyEvent(svc, kHIDTempEventType, 0, 0) else { continue }
            let t = IOHIDEventGetFloatValue(event, kHIDTempField)
            cfRelease(event)
            guard t > 0, t < 150 else { continue }

            switch sensor.role {
            case .cpu:
                result.append(reading(kind: .cpu, label: "CPU", value: t, source: sensor.name, meaning: "SoC die / cluster temperature"))
            case .gpu:
                result.append(reading(kind: .gpu, label: "GPU", value: t, source: sensor.name, meaning: "Integrated GPU temperature"))
            case .memory:
                result.append(reading(kind: .memory, label: "Memory", value: t, source: sensor.name, meaning: "Memory or storage proximity temperature"))
            case .ambient:
                result.append(reading(kind: .ambient, label: "Ambient", value: t, source: sensor.name, meaning: "Case or internal air temperature"))
            }
        }
        return result
    }

    // MARK: - Classification

    private enum Role { case cpu, gpu, memory, ambient }

    private func classify(_ name: String) -> Role? {
        let n = name.lowercased()

        // --- Root-gated sensors (only visible when running as root via helper) ---
        if n.contains("pacc") || n.contains("pcore") ||
           n.contains("eacc") || n.contains("ecore") { return .cpu }
        if n.contains("gpu")  || n.contains("tg0")   { return .gpu }

        // --- Available without root on Apple Silicon ---
        // PMU tdie* = SoC die thermal probes distributed across the chip.
        // These are real die temperatures; max among them ≈ hottest cluster (CPU).
        if n.contains("tdie")                        { return .cpu }

        // NAND = SSD/storage die temperature
        if n.contains("nand")                        { return .memory }

        // PMU tcal = calibration reference; the coolest stable reading on the board
        if n.contains("tcal")                        { return .ambient }

        // Other labelled sensors
        if n.contains("dram") || n.contains("tmem") ||
           n.contains("hbm")                         { return .memory }
        if n.contains("soc")  || n.contains("airflow") ||
           n.contains("ambient") || n.contains("inlet") { return .ambient }

        return nil
    }

    // MARK: - Helpers

    private func productName(_ svc: UnsafeMutableRawPointer) -> String {
        guard let rawProp = IOHIDServiceClientCopyProperty(svc, "Product" as CFString) else {
            return "Unknown"
        }
        // Property is a CFString; cast and bridge to Swift String
        let str = unsafeBitCast(rawProp, to: CFString.self) as String
        cfRelease(rawProp)
        return str
    }

    /// Release a CoreFoundation-compatible opaque pointer.
    private func cfRelease(_ ptr: UnsafeMutableRawPointer) {
        Unmanaged<AnyObject>.fromOpaque(ptr).release()
    }

    private func reading(kind: TemperatureReading.Kind, label: String, value: Double, source: String, meaning: String) -> TemperatureReading {
        TemperatureReading(kind: kind, label: label, value: value, source: source, meaning: meaning)
    }
}
