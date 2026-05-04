import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Design Tokens System for RooMate (Modern Design)

struct DesignTokens {
    // MARK: - Colors (Modern, Clean Palette)
    struct Colors {
        // Primary: Modern teal-blue
        static let primary = Color(red: 0.20, green: 0.60, blue: 0.85)
        // Accent: Vibrant orange-red
        static let accent = Color(red: 0.95, green: 0.45, blue: 0.35)
        // Success: Fresh green
        static let success = Color(red: 0.25, green: 0.78, blue: 0.50)
        // Warning: Warm amber
        static let warning = Color(red: 0.95, green: 0.70, blue: 0.20)
        // Destructive: Red
        static let destructive = Color(red: 0.95, green: 0.28, blue: 0.28)
    }
    
    // MARK: - Typography (Modern & Clean)
    struct Typography {
        static let headline2 = Font.system(size: 28, weight: .bold, design: .default)
        static let headline3 = Font.system(size: 22, weight: .semibold, design: .default)
        static let title = Font.system(size: 18, weight: .semibold, design: .default)
        static let body = Font.system(size: 16, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
        static let caption = Font.system(size: 13, weight: .regular, design: .default)

        /// Brand-only display font with a Sofia Pro Black preference and a system fallback.
        static func brandTitle(size: CGFloat = 28) -> Font {
#if canImport(AppKit)
            if let font = NSFont(name: "Sofia Pro Black", size: size) {
                return Font(font)
            }
            return .system(size: size, weight: .black, design: .default)
#elseif canImport(UIKit)
            if let font = UIFont(name: "Sofia Pro Black", size: size) {
                return Font(font)
            }
            return .system(size: size, weight: .black, design: .default)
#else
            return .system(size: size, weight: .black, design: .default)
#endif
        }
    }
    
    // MARK: - Spacing (Generous, Modern)
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
    
    // MARK: - Corner Radius (Modern, Rounded)
    struct Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
    }
    
    // MARK: - Shadows (Subtle, Modern)
    struct Shadows {
        static let subtle = Shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
        static let small = Shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        static let medium = Shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        static let large = Shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 8)
    }
    
    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
    
    // MARK: - Animation (Smooth, Contemporary)
    struct Animation {
        static let snappy = SwiftUI.Animation.snappy(duration: 0.25)
        static let smooth = SwiftUI.Animation.smooth(duration: 0.35)
    }
}

// MARK: - View Extensions
extension View {
    func designShadow(_ shadow: DesignTokens.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
