import SwiftUI
import AppKit

struct SparklineLabel: View {
    let dataPoints: [Double]
    let colorScheme: HeatmapColorScheme
    let latencyThreshold: Double
    var showBackground: Bool = true
    var latencyMs: Double?

    private let sparklineWidth: CGFloat = 32
    private let sparklineHeight: CGFloat = 24
    private let fontSize: CGFloat = 12
    private let gap: CGFloat = 2

    var body: some View {
        Image(nsImage: renderLabel())
    }

    private func renderLabel() -> NSImage {
        // Measure text
        let text = latencyText
        let textAttrs = textAttributes(for: latencyMs)
        let textSize = (text as NSString).size(withAttributes: textAttrs)

        let showSparkline = dataPoints.count >= 2
        let totalWidth: CGFloat
        if showSparkline {
            totalWidth = sparklineWidth + gap + ceil(textSize.width)
        } else {
            totalWidth = ceil(textSize.width)
        }

        let image = NSImage(size: NSSize(width: totalWidth, height: sparklineHeight))
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        if showSparkline {
            // Draw background behind sparkline only
            if showBackground {
                drawBackground(ctx, width: sparklineWidth, height: sparklineHeight)
            }

            // Draw sparkline
            drawSparkline(ctx, width: sparklineWidth, height: sparklineHeight)

            // Draw text to the right of sparkline
            let textY = (sparklineHeight - textSize.height) / 2
            (text as NSString).draw(
                at: NSPoint(x: sparklineWidth + gap, y: textY),
                withAttributes: textAttrs
            )
        } else {
            // No sparkline — just draw text centered vertically
            let textY = (sparklineHeight - textSize.height) / 2
            (text as NSString).draw(
                at: NSPoint(x: 0, y: textY),
                withAttributes: textAttrs
            )
        }

        image.unlockFocus()
        return image
    }

    private var latencyText: String {
        if let ms = latencyMs {
            return String(format: "%.0fms", ms)
        }
        return "--ms"
    }

    private func textAttributes(for ms: Double?) -> [NSAttributedString.Key: Any] {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        let color: NSColor = if ms != nil {
            .white
        } else {
            .secondaryLabelColor
        }
        return [
            .font: font,
            .foregroundColor: color
        ]
    }

    private func drawSparkline(_ ctx: CGContext, width: CGFloat, height: CGFloat) {
        guard !dataPoints.isEmpty else { return }

        let maxVal = dataPoints.max() ?? 10
        let scaleSteps: [Double] = [10, 25, 50, 100, 200, 500, 1000]
        let yScale = CGFloat(scaleSteps.first { $0 >= maxVal } ?? maxVal)
        let padding: CGFloat = 1
        let drawHeight = height - padding * 2
        let drawWidth = width - padding * 2

        var points: [(x: CGFloat, y: CGFloat)] = []
        for i in 0..<dataPoints.count {
            let x = padding + CGFloat(i) / CGFloat(max(dataPoints.count - 1, 1)) * drawWidth
            let y = padding + CGFloat(dataPoints[i]) / yScale * drawHeight
            points.append((x: x, y: y))
        }

        func latencyForY(_ y: CGFloat) -> Double {
            return Double((y - padding) / drawHeight * yScale)
        }

        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]

            let dx = curr.x - prev.x
            let dy = curr.y - prev.y
            let segmentLength = sqrt(dx * dx + dy * dy)
            let steps = max(Int(segmentLength / 1.5), 1)

            for s in 0..<steps {
                let t0 = CGFloat(s) / CGFloat(steps)
                let t1 = CGFloat(s + 1) / CGFloat(steps)
                let x0 = prev.x + dx * t0
                let y0 = prev.y + dy * t0
                let x1 = prev.x + dx * t1
                let y1 = prev.y + dy * t1

                let midY = (y0 + y1) / 2
                let color = colorScheme.nsColor(for: latencyForY(midY), maxMs: latencyThreshold)
                ctx.setStrokeColor(color.cgColor)
                ctx.setLineWidth(1.5)
                ctx.move(to: CGPoint(x: x0, y: y0))
                ctx.addLine(to: CGPoint(x: x1, y: y1))
                ctx.strokePath()
            }
        }
    }

    private func drawBackground(_ ctx: CGContext, width: CGFloat, height: CGFloat) {
        let rect = NSRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1)
        let bgPath = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)

        // Fill
        let bgColor = colorScheme.nsMenuBarBackground
        ctx.setFillColor(bgColor.cgColor)
        bgPath.fill()

        // 1px outline
        bgPath.lineWidth = 1
        NSColor.white.withAlphaComponent(0.25).setStroke()
        bgPath.stroke()
    }
}
