import SwiftUI
import UIKit

/// Central design tokens. Views use these instead of literal colors/sizes so the visual
/// language stays consistent and dark/light mode are handled in one place.
enum Theme {
    enum Palette {
        static let background = Color(light: 0xF4F4F7, dark: 0x0A0A0D)
        static let surface = Color(light: 0xFFFFFF, dark: 0x15151B)
        static let surfaceElevated = Color(light: 0xECECF1, dark: 0x1F1F28)
        static let hairline = Color(light: 0x000000, dark: 0xFFFFFF).opacity(0.08)

        static let textPrimary = Color(light: 0x0B0B10, dark: 0xF5F5F7)
        static let textSecondary = Color(light: 0x5B5B66, dark: 0x9A9AA8)
        static let textTertiary = Color(light: 0x8E8E99, dark: 0x5E5E6B)

        /// Brand "ember" — streaks, primary actions.
        static let accent = Color(light: 0xF2541B, dark: 0xFF6B2C)
        static let accentSecondary = Color(light: 0xE0A400, dark: 0xFFC53D)
        static let success = Color(light: 0x0F9F6E, dark: 0x34D399)
        static let warning = Color(light: 0xC77700, dark: 0xFBBF24)
        static let danger = Color(light: 0xD93636, dark: 0xF87171)
        static let info = Color(light: 0x2563EB, dark: 0x60A5FA)

        static let emberGradient = LinearGradient(
            colors: [accentSecondary, accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
    }

    enum Typography {
        static let hero = Font.system(size: 40, weight: .heavy, design: .rounded)
        static let title = Font.system(.title, design: .rounded).weight(.bold)
        static let title2 = Font.system(.title2, design: .rounded).weight(.bold)
        static let headline = Font.system(.headline, design: .rounded)
        static let body = Font.system(.body, design: .rounded)
        static let callout = Font.system(.callout, design: .rounded)
        static let caption = Font.system(.caption, design: .rounded).weight(.medium)
        /// Uppercase section labels such as "TODAY" or "WEEKLY GOALS".
        static let eyebrow = Font.system(.caption, design: .rounded).weight(.bold)
        static let metric = Font.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit()
    }
}

extension Color {
    /// A color that adapts to the current interface style.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// User-selectable appearance. Dark is the default — the app is designed dark-first.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case dark, light, system

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    var title: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "System"
        }
    }
}
