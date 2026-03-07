import Testing
import AppKit
@testable import TraceBar

@Suite("HeatmapColorScheme")
struct HeatmapColorSchemeTests {

    private func rgb(_ color: NSColor) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let c = color.usingColorSpace(.sRGB)!
        return (c.redComponent, c.greenComponent, c.blueComponent)
    }

    private func assertClose(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 0.01,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(a - b) < tolerance, "Expected \(a) to be close to \(b)", sourceLocation: sourceLocation)
    }

    // MARK: - Boundary colors (t=0 and t=1)

    @Test func classicAtZeroIsGreen() {
        let c = rgb(HeatmapColorScheme.classic.nsColor(for: 0, maxMs: 100))
        assertClose(c.r, 0.0)
        assertClose(c.g, 0.8)
        assertClose(c.b, 0.0)
    }

    @Test func classicAtMaxIsRed() {
        let c = rgb(HeatmapColorScheme.classic.nsColor(for: 100, maxMs: 100))
        assertClose(c.r, 0.9)
        assertClose(c.g, 0.0)
        assertClose(c.b, 0.0)
    }

    @Test func hotDogStandAtZeroIsYellow() {
        let c = rgb(HeatmapColorScheme.hotDogStand.nsColor(for: 0, maxMs: 100))
        assertClose(c.r, 1.0)
        assertClose(c.g, 1.0)
        assertClose(c.b, 0.0)
    }

    @Test func hotDogStandAtMaxIsRed() {
        let c = rgb(HeatmapColorScheme.hotDogStand.nsColor(for: 100, maxMs: 100))
        assertClose(c.r, 1.0)
        assertClose(c.g, 0.0)
        assertClose(c.b, 0.0)
    }

    // MARK: - Midpoint for 2-stop scheme

    @Test func hotPinkMidpointInterpolates() {
        // hotPink: cream (0.96, 0.90, 0.74) -> hot pink (0.94, 0.20, 0.69)
        let c = rgb(HeatmapColorScheme.hotPink.nsColor(for: 50, maxMs: 100))
        // At t=0.5: lerp between the two stops
        assertClose(c.r, (0.96 + 0.94) / 2)
        assertClose(c.g, (0.90 + 0.20) / 2)
        assertClose(c.b, (0.74 + 0.69) / 2)
    }

    // MARK: - Midpoint for 3-stop scheme (t=0.5 should be the middle stop)

    @Test func classicMidpointIsYellow() {
        // classic: green -> yellow -> red, midpoint = yellow
        let c = rgb(HeatmapColorScheme.classic.nsColor(for: 50, maxMs: 100))
        assertClose(c.r, 0.95)
        assertClose(c.g, 0.85)
        assertClose(c.b, 0.10)
    }

    // MARK: - Clamping

    @Test func negativeLatencyClampsToZero() {
        let atZero = rgb(HeatmapColorScheme.classic.nsColor(for: 0, maxMs: 100))
        let atNeg = rgb(HeatmapColorScheme.classic.nsColor(for: -50, maxMs: 100))
        assertClose(atZero.r, atNeg.r)
        assertClose(atZero.g, atNeg.g)
        assertClose(atZero.b, atNeg.b)
    }

    @Test func latencyBeyondMaxClampsToOne() {
        let atMax = rgb(HeatmapColorScheme.classic.nsColor(for: 100, maxMs: 100))
        let beyond = rgb(HeatmapColorScheme.classic.nsColor(for: 500, maxMs: 100))
        assertClose(atMax.r, beyond.r)
        assertClose(atMax.g, beyond.g)
        assertClose(atMax.b, beyond.b)
    }

    // MARK: - maxMs scaling

    @Test func differentMaxMsScalesCorrectly() {
        // 50ms with maxMs=100 should equal 25ms with maxMs=50 (both t=0.5)
        let a = rgb(HeatmapColorScheme.lagoon.nsColor(for: 50, maxMs: 100))
        let b = rgb(HeatmapColorScheme.lagoon.nsColor(for: 25, maxMs: 50))
        assertClose(a.r, b.r)
        assertClose(a.g, b.g)
        assertClose(a.b, b.b)
    }

    // MARK: - All schemes produce valid colors

    @Test func allSchemesProduceValidColorsAtBoundaries() {
        for scheme in HeatmapColorScheme.allCases {
            for ms in [0.0, 50.0, 100.0] {
                let c = rgb(scheme.nsColor(for: ms, maxMs: 100))
                #expect(c.r >= 0 && c.r <= 1, "\(scheme.rawValue) red out of range at \(ms)ms")
                #expect(c.g >= 0 && c.g <= 1, "\(scheme.rawValue) green out of range at \(ms)ms")
                #expect(c.b >= 0 && c.b <= 1, "\(scheme.rawValue) blue out of range at \(ms)ms")
            }
        }
    }

    // MARK: - Monotonic interpolation (colors change smoothly)

    @Test func classicRedIncreasesWithLatency() {
        let low = rgb(HeatmapColorScheme.classic.nsColor(for: 10, maxMs: 100))
        let high = rgb(HeatmapColorScheme.classic.nsColor(for: 90, maxMs: 100))
        #expect(high.r > low.r, "Red should increase with latency for classic scheme")
    }
}
