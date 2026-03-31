import SwiftUI
import AppKit

// MARK: - NSVisualEffectView bridge

struct VisualEffectView: NSViewRepresentable {
    var material:     NSVisualEffectView.Material     = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material     = material
        v.blendingMode = blendingMode
        v.state        = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material     = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Window configurator
//
// Runs once on makeNSView and on every updateNSView so settings take
// effect immediately without a relaunch.

struct WindowConfigurator: NSViewRepresentable {
    let floating:      Bool
    let autosaveName:  String

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { configure(v) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView) }
    }

    private func configure(_ v: NSView) {
        guard let window = v.window else { return }
        window.level                       = floating ? .floating : .normal
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent  = true
        window.backgroundColor             = .clear
        window.minSize                     = CGSize(width: 420, height: 180)

        // Position + size persistence — save/restore across launches
        if !autosaveName.isEmpty, window.frameAutosaveName != autosaveName {
            window.setFrameAutosaveName(autosaveName)
        }
    }
}

extension View {
    /// Configures the hosting NSWindow: floating level + frame persistence.
    func configuredWindow(floating: Bool = true, autosaveName: String = "") -> some View {
        background(
            WindowConfigurator(floating: floating, autosaveName: autosaveName)
                .frame(width: 0, height: 0)
        )
    }
}
