import SwiftUI

// MARK: - GPUBarsView
// Dot-matrix histogram: columns = time (oldest left → newest right),
// rows = load level (0% bottom → 100% top). Lit cells grow upward.

struct GPUBarsView: View {
    let gpu: GPUState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Grid geometry
    private let rowCount: Int    = 20
    private let cellSize: CGFloat = 3.5
    private let cellGap:  CGFloat = 1.5

    private var gridHeight: CGFloat {
        CGFloat(rowCount) * (cellSize + cellGap) - cellGap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            dotMatrix
        }
    }

    // MARK: - Dot matrix

    private var dotMatrix: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                // Always use exactly sparklineHistory columns stretched to fill
                // the available width — grid is always wall-to-wall.
                let cols    = TahoeTokens.Timing.sparklineHistory
                let history = paddedHistory(cols: cols)
                let tint    = TahoeTokens.Color.gpuTint

                // Stretch step so cols * step == size.width exactly.
                let step  = size.width / CGFloat(cols)
                let cellW = max(step - cellGap, 2)

                for col in 0 ..< cols {
                    let load    = history[col]
                    let litRows = Int((load / 100.0) * Double(rowCount) + 0.5)

                    for row in 0 ..< rowCount {
                        let x    = CGFloat(col) * step
                        let y    = CGFloat(row) * (cellSize + cellGap)
                        let rect = CGRect(x: x, y: y, width: cellW, height: cellSize)
                        let path = Path(roundedRect: rect, cornerRadius: 1.0)

                        let isLit   = row >= rowCount - litRows
                        let isCrest = row == rowCount - litRows

                        if isLit {
                            ctx.fill(path, with: .color(tint.opacity(isCrest ? 0.95 : 0.65)))
                        } else {
                            ctx.fill(path, with: .color(Color.white.opacity(0.05)))
                        }
                    }
                }
            }
        }
        .frame(height: gridHeight)
        // Overlay: overall % badge bottom-right
        .overlay(alignment: .bottomTrailing) {
            Text(String(format: "%.0f%%", gpu.utilization))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(TahoeTokens.Color.gpuTint.opacity(0.9))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background {
                    Capsule(style: .continuous)
                        .fill(TahoeTokens.Color.gpuTint.opacity(0.13))
                }
        }
    }

    // MARK: - Helpers

    private func paddedHistory(cols: Int) -> [Double] {
        let h = gpu.history
        guard h.count < cols else { return Array(h.suffix(cols)) }
        return Array(repeating: 0.0, count: cols - h.count) + h
    }
}
