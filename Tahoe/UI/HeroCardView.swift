import SwiftUI

struct HeroCardView: View {
    let label:    String
    let value:    String
    let unit:     String
    let subtitle: String
    let tint:     Color
    let history:  [Double]
    var onTap:    (() -> Void)? = nil

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(TahoeTokens.FontStyle.label)
                .foregroundStyle(tint.opacity(0.85))
                .kerning(0.8)
                .textCase(.uppercase)
                .padding(.bottom, 4)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(theme.heroValueFont)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .monospacedDigit()
                Text(unit)
                    .font(TahoeTokens.FontStyle.heroUnit)
                    .foregroundStyle(.secondary)
                    .baselineOffset(12)
            }

            Text(subtitle)
                .font(TahoeTokens.FontStyle.body)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            SparklineView(history: history, tint: tint,
                          accessibilityLabel: label,
                          accessibilityValue: value + unit)
                .padding(.top, 8)

            if onTap != nil {
                HStack {
                    Spacer()
                    Image(systemName: "chevron.down.circle")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(tint.opacity(isHovered ? 0.45 : 0.18))
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { glassBackground }
        .scaleEffect(isHovered && onTap != nil && !reduceMotion ? 1.012 : 1.0)
        .animation(
            reduceMotion ? nil
                : theme.usesSpringAnimation
                    ? .spring(response: 0.25, dampingFraction: 0.7)
                    : .easeOut(duration: 0.15),
            value: isHovered
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            guard onTap != nil else { return }
            isHovered = hovering
        }
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) \(unit). \(subtitle)")
        .accessibilityAddTraits(onTap != nil ? .isButton : [])
    }

    // MARK: - Liquid glass background

    @ViewBuilder
    private var glassBackground: some View {
        let radius = TahoeTokens.Radius.card

        ZStack {
            // 1. Frosted glass base — blurs whatever is behind the window
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.ultraThinMaterial)

            // 2. Very light tint wash — just enough colour, no white flare
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(tint.opacity(isHovered && onTap != nil ? 0.10 : 0.06))

            // 3. Outer border: thin tint-coloured ring
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.75)

            // 4. Inner specular highlight — top-edge only, very thin + subtle
            //    This is the "liquid" edge, not a full-card white wash.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.30),   // top highlight
                            .white.opacity(0.04),   // fade out quickly
                            .clear,
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.0
                )

            // 5. Subtle depth shadow at the bottom inner edge
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .clear,
                            .clear,
                            .black.opacity(0.08),
                            .black.opacity(0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
        }
        .shadow(
            color: tint.opacity(isHovered && onTap != nil ? 0.18 : 0.10),
            radius: 10, y: 4
        )
        .shadow(color: .black.opacity(0.20), radius: 6, y: 3)
    }
}
