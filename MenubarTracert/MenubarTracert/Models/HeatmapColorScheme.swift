import SwiftUI
import AppKit

enum HeatmapColorScheme: String, CaseIterable, Identifiable {
    case oceanic, thermal, verdant, grayscale, sunset, arctic
    case classic, hotPink, synthwave, skyrose, grape

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oceanic:   return "Oceanic"
        case .thermal:   return "Thermal"
        case .verdant:   return "Verdant"
        case .grayscale: return "Grayscale"
        case .sunset:    return "Sunset"
        case .arctic:    return "Arctic"
        case .classic:   return "Classic"
        case .hotPink:   return "Hot Pink"
        case .synthwave: return "Synthwave"
        case .skyrose:     return "Sky Rose"
        case .grape:     return "Grape"
        }
    }

    private typealias RGB = (CGFloat, CGFloat, CGFloat)

    // Color stops from good (0ms) to bad (100ms+). 2 or 3 stops supported.
    private var stops: [RGB] {
        switch self {
        case .oceanic:
            return [(0.08, 0.55, 0.50),   // darker teal
                    (0.22, 0.74, 0.97),   // sky
                    (0.98, 0.68, 0.12)]   // light amber
        case .thermal:
            return [(0.46, 0.50, 0.87),   // dark indigo
                    (0.75, 0.52, 0.99),   // purple
                    (0.98, 0.55, 0.78)]   // light pink
        case .verdant:
            return [(0.20, 0.83, 0.60),   // emerald
                    (0.64, 0.90, 0.21),   // lime
                    (0.98, 0.75, 0.14)]   // amber
        case .grayscale:
            return [(0.85, 0.87, 0.89),   // light silver
                    (0.50, 0.52, 0.55),   // mid gray
                    (0.18, 0.20, 0.24)]   // near-black
        case .sunset:
            return [(0.99, 0.73, 0.45),   // peach
                    (0.98, 0.44, 0.52),   // coral
                    (0.86, 0.15, 0.15)]   // deep red
        case .arctic:
            return [(0.73, 0.90, 0.99),   // ice blue
                    (0.35, 0.52, 0.70),   // slate blue
                    (0.10, 0.15, 0.25)]   // deep navy
        case .classic:
            return [(0.0, 0.8, 0.0),      // green
                    (0.9, 0.0, 0.0)]      // red
        case .hotPink:
            return [(0.94, 0.20, 0.69),   // #EF33B1
                    (0.96, 0.90, 0.74)]   // #F6E6BC
        case .synthwave:
            return [(0.76, 0.18, 0.82),   // #C22ED0
                    (0.37, 0.98, 0.88)]   // #5FFAE0
        case .skyrose:
            return [(0.05, 0.48, 0.70),   // #0C7BB3
                    (0.95, 0.73, 0.91)]   // #F2BAE8
        case .grape:
            return [(0.34, 0.07, 0.42),   // #58126A
                    (0.96, 0.70, 0.88)]   // #F6B2E1
        }
    }

    var timeoutColor: Color {
        switch self {
        case .oceanic:   return Color(red: 0.12, green: 0.16, blue: 0.23)
        case .thermal:   return Color.black
        case .verdant:   return Color(red: 0.22, green: 0.25, blue: 0.32)
        case .grayscale: return Color(red: 0.07, green: 0.09, blue: 0.15)
        case .sunset:    return Color(red: 0.27, green: 0.10, blue: 0.01)
        case .arctic:    return Color(red: 0.06, green: 0.09, blue: 0.16)
        case .classic:   return Color.black
        case .hotPink:   return Color(red: 0.15, green: 0.05, blue: 0.10)
        case .synthwave: return Color(red: 0.10, green: 0.02, blue: 0.12)
        case .skyrose:     return Color(red: 0.03, green: 0.10, blue: 0.15)
        case .grape:     return Color(red: 0.10, green: 0.02, blue: 0.12)
        }
    }

    var timeoutNSColor: NSColor {
        switch self {
        case .oceanic:   return NSColor(red: 0.12, green: 0.16, blue: 0.23, alpha: 1)
        case .thermal:   return .black
        case .verdant:   return NSColor(red: 0.22, green: 0.25, blue: 0.32, alpha: 1)
        case .grayscale: return NSColor(red: 0.07, green: 0.09, blue: 0.15, alpha: 1)
        case .sunset:    return NSColor(red: 0.27, green: 0.10, blue: 0.01, alpha: 1)
        case .arctic:    return NSColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1)
        case .classic:   return .black
        case .hotPink:   return NSColor(red: 0.15, green: 0.05, blue: 0.10, alpha: 1)
        case .synthwave: return NSColor(red: 0.10, green: 0.02, blue: 0.12, alpha: 1)
        case .skyrose:     return NSColor(red: 0.03, green: 0.10, blue: 0.15, alpha: 1)
        case .grape:     return NSColor(red: 0.10, green: 0.02, blue: 0.12, alpha: 1)
        }
    }

    func color(for ms: Double) -> Color {
        let (r, g, b) = interpolatedRGB(for: ms)
        return Color(red: r, green: g, blue: b)
    }

    func nsColor(for ms: Double) -> NSColor {
        let (r, g, b) = interpolatedRGB(for: ms)
        return NSColor(red: r, green: g, blue: b, alpha: 1)
    }

    private func interpolatedRGB(for ms: Double) -> (CGFloat, CGFloat, CGFloat) {
        let s = stops
        let t = min(max(ms / 100.0, 0), 1.0)

        if s.count == 2 {
            return (lerp(s[0].0, s[1].0, t),
                    lerp(s[0].1, s[1].1, t),
                    lerp(s[0].2, s[1].2, t))
        } else {
            if t < 0.5 {
                let f = t / 0.5
                return (lerp(s[0].0, s[1].0, f),
                        lerp(s[0].1, s[1].1, f),
                        lerp(s[0].2, s[1].2, f))
            } else {
                let f = (t - 0.5) / 0.5
                return (lerp(s[1].0, s[2].0, f),
                        lerp(s[1].1, s[2].1, f),
                        lerp(s[1].2, s[2].2, f))
            }
        }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }
}
