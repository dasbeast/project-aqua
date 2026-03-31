import Foundation
import UserNotifications

// MARK: - Threshold alert monitor
//
// Called once per poll cycle from SystemMonitor (background thread).
// Fires UNUserNotifications when metrics exceed configurable thresholds.
// Per-metric cooldown prevents spamming (default 5 minutes).

final class AlertMonitor {
    private var lastFired: [String: Date] = [:]
    private let cooldown: TimeInterval = 300   // 5 minutes

    // MARK: - Setup

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Check

    func check(cpu: Double, memory: Double, disk: Double, power: Double, tempC: Double) {
        let prefs = UserDefaults.standard

        if prefs.bool(forKey: "alertCPUEnabled") {
            let threshold = thresholdFor("alertCPUThreshold", default: 90)
            if cpu >= threshold {
                fire(id: "cpu", title: "CPU Pressure",
                     body: String(format: "CPU at %.0f%% (threshold %.0f%%)", cpu, threshold))
            }
        }

        if prefs.bool(forKey: "alertMemEnabled") {
            let threshold = thresholdFor("alertMemThreshold", default: 90)
            if memory >= threshold {
                fire(id: "mem", title: "Memory Pressure",
                     body: String(format: "Memory at %.0f%% (threshold %.0f%%)", memory, threshold))
            }
        }

        if prefs.bool(forKey: "alertDiskEnabled") {
            let threshold = thresholdFor("alertDiskThreshold", default: 200)   // MB/s
            if disk >= threshold {
                fire(id: "disk", title: "Disk I/O Spike",
                     body: String(format: "Disk I/O at %.0f MB/s (threshold %.0f)", disk, threshold))
            }
        }

        if prefs.bool(forKey: "alertTempEnabled") {
            let threshold = thresholdFor("alertTempThreshold", default: 90)    // °C
            if tempC > 0, tempC >= threshold {
                fire(id: "temp", title: "High CPU Temperature",
                     body: String(format: "CPU at %.0f°C (threshold %.0f°C)", tempC, threshold))
            }
        }
    }

    // MARK: - Private

    private func thresholdFor(_ key: String, default val: Double) -> Double {
        let stored = UserDefaults.standard.double(forKey: key)
        return stored > 0 ? stored : val
    }

    private func fire(id: String, title: String, body: String) {
        let now = Date()
        if let last = lastFired[id], now.timeIntervalSince(last) < cooldown { return }
        lastFired[id] = now

        let content     = UNMutableNotificationContent()
        content.title   = title
        content.body    = body
        content.sound   = .default

        let request = UNNotificationRequest(
            identifier: "tahoe.\(id).\(Int(now.timeIntervalSince1970))",
            content: content,
            trigger: nil   // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }
}
