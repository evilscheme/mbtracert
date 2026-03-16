import SwiftUI
import AppKit

struct MenuBarView: View {
    @Environment(\.colorScheme) private var systemColorScheme

    let probes: [ProbeResult]
    let now: Date
    let historyMinutes: Double
    let colorScheme: ColorTheme
    let latencyThreshold: Double
    let chartMode: ChartMode
    var showBackground: Bool = true
    var compactMenubar: Bool = false
    var latencyMs: Double?

    // Wide mode dimensions
    private let wideChartWidth: CGFloat = 32
    private let wideChartHeight: CGFloat = 24
    private let wideFontSize: CGFloat = 10
    private let wideGap: CGFloat = 2

    // Compact mode dimensions
    private let compactChartWidth: CGFloat = 26
    private let compactChartHeight: CGFloat = 14
    private let compactFontSize: CGFloat = 7
    private let compactTotalHeight: CGFloat = 22

    var body: some View {
        Image(nsImage: compactMenubar ? renderCompactLabel() : renderWideLabel())
    }

    // MARK: - Wide layout (horizontal: chart + text side by side)

    private func renderWideLabel() -> NSImage {
        let text = latencyText
        let textAttrs = textAttributes(fontSize: wideFontSize)
        let textSize = (text as NSString).size(withAttributes: textAttrs)
        let refWidth = ("000ms" as NSString).size(withAttributes: textAttrs).width

        let totalWidth = wideChartWidth + wideGap + ceil(refWidth)
        let image = NSImage(size: NSSize(width: totalWidth, height: wideChartHeight))
        image.lockFocus()
        defer { image.unlockFocus() }

        let chartImage = renderChartImage(width: wideChartWidth, height: wideChartHeight)
        chartImage.draw(in: NSRect(x: 0, y: 0, width: wideChartWidth, height: wideChartHeight))

        let textX = wideChartWidth + wideGap + ceil(refWidth) - ceil(textSize.width)
        let textY = (wideChartHeight - textSize.height) / 2
        (text as NSString).draw(
            at: NSPoint(x: textX, y: textY),
            withAttributes: textAttrs
        )

        return image
    }

    // MARK: - Compact layout (vertical: chart on top, text below)

    private func renderCompactLabel() -> NSImage {
        let text = latencyText
        let textAttrs = textAttributes(fontSize: compactFontSize)
        let textSize = (text as NSString).size(withAttributes: textAttrs)

        let totalWidth = max(compactChartWidth, ceil(textSize.width))
        let image = NSImage(size: NSSize(width: totalWidth, height: compactTotalHeight))
        image.lockFocus()
        defer { image.unlockFocus() }

        // Chart at the top
        let chartImage = renderChartImage(width: compactChartWidth, height: compactChartHeight)
        let chartX = (totalWidth - compactChartWidth) / 2
        let chartY = compactTotalHeight - compactChartHeight
        chartImage.draw(in: NSRect(x: chartX, y: chartY, width: compactChartWidth, height: compactChartHeight))

        // Text centered below chart
        let textX = (totalWidth - ceil(textSize.width)) / 2
        let textY: CGFloat = 0
        (text as NSString).draw(
            at: NSPoint(x: textX, y: textY),
            withAttributes: textAttrs
        )

        return image
    }

    // MARK: - Shared

    private func renderChartImage(width: CGFloat, height: CGFloat) -> NSImage {
        let content = chartContent
            .frame(width: width, height: height)
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
            return NSImage(size: NSSize(width: width, height: height))
        }
        return image
    }

    @ViewBuilder
    private var chartContent: some View {
        chartMode.chartView(probes: probes, now: now, historyMinutes: historyMinutes, colorScheme: colorScheme, latencyThreshold: latencyThreshold)
    }

    private var latencyText: String {
        if let ms = latencyMs {
            return String(format: "%.0fms", ms)
        }
        return "--ms"
    }

    private func textAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        // Use the menubar's appearance to pick text color — macOS updates
        // the SwiftUI colorScheme environment based on the wallpaper behind the menubar.
        let color: NSColor
        if latencyMs != nil {
            color = systemColorScheme == .dark ? .white : .black
        } else {
            color = systemColorScheme == .dark
                ? NSColor.white.withAlphaComponent(0.5)
                : NSColor.black.withAlphaComponent(0.5)
        }
        return [.font: font, .foregroundColor: color]
    }
}
