import SwiftUI

enum TahoeTokens {
    enum Color {
        static let cpuTint   = SwiftUI.Color(red: 0.04, green: 0.48, blue: 1.0)
        static let gpuTint   = SwiftUI.Color(red: 0.55, green: 0.31, blue: 0.78)
        static let memTint   = SwiftUI.Color(red: 0.19, green: 0.69, blue: 0.31)
        static let pwrTint   = SwiftUI.Color(red: 0.94, green: 0.47, blue: 0.13)
        static let diskTint  = SwiftUI.Color(red: 0.18, green: 0.74, blue: 0.82)
        static let netTint   = SwiftUI.Color(red: 0.96, green: 0.77, blue: 0.19)
        static let tempTint  = SwiftUI.Color(red: 0.91, green: 0.38, blue: 0.22)
        static let danger    = SwiftUI.Color(red: 0.91, green: 0.21, blue: 0.17)
        static let warning   = SwiftUI.Color(red: 1.0,  green: 0.58, blue: 0.0)
    }
    enum Radius {
        static let window: CGFloat = 24
        static let card: CGFloat   = 20
        static let pill: CGFloat   = 12
        static let bar: CGFloat    = 6
    }
    enum FontStyle {
        static let heroValue = SwiftUI.Font.system(size: 36, weight: .light,    design: .default)
        static let heroUnit  = SwiftUI.Font.system(size: 14, weight: .regular,  design: .default)
        static let label     = SwiftUI.Font.system(size: 10, weight: .semibold, design: .default)
        static let body      = SwiftUI.Font.system(size: 11, weight: .regular,  design: .default)
        static let pill      = SwiftUI.Font.system(size: 10, weight: .medium,   design: .default)
    }
    enum Timing {
        static var pollInterval: TimeInterval {
            let stored = UserDefaults.standard.double(forKey: "pollInterval")
            return stored > 0 ? stored : 1.0
        }
        static let sparklineHistory = 40
    }
    enum Alert {
        static let cpuDefault:   Double = 90
        static let memDefault:   Double = 90
        static let diskDefault:  Double = 200   // MB/s total I/O
        static let tempDefault:  Double = 90    // °C
    }
}
