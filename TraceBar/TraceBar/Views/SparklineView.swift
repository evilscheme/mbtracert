import SwiftUI
import AppKit

struct SparklineLabel: View {
    let probes: [ProbeResult]
    let now: Date
    let historyMinutes: Double
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
        // Measure text — use fixed-width reference to prevent layout jumps
        let text = latencyText
        let textAttrs = textAttributes(for: latencyMs)
        let textSize = (text as NSString).size(withAttributes: textAttrs)
        let refWidth = ("000ms" as NSString).size(withAttributes: textAttrs).width

        let totalWidth = sparklineWidth + gap + ceil(refWidth)

        let image = NSImage(size: NSSize(width: totalWidth, height: sparklineHeight))
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        // Always draw background behind sparkline area
        if showBackground {
            drawBackground(ctx, width: sparklineWidth, height: sparklineHeight)
        }

        // Draw sparkline when we have data
        drawSparkline(ctx, width: sparklineWidth, height: sparklineHeight)

        // Draw text right-aligned within the fixed-width area
        let textX = sparklineWidth + gap + ceil(refWidth) - ceil(textSize.width)
        let textY = (sparklineHeight - textSize.height) / 2
        (text as NSString).draw(
            at: NSPoint(x: textX, y: textY),
            withAttributes: textAttrs
        )

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
        let totalSeconds = historyMinutes * 60

        let padding: CGFloat = 1
        let drawWidth = width - padding * 2
        let drawHeight = height - padding * 2
        let pixelCount = Int(drawWidth)
        guard pixelCount > 0 else { return }

        // Quantize window edge to bucket-width intervals so buckets don't
        // shift on every render — only scroll by 1px per bucket period.
        let bucketDuration = totalSeconds / Double(pixelCount)
        let quantizedNow = Date(timeIntervalSinceReferenceDate:
            (now.timeIntervalSinceReferenceDate / bucketDuration).rounded(.down) * bucketDuration)
        let windowStart = quantizedNow.addingTimeInterval(-totalSeconds)

        let visible = probes.filter { $0.timestamp >= windowStart }
        guard !visible.isEmpty else { return }

        // Bucket probes into pixel-width time slots
        struct Bucket {
            var maxLatency: Double = 0
            var hasData: Bool = false
            var hasTimeout: Bool = false
        }
        var buckets = [Bucket](repeating: Bucket(), count: pixelCount)

        for probe in visible {
            let age = quantizedNow.timeIntervalSince(probe.timestamp)
            let xFraction = 1.0 - age / totalSeconds
            let bucketIndex = min(Int(xFraction * Double(pixelCount)), pixelCount - 1)
            guard bucketIndex >= 0 else { continue }

            if probe.isTimeout {
                buckets[bucketIndex].hasTimeout = true
            } else {
                buckets[bucketIndex].hasData = true
                buckets[bucketIndex].maxLatency = max(buckets[bucketIndex].maxLatency, probe.latencyMs)
            }
        }

        // Y scale from bucketed max latencies
        let maxVal = buckets.filter(\.hasData).map(\.maxLatency).max() ?? 10
        let scaleSteps: [Double] = [50, 100, 200, 500, 1000]
        let yScale = CGFloat(scaleSteps.first { $0 >= maxVal } ?? maxVal)

        // Build plottable points from buckets with data
        var points: [(x: CGFloat, y: CGFloat)] = []
        for i in 0..<pixelCount {
            guard buckets[i].hasData else { continue }
            let x = padding + CGFloat(i) + 0.5
            let y = padding + CGFloat(buckets[i].maxLatency) / yScale * drawHeight
            points.append((x: x, y: y))
        }

        // Draw loss markers first (behind line)
        let lossColor = colorScheme.nsColor(for: latencyThreshold, maxMs: latencyThreshold)
        ctx.setStrokeColor(lossColor.cgColor)
        ctx.setLineWidth(1.5)
        for i in 0..<pixelCount {
            guard buckets[i].hasTimeout else { continue }
            let x = padding + CGFloat(i) + 0.5
            ctx.move(to: CGPoint(x: x, y: padding))
            ctx.addLine(to: CGPoint(x: x, y: padding + 4))
            ctx.strokePath()
        }

        // Single point: draw a dot
        if points.count == 1 {
            let pt = points[0]
            let dotColor = colorScheme.nsColor(for: Double((pt.y - padding) / drawHeight * yScale), maxMs: latencyThreshold)
            ctx.setFillColor(dotColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: pt.x - 1.5, y: pt.y - 1.5, width: 3, height: 3))
            return
        }

        guard points.count >= 2 else { return }

        func latencyForY(_ y: CGFloat) -> Double {
            return Double((y - padding) / drawHeight * yScale)
        }

        // Draw gradient line segments
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
