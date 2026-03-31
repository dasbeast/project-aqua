import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @EnvironmentObject var updater: AppUpdater

    @State private var launchAtLogin = false
    @State private var loginError:   String? = nil

    @AppStorage("alwaysOnTop")        private var alwaysOnTop    = true
    @AppStorage("compactMode")        private var compactMode    = false
    @AppStorage("uiTheme")            private var uiThemeRaw     = AppTheme.tahoe.rawValue
    @AppStorage("pollInterval")       private var pollInterval   = 1.0

    @AppStorage("alertCPUEnabled")    private var alertCPU       = false
    @AppStorage("alertCPUThreshold")  private var cpuThreshold   = TahoeTokens.Alert.cpuDefault
    @AppStorage("alertMemEnabled")    private var alertMem       = false
    @AppStorage("alertMemThreshold")  private var memThreshold   = TahoeTokens.Alert.memDefault
    @AppStorage("alertDiskEnabled")   private var alertDisk      = false
    @AppStorage("alertDiskThreshold") private var diskThreshold  = TahoeTokens.Alert.diskDefault
    @AppStorage("alertTempEnabled")   private var alertTemp      = false
    @AppStorage("alertTempThreshold") private var tempThreshold  = TahoeTokens.Alert.tempDefault

    private var uiTheme: Binding<AppTheme> {
        Binding(
            get: { AppTheme(rawValue: uiThemeRaw) ?? .tahoe },
            set: { uiThemeRaw = $0.rawValue }
        )
    }

    private let intervalOptions: [(label: String, value: Double)] = [
        ("0.25 s", 0.25), ("0.5 s", 0.5), ("1 s", 1.0), ("2 s", 2.0), ("5 s", 5.0)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                sectionHeader("General")

                Toggle(isOn: $launchAtLogin) {
                    settingLabel("Launch at Login", icon: "power")
                }
                .onChange(of: launchAtLogin, setLoginItem)
                .padding(.bottom, 8)

                Toggle(isOn: $alwaysOnTop) {
                    settingLabel("Float Above Other Windows", icon: "square.3.layers.3d.top.filled")
                }
                .padding(.bottom, 8)

                Toggle(isOn: $compactMode) {
                    settingLabel("Compact Mode", icon: "rectangle.compress.vertical")
                }

                if let err = loginError {
                    Text(err).font(TahoeTokens.FontStyle.body)
                        .foregroundStyle(TahoeTokens.Color.danger).padding(.top, 6)
                }

                divider

                sectionHeader("Appearance")

                HStack {
                    settingLabel("Theme", icon: "paintbrush")
                    Spacer()
                    Picker("", selection: uiTheme) {
                        ForEach(AppTheme.allCases, id: \.rawValue) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }

                divider

                sectionHeader("Polling")

                HStack {
                    settingLabel("Interval", icon: "timer")
                    Spacer()
                    Picker("", selection: $pollInterval) {
                        ForEach(intervalOptions, id: \.value) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                divider

                sectionHeader("Alerts")

                alertRow(label: "CPU",      icon: "cpu",
                         enabled: $alertCPU,  threshold: $cpuThreshold,
                         range: 50...100,     unit: "%")
                alertRow(label: "Memory",   icon: "memorychip",
                         enabled: $alertMem,  threshold: $memThreshold,
                         range: 50...100,     unit: "%")
                alertRow(label: "Disk I/O", icon: "internaldrive",
                         enabled: $alertDisk, threshold: $diskThreshold,
                         range: 50...500,     unit: " MB/s")
                alertRow(label: "CPU Temp", icon: "thermometer.medium",
                         enabled: $alertTemp, threshold: $tempThreshold,
                         range: 60...110,     unit: "°C")

                divider

                sectionHeader("Updates")

                UpdaterSettingsView(
                    updater: updater.updater,
                    configurationError: updater.configurationError
                )

                divider

                sectionHeader("Data")

                Button { copySnapshot() } label: {
                    HStack {
                        Image(systemName: "doc.on.clipboard").font(.system(size: 11)).frame(width: 16)
                        Text("Copy Snapshot to Clipboard").font(TahoeTokens.FontStyle.body)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(TahoeTokens.Color.cpuTint)
                .keyboardShortcut("c", modifiers: [.command, .shift])

                divider

                HStack {
                    Text("Aqua · v0.0.6 · Project Aqua")
                        .font(TahoeTokens.FontStyle.body).foregroundStyle(.quaternary)
                    Spacer()
                }
            }
            .padding(16)
        }
        .frame(width: 300, height: 560)
        .onAppear { syncLoginState() }
    }

    // MARK: - Section helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(TahoeTokens.FontStyle.label).foregroundStyle(.tertiary)
            .textCase(.uppercase).kerning(0.8).padding(.bottom, 8)
    }

    @ViewBuilder
    private func settingLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
            Text(text).font(TahoeTokens.FontStyle.body)
        }
    }

    @ViewBuilder
    private func alertRow(
        label: String, icon: String,
        enabled: Binding<Bool>, threshold: Binding<Double>,
        range: ClosedRange<Double>, unit: String
    ) -> some View {
        VStack(spacing: 4) {
            Toggle(isOn: enabled) { settingLabel(label, icon: icon) }
            if enabled.wrappedValue {
                HStack {
                    Slider(value: threshold, in: range, step: 5)
                    Text(String(format: "%.0f\(unit)", threshold.wrappedValue))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                }
                .padding(.leading, 23)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.bottom, 6)
        .animation(.easeOut(duration: 0.2), value: enabled.wrappedValue)
    }

    private var divider: some View { Divider().padding(.vertical, 10) }

    // MARK: - Actions

    private func copySnapshot() {
        let text = monitor.snapshot()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func syncLoginState() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func setLoginItem(old: Bool, new: Bool) {
        loginError = nil
        do {
            if new { try SMAppService.mainApp.register() }
            else   { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = !new
        }
    }
}
