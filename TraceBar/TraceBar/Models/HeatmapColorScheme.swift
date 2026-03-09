import SwiftUI
import AppKit

enum HeatmapColorScheme: String, CaseIterable, Identifiable {
    case lagoon, thermal, verdant, grayscale, grayscaleInverted, sunset, arctic
    case classic, hotPink, synthwave, skyrose, grape
    case oceanic, halloween, hotDogStand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lagoon:      return "Lagoon"
        case .thermal:     return "Thermal"
        case .verdant:     return "Verdant"
        case .grayscale:   return "Grayscale"
        case .sunset:      return "Sunset"
        case .arctic:      return "Arctic"
        case .classic:     return "Classic"
        case .hotPink:     return "Hot Pink"
        case .synthwave:   return "Synthwave"
        case .skyrose:     return "Sky Rose"
        case .grape:       return "Grape"
        case .oceanic:     return "Oceanic"
        case .halloween:   return "Halloween"
        case .hotDogStand: return "Hot Dog Stand"
        case .grayscaleInverted: return "Grayscale Inverted"
        }
    }

    private typealias RGB = (CGFloat, CGFloat, CGFloat)

    // Color stops from good (0ms) to bad (100ms+). 2 or 3 stops supported.
    private var stops: [RGB] {
        switch self {
        case .lagoon:
            return [(0.12, 0.29, 0.61),   // #1f4b9c deep blue
                    (0.22, 0.74, 0.97),   // sky blue
                    (0.98, 0.68, 0.12)]   // amber
        case .thermal:
            return [(0.29, 0.17, 0.60),   // #4a2b98 deep indigo
                    (0.88, 0.40, 0.72),   // magenta
                    (0.98, 0.60, 0.40)]   // coral
        case .verdant:
            return [(0.00, 0.40, 0.22),   // #006537 deep green
                    (0.64, 0.90, 0.21),   // lime
                    (0.98, 0.75, 0.14)]   // amber
        case .grayscale:
            return [(0.75, 0.75, 0.75),   // #c0c0c0 silver
                    (0.27, 0.27, 0.27),   // #444444 dark gray
                    (0.10, 0.10, 0.10)]   // #1a1a1a near-black
        case .sunset:
            return [(0.99, 0.73, 0.45),   // peach
                    (0.98, 0.44, 0.52),   // coral
                    (0.86, 0.15, 0.15)]   // deep red
        case .arctic:
            return [(0.60, 0.85, 0.98),   // ice blue
                    (0.32, 0.43, 0.58),   // #516e94 slate
                    (0.90, 0.70, 0.35)]   // amber
        case .classic:
            return [(0.0, 0.8, 0.0),      // green
                    (0.95, 0.85, 0.10),   // yellow
                    (0.9, 0.0, 0.0)]      // red
        case .hotPink:
            return [(0.96, 0.90, 0.74),   // cream
                    (0.94, 0.20, 0.69)]   // hot pink
        case .synthwave:
            return [(0.76, 0.18, 0.82),   // purple
                    (0.37, 0.98, 0.88)]   // cyan
        case .skyrose:
            return [(0.30, 0.72, 0.95),   // bright blue
                    (0.75, 0.65, 0.98),   // lavender
                    (0.95, 0.55, 0.75)]   // rose
        case .grape:
            return [(0.38, 0.09, 0.49),   // #61177c deep purple
                    (0.89, 0.57, 1.00)]   // bright lilac
        case .oceanic:
            return [(0.40, 0.75, 1.00),   // light blue
                    (0.10, 0.30, 0.75),   // medium blue
                    (0.03, 0.08, 0.40)]   // deep navy
        case .halloween:
            return [(1.00, 0.65, 0.00),   // bright orange
                    (0.85, 0.30, 0.00),   // dark orange
                    (0.15, 0.05, 0.00)]   // near-black
        case .hotDogStand:
            return [(1.00, 1.00, 0.00),   // yellow
                    (1.00, 0.00, 0.00)]   // red
        case .grayscaleInverted:
            return [(0.13, 0.13, 0.13),   // #444444 dark gray
                    (0.60, 0.60, 0.60),   // #999999 medium gray
                    (1.00, 1.00, 1.00)]   // #ffffff white
        }
    }

    var timeoutColor: Color {
        switch self {
        case .lagoon:      return Color(red: 0.12, green: 0.16, blue: 0.23)
        case .thermal:     return Color(red: 0.08, green: 0.05, blue: 0.15)
        case .verdant:     return Color(red: 0.22, green: 0.25, blue: 0.32)
        case .grayscale:   return Color(red: 0.10, green: 0.10, blue: 0.14)
        case .sunset:      return Color(red: 0.27, green: 0.10, blue: 0.01)
        case .arctic:      return Color(red: 0.06, green: 0.09, blue: 0.16)
        case .classic:     return Color.black
        case .hotPink:     return Color(red: 0.15, green: 0.05, blue: 0.10)
        case .synthwave:   return Color(red: 0.10, green: 0.02, blue: 0.12)
        case .skyrose:     return Color(red: 0.05, green: 0.12, blue: 0.18)
        case .grape:       return Color(red: 0.12, green: 0.05, blue: 0.15)
        case .oceanic:     return Color(red: 0.02, green: 0.02, blue: 0.12)
        case .halloween:   return Color(red: 0.05, green: 0.02, blue: 0.00)
        case .hotDogStand: return Color.black
        case .grayscaleInverted: return Color(red: 0.1, green: 0.1, blue: 0.1)
        }
    }

    /// Per-theme (download, upload) color pair for the bandwidth sparkline.
    /// Each pair is chosen to be visually distinct from each other and
    /// harmonious with the theme's latency gradient.
    /// Where possible, colors reference gradient stops directly to avoid duplication.
    private var bandwidthColors: (download: RGB, upload: RGB) {
        let s = stops
        switch self {
        case .lagoon:      return (s[1], s[2])                                     // sky blue / amber
        case .thermal:     return ((0.55, 0.25, 0.78), s[2])                       // violet / coral
        case .verdant:     return ((0.20, 0.72, 0.40), s[2])                       // green / amber
        case .grayscale:   return ((0.60, 0.60, 0.60), (0.25, 0.25, 0.25))         // light gray / dark gray
        case .sunset:      return (s[0], s[2])                                     // peach / deep red
        case .arctic:      return (s[0], s[2])                                     // ice blue / amber
        case .classic:     return ((0.00, 0.70, 0.00), s[2])                       // green / red
        case .hotPink:     return (s[0], s[1])                                     // cream / hot pink
        case .synthwave:   return (s[0], s[1])                                     // purple / cyan
        case .skyrose:     return (s[0], s[2])                                     // blue / rose
        case .grape:       return ((0.55, 0.20, 0.70), s[1])                       // deep purple / lilac
        case .oceanic:     return (s[0], (0.90, 0.55, 0.20))                       // light blue / orange
        case .halloween:   return (s[0], (0.60, 0.15, 0.00))                       // bright orange / dark orange
        case .hotDogStand: return (s[0], s[1])                                     // yellow / red
        case .grayscaleInverted: return ((0.27, 0.27, 0.27), (0.40, 0.40, 0.40))    // #444444 / #666666
        }
    }

    /// Color for download bandwidth sparkline.
    var downloadColor: Color {
        let c = bandwidthColors.download
        return Color(red: c.0, green: c.1, blue: c.2)
    }

    /// Color for upload bandwidth sparkline.
    var uploadColor: Color {
        let c = bandwidthColors.upload
        return Color(red: c.0, green: c.1, blue: c.2)
    }

    func color(for ms: Double, maxMs: Double = 100) -> Color {
        let (r, g, b) = interpolatedRGB(for: ms, maxMs: maxMs)
        return Color(red: r, green: g, blue: b)
    }

    func nsColor(for ms: Double, maxMs: Double = 100) -> NSColor {
        let (r, g, b) = interpolatedRGB(for: ms, maxMs: maxMs)
        return NSColor(red: r, green: g, blue: b, alpha: 1)
    }

    private func interpolatedRGB(for ms: Double, maxMs: Double = 100) -> (CGFloat, CGFloat, CGFloat) {
        let s = stops
        let t = min(max(ms / maxMs, 0), 1.0)

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
