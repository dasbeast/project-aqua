import SwiftUI

// MARK: - Tooltip modifier
// Shows a glass-styled label after the cursor dwells for `delay` seconds.

struct TooltipModifier: ViewModifier {
    let text:  String
    let delay: TimeInterval

    @State private var visible  = false
    @State private var workItem: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                workItem?.cancel()
                if hovering {
                    let item = DispatchWorkItem {
                        withAnimation(.easeIn(duration: 0.14)) { visible = true }
                    }
                    workItem = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
                } else {
                    withAnimation(.easeOut(duration: 0.1)) { visible = false }
                }
            }
            .overlay(alignment: .bottom) {
                if visible {
                    TooltipLabel(text: text)
                        .offset(y: tooltipOffset)
                        .allowsHitTesting(false)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)),
                                removal:   .opacity
                            )
                        )
                        .zIndex(999)
                }
            }
    }

    // Push tooltip below the element with a bit of breathing room.
    private var tooltipOffset: CGFloat { 38 }
}

// MARK: - Glass tooltip label

private struct TooltipLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: 200)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                lineWidth: 0.75
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
                    .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
            }
    }
}

// MARK: - View extension

extension View {
    func tooltip(_ text: String, delay: TimeInterval = 1.4) -> some View {
        modifier(TooltipModifier(text: text, delay: delay))
    }
}
