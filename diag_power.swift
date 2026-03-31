#!/usr/bin/swift
// Run: swift /Users/baileykiehl/Desktop/Project\ Aqua/diag_power.swift
import Foundation

typealias CopyChannelsT = @convention(c) (CFString?, CFString?, UInt32, UInt32, UInt32) -> Unmanaged<CFMutableDictionary>?
typealias CreateSubT    = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?) -> UnsafeMutableRawPointer?
typealias CreateSampT   = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
typealias CreateDeltaT  = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
typealias IterateT      = @convention(c) (CFDictionary, @convention(block)(UnsafeRawPointer) -> Int32) -> Void
typealias GetStrT       = @convention(c) (UnsafeRawPointer) -> Unmanaged<CFString>?
typealias GetIntT       = @convention(c) (UnsafeRawPointer, UnsafeMutablePointer<Int32>) -> Int64

guard let lib = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY) else {
    print("❌ dlopen FAILED: \(String(cString: dlerror()))")
    exit(1)
}
print("✅ dlopen OK")

func sym<T>(_ name: String) -> T? {
    guard let p = dlsym(lib, name) else { print("  ❌ missing: \(name)"); return nil }
    print("  ✅ \(name)")
    return unsafeBitCast(p, to: T.self)
}

print("\nSymbols:")
guard let copyChannels: CopyChannelsT = sym("IOReportCopyChannelsInGroup"),
      let createSub:    CreateSubT    = sym("IOReportCreateSubscription"),
      let createSamp:   CreateSampT   = sym("IOReportCreateSamples"),
      let createDelta:  CreateDeltaT  = sym("IOReportCreateSamplesDelta"),
      let iterate:      IterateT      = sym("IOReportIterate"),
      let getGroup:     GetStrT       = sym("IOReportChannelGetGroup"),
      let getName:      GetStrT       = sym("IOReportChannelGetChannelName"),
      let getInt:       GetIntT       = sym("IOReportSimpleGetIntegerValue")
else { print("❌ Missing symbols — cannot continue"); exit(1) }

// Try a few group names
let groups: [String?] = ["Energy Model", "CPU Stats", "GPU Stats", nil]
for grpName in groups {
    let label = grpName ?? "<all channels>"
    let cfName = grpName.map { $0 as CFString }
    guard let ch = copyChannels(cfName, nil, 0, 0, 0)?.takeRetainedValue() else {
        print("\n⚠️  copyChannels(\"\(label)\") → nil")
        continue
    }
    print("\n✅ copyChannels(\"\(label)\") → got channels dict")

    var subbedRef: Unmanaged<CFMutableDictionary>? = nil
    guard let sub = createSub(nil, ch, &subbedRef, 0, nil) else {
        print("  ❌ createSubscription returned nil")
        continue
    }
    let subbed = subbedRef?.takeRetainedValue()
    guard let sc = subbed else { print("  ❌ subbedChannels nil"); continue }
    print("  ✅ subscription created")

    guard let s1 = createSamp(sub, sc, nil)?.takeRetainedValue() else {
        print("  ❌ first sample nil"); continue
    }
    print("  ✅ first sample OK — sleeping 1s...")
    Thread.sleep(forTimeInterval: 1.0)

    guard let s2 = createSamp(sub, sc, nil)?.takeRetainedValue() else {
        print("  ❌ second sample nil"); continue
    }
    guard let delta = createDelta(s1, s2, nil)?.takeRetainedValue() else {
        print("  ❌ delta nil"); continue
    }
    print("  ✅ delta OK — channels found:")

    var count = 0
    iterate(delta) { ref in
        let grp  = (getGroup(ref)?.takeUnretainedValue()) as String? ?? "?"
        let name = (getName(ref)?.takeUnretainedValue()) as String? ?? "?"
        var u: Int32 = 0
        let val = getInt(ref, &u)
        print("    [\(grp)] \(name) = \(val)  (unit=\(u))")
        count += 1
        return 0
    }
    print("  Total channels: \(count)")
    if grpName != nil { break }  // found one that works
}
