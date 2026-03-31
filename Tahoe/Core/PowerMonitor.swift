import Foundation

struct PowerState {
    var cpuWatts:   Double = 0
    var gpuWatts:   Double = 0
    var aneWatts:   Double = 0
    var totalWatts: Double { cpuWatts + gpuWatts + aneWatts }
    var history:    [Double] = []
}

// MARK: - IOReport-based power monitor (Apple Silicon)
//
// Uses the private IOReport framework via dlopen.
// IOReportSubscriptionRef is an opaque struct pointer — NOT toll-free
// bridged to CFType — so we store it as UnsafeMutableRawPointer and
// pass it through C calls without ARC involvement.
//
// Energy Model channels return cumulative millijoule counts.
// Delta between two samples / elapsed seconds / 1000 = watts.

final class PowerMonitor {

    // MARK: Private API types

    private typealias CopyChannelsInGroupT = @convention(c) (
        CFString?, CFString?, UInt32, UInt32, UInt32
    ) -> Unmanaged<CFMutableDictionary>?

    // First param is IOReportSubscriptionRef — opaque pointer, NOT a CFType.
    private typealias CreateSubscriptionT = @convention(c) (
        UnsafeMutableRawPointer?,
        CFMutableDictionary,
        UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>,
        UInt64,
        CFTypeRef?
    ) -> UnsafeMutableRawPointer?          // returns IOReportSubscriptionRef

    private typealias CreateSamplesT = @convention(c) (
        UnsafeMutableRawPointer?,          // IOReportSubscriptionRef
        CFMutableDictionary,
        CFTypeRef?
    ) -> Unmanaged<CFDictionary>?

    private typealias CreateSamplesDeltaT = @convention(c) (
        CFDictionary, CFDictionary, CFTypeRef?
    ) -> Unmanaged<CFDictionary>?

    private typealias IterateT = @convention(c) (
        CFDictionary,
        @convention(block) (UnsafeRawPointer) -> Int32
    ) -> Void

    private typealias GetGroupT        = @convention(c) (UnsafeRawPointer) -> Unmanaged<CFString>?
    private typealias GetChannelNameT  = @convention(c) (UnsafeRawPointer) -> Unmanaged<CFString>?
    private typealias GetIntegerValueT = @convention(c) (UnsafeRawPointer, UnsafeMutablePointer<Int32>) -> Int64

    // MARK: Loaded symbols

    private let lib:                UnsafeMutableRawPointer?
    private let copyChannelsInGroup: CopyChannelsInGroupT?
    private let createSubscription:  CreateSubscriptionT?
    private let createSamples:       CreateSamplesT?
    private let createSamplesDelta:  CreateSamplesDeltaT?
    private let iterate:             IterateT?
    private let getGroup:            GetGroupT?
    private let getChannelName:      GetChannelNameT?
    private let getIntegerValue:     GetIntegerValueT?

    // MARK: Subscription state (raw pointer — no ARC)

    private var subscription:   UnsafeMutableRawPointer?
    private var subbedChannels: CFMutableDictionary?
    private var prevSample:     CFDictionary?
    private var prevTime:       Date = Date()

    // MARK: Init

    init() {
        // macOS 15+: shipped as a flat dylib, not a private framework
        let libHandle = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY)
        func sym<T>(_ name: String) -> T? {
            guard let libHandle, let p = dlsym(libHandle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        lib                 = libHandle
        copyChannelsInGroup = sym("IOReportCopyChannelsInGroup")
        createSubscription  = sym("IOReportCreateSubscription")
        createSamples       = sym("IOReportCreateSamples")
        createSamplesDelta  = sym("IOReportCreateSamplesDelta")
        iterate             = sym("IOReportIterate")
        getGroup            = sym("IOReportChannelGetGroup")
        getChannelName      = sym("IOReportChannelGetChannelName")
        getIntegerValue     = sym("IOReportSimpleGetIntegerValue")
        setup()
    }

    private func setup() {
        guard let copyChannelsInGroup, let createSubscription, let createSamples else {
            NSLog("[PowerMonitor] ❌ missing symbols")
            return
        }

        guard let energyCh = copyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0)?
                .takeRetainedValue() else {
            NSLog("[PowerMonitor] ❌ copyChannelsInGroup returned nil")
            return
        }
        NSLog("[PowerMonitor] ✅ got channels dict")

        var subbedRef: Unmanaged<CFMutableDictionary>? = nil
        guard let sub = createSubscription(nil, energyCh, &subbedRef, 0, nil) else {
            NSLog("[PowerMonitor] ❌ createSubscription returned nil")
            return
        }
        NSLog("[PowerMonitor] ✅ subscription created, subbedRef nil=\(subbedRef == nil)")

        subscription   = sub
        subbedChannels = subbedRef?.takeRetainedValue()
        if let sc = subbedChannels {
            let s = createSamples(sub, sc, nil)?.takeRetainedValue()
            prevSample = s
            NSLog("[PowerMonitor] ✅ initial sample nil=\(s == nil)")
        } else {
            NSLog("[PowerMonitor] ❌ subbedChannels is nil")
        }
        prevTime = Date()
    }

    // MARK: Sampling

    func sample() -> PowerState {
        guard let subscription, let subbedChannels,
              let createSamples, let createSamplesDelta, let iterate,
              let getChannelName, let getIntegerValue,
              let prev = prevSample else {
            return PowerState()
        }

        guard let current = createSamples(subscription, subbedChannels, nil)?
                .takeRetainedValue() else { return PowerState() }

        let now     = Date()
        let elapsed = max(now.timeIntervalSince(prevTime), 1e-3)
        prevTime   = now
        prevSample = current

        guard let delta = createSamplesDelta(prev, current, nil)?
                .takeRetainedValue() else { return PowerState() }

        final class Acc { var cpu = 0.0; var gpu = 0.0; var ane = 0.0 }
        let acc = Acc()

        iterate(delta) { [acc, getChannelName, getIntegerValue] ref in
            guard let name = getChannelName(ref)?.takeUnretainedValue() else { return 0 }
            var unused: Int32 = 0
            let mj = Double(getIntegerValue(ref, &unused))

            // Use only the aggregate rollup channels to avoid double-counting.
            // Confirmed channel names from IOReport on M4/macOS 15:
            //   "CPU Energy" = ECPU + PCPU cluster total (mJ delta)
            //   "GPU"        = GPU core energy (mJ delta)  — NOT "GPU Energy" (monotonic μJ)
            //   "ANE"        = Neural Engine (mJ delta)
            switch name as String {
            case "CPU Energy": acc.cpu += mj
            case "GPU":        acc.gpu += mj
            case "ANE":        acc.ane += mj
            default:           break
            }
            return 0  // kIOReportIterOk
        }

        // mJ / elapsed_s / 1000 = W
        let scale = 1.0 / (elapsed * 1_000.0)
        return PowerState(
            cpuWatts: (acc.cpu * scale).clamped(to: 0...300),
            gpuWatts: (acc.gpu * scale).clamped(to: 0...150),
            aneWatts: (acc.ane * scale).clamped(to: 0...30)
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
