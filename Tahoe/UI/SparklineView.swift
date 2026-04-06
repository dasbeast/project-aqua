import SwiftUI

struct SparklineView: View {
    let history:            [Double]
    let tint:               Color
    var height:             CGFloat = 48
    /// The value that maps to the top of the chart. Defaults to 100 (for 0–100 % metrics).
    /// Pass the rolling max for MB/s metrics so the chart scales correctly.
    var maxValue:           Double  = 100
    var accessibilityLabel: String = "Sparkline"
    var accessibilityValue: String = ""
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    // Hover tooltip state
    @State private var hoverLocation: CGFloat? = nil
    @State private var hoverValue:    Double?  = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                guard history.count > 1 else { return }
                let w        = size.width
                let h        = size.height
                let maxCount = TahoeTokens.Timing.sparklineHistory
                let step     = w / Double(maxCount - 1)
                let offset   = maxCount - history.count  // places data at right edge

                var path = Path()
                let scale = maxValue > 0 ? maxValue : 100
                for (i, v) in history.enumerated() {
                    let x = Double(i + offset) * step
                    let y = h - (v / scale) * h * 0.82 - h * 0.09
                    i == 0 ? path.move(to: CGPoint(x: x, y: y))
                           : path.addLine(to: CGPoint(x: x, y: y))
                }
                ctx.stroke(path, with: .color(tint.opacity(0.7)), lineWidth: 1.2)

                var fill = path
                fill.addLine(to: CGPoint(x: w, y: h))
                fill.addLine(to: CGPoint(x: Double(offset) * step, y: h))
                fill.closeSubpath()
                ctx.fill(fill, with: .color(tint.opacity(0.1)))

                if let last = history.last {
                    let lx  = w
                    let ly  = h - (last / scale) * h * 0.82 - h * 0.09
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: lx - 2.5, y: ly - 2.5, width: 5, height: 5)),
                        with: .color(tint.opacity(0.85))
                    )
                }

                // Hover crosshair
                if let hx = hoverLocation {
                    var line = Path()
                    line.move(to: CGPoint(x: hx, y: 0))
                    line.addLine(to: CGPoint(x: hx, y: h))
                    ctx.stroke(line, with: .color(tint.opacity(0.35)), lineWidth: 0.75)
                }
            }
            .frame(height: height)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: history.count)
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    guard history.count > 1 else { return }
                    hoverLocation = loc.x
                    // Map x position to nearest history sample
                    let frac  = loc.x / (UIHintWidth ?? 1)
                    let idx   = Int((frac * Double(history.count - 1)).rounded()).clamped(to: 0...(history.count - 1))
                    hoverValue = history[idx]
                case .ended:
                    hoverLocation = nil
                    hoverValue    = nil
                }
            }

            // Tooltip
            if let val = hoverValue, let hx = hoverLocation {
                Text(String(format: "%.1f", val))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    )
                    .offset(x: min(max(hx - 14, 0), 200), y: -20)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.1), value: hoverValue)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel + " chart")
        .accessibilityValue(
            history.isEmpty ? "No data"
            : "Current \(accessibilityValue). Min \(String(format: "%.1f", history.min() ?? 0)), Max \(String(format: "%.1f", history.max() ?? 0))"
        )
    }

    // Workaround: read parent width via GeometryReader is expensive in Canvas context;
    // use a rough constant that gets recalculated on hover event naturally via loc.x bounds.
    @State private var UIHintWidth: CGFloat? = nil
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
