import SwiftUI

@main
struct TahoeApp: App {
    @StateObject  private var monitor     = SystemMonitor.shared
    @StateObject  private var updater     = AppUpdater()
    @AppStorage("compactMode") private var compactMode = false
    @AppStorage("alwaysOnTop") private var alwaysOnTop = true
    @AppStorage("uiTheme")     private var uiThemeRaw  = AppTheme.tahoe.rawValue
    @AppStorage("followSystemAppearance") private var followSystemAppearance = true
    @AppStorage("manualColorMode")        private var manualColorModeRaw = AppColorMode.dark.rawValue

    private var theme: AppTheme { AppTheme(rawValue: uiThemeRaw) ?? .tahoe }
    private var preferredColorScheme: ColorScheme? {
        guard !followSystemAppearance else { return nil }
        return AppColorMode(rawValue: manualColorModeRaw)?.colorScheme ?? .dark
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(monitor)
                .environmentObject(updater)
                .environment(\.appTheme, theme)
                .preferredColorScheme(preferredColorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 520, height: 640)
        .commands {
            // ⌘,  → Settings (mirrors the gear button)
            CommandGroup(replacing: .appSettings) {
                EmptyView()   // SwiftUI owns ⌘, natively via the scene
            }

            CommandGroup(after: .appInfo) {
                if let sparkUpdater = updater.updater {
                    CheckForUpdatesView(updater: sparkUpdater)
                } else {
                    Button("Check for Updates…") {}
                        .disabled(true)
                }

                Divider()

                Button("Copy Snapshot") {
                    let text = monitor.snapshot()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Divider()

                Button(compactMode ? "Expand View" : "Compact View") {
                    compactMode.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button(alwaysOnTop ? "Disable Float" : "Float Above Windows") {
                    alwaysOnTop.toggle()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(monitor)
                .environmentObject(updater)
                .preferredColorScheme(preferredColorScheme)
        } label: {
            MenuBarLabel(
                cpu:    monitor.cpu.total,
                gpu:    monitor.gpu.utilization,
                memPct: monitor.memory.usedGB / max(monitor.memory.totalGB, 1) * 100,
                pwr:    monitor.power.totalWatts
            )
        }
        .menuBarExtraStyle(.window)
    }
}
