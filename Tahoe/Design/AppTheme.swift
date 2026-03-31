import SwiftUI

// MARK: - Theme enum

enum AppTheme: Int, CaseIterable {
    case tahoe   = 0   // Bubbly, tinted glass, spring animations (default)
    case capitan = 1   // El Capitan — frosted glass, 200-weight numerals, clean edges

    var displayName: String {
        switch self {
        case .tahoe:   return "Tahoe"
        case .capitan: return "Capitan"
        }
    }
}

enum AppColorMode: Int, CaseIterable {
    case light = 0
    case dark = 1

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark:  return "Dark"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark:  return .dark
        }
    }
}

// MARK: - SwiftUI environment key

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .tahoe
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Theme-aware token accessors

extension AppTheme {
    var heroValueFont: Font {
        switch self {
        case .tahoe:   return TahoeTokens.FontStyle.heroValue                             // .light (300)
        case .capitan: return .system(size: 36, weight: .ultraLight, design: .default)   // 200-weight
        }
    }

    var cardFill: (Color, Double) -> Color {
        switch self {
        case .tahoe:
            return { color, base in color.opacity(base) }
        case .capitan:
            // Capitan cards are nearly-neutral — just a hint of tint
            return { color, _ in color.opacity(0.04) }
        }
    }

    var cardMaterial: Material {
        switch self {
        case .tahoe:   return .ultraThinMaterial
        case .capitan: return .thickMaterial
        }
    }

    var shimmerOpacity: Double {
        // Tahoe has the "lickable" top-edge shimmer; Capitan is flat
        switch self {
        case .tahoe:   return 0.6
        case .capitan: return 0.0
        }
    }

    var cardBorderOpacity: Double {
        switch self {
        case .tahoe:   return 0.15
        case .capitan: return 0.10
        }
    }

    var usesSpringAnimation: Bool {
        switch self {
        case .tahoe:   return true
        case .capitan: return false
        }
    }
}
