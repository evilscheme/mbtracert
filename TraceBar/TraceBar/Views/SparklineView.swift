import SwiftUI
import AppKit

struct SparklineLabel: View {
    let probes: [ProbeResult]
    let now: Date
    let historyMinutes: Double
    let colorScheme: HeatmapColorScheme
    let latencyThreshold: Double
    let chartMode: ChartMode
    var showBackground: Bool = true
    var latencyMs: Double?

    private let chartWidth: CGFloat = 32
    private let chartHeight: CGFloat = 24
    private let fontSize: CGFloat = 10
    private let gap: CGFloat = 2

    var body: some View {
        Image(nsImage: renderLabel())
    }

    private func renderLabel() -> NSImage {
        let text = latencyText
        let textAttrs = textAttributes(for: latencyMs)
        let textSize = (text as NSString).size(withAttributes: textAttrs)
        let refWidth = ("000ms" as NSString).size(withAttributes: textAttrs).width

        let totalWidth = chartWidth + gap + ceil(refWidth)
        let image = NSImage(size: NSSize(width: totalWidth, height: chartHeight))
        image.lockFocus()
        defer { image.unlockFocus() }

        // Chart: render SwiftUI chart view into the left portion
        let chartImage = renderChartImage()
        chartImage.draw(in: NSRect(x: 0, y: 0, width: chartWidth, height: chartHeight))

        // Text: draw right-aligned within fixed-width area (bypasses system font minimum)
        let textX = chartWidth + gap + ceil(refWidth) - ceil(textSize.width)
        let textY = (chartHeight - textSize.height) / 2
        (text as NSString).draw(
            at: NSPoint(x: textX, y: textY),
            withAttributes: textAttrs
        )

        return image
    }

    private func renderChartImage() -> NSImage {
        let content = chartContent
            .frame(width: chartWidth, height: chartHeight)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .background {
                if showBackground {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colorScheme.menuBarBackground)
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                }
            }

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0

        guard let image = renderer.nsImage else {
            return NSImage(size: NSSize(width: chartWidth, height: chartHeight))
        }
        return image
    }

    @ViewBuilder
    private var chartContent: some View {
        switch chartMode {
        case .sparkline:
            SparklineBar(probes: probes, now: now, historyMinutes: historyMinutes, colorScheme: colorScheme, latencyThreshold: latencyThreshold)
        case .heatmap:
            HeatmapBar(probes: probes, now: now, historyMinutes: historyMinutes, colorScheme: colorScheme, latencyThreshold: latencyThreshold)
        case .bars:
            VerticalBarsBar(probes: probes, now: now, historyMinutes: historyMinutes, colorScheme: colorScheme, latencyThreshold: latencyThreshold)
        }
    }

    private var latencyText: String {
        if let ms = latencyMs {
            return String(format: "%.0fms", ms)
        }
        return "--ms"
    }

    private func textAttributes(for ms: Double?) -> [NSAttributedString.Key: Any] {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        let color: NSColor = ms != nil ? .white : .secondaryLabelColor
        return [.font: font, .foregroundColor: color]
    }
}
