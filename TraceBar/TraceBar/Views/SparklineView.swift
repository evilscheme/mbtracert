import SwiftUI
import AppKit

struct SparklineLabel: View {
    let dataPoints: [Double]
    let colorScheme: HeatmapColorScheme
    let latencyThreshold: Double

    var body: some View {
        Image(nsImage: renderSparkline())
    }

    private func renderSparkline() -> NSImage {
        let width: CGFloat = 32
        let height: CGFloat = 18
        let image = NSImage(size: NSSize(width: width, height: height))

        guard !dataPoints.isEmpty else {
            image.lockFocus()
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.setStrokeColor(NSColor.secondaryLabelColor.cgColor)
                ctx.setLineWidth(1)
                ctx.move(to: CGPoint(x: 0, y: 1))
                ctx.addLine(to: CGPoint(x: width, y: 1))
                ctx.strokePath()
            }
            image.unlockFocus()
            return image
        }

        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        // Stepped Y scale matching SparklineBar
        let maxVal = dataPoints.max() ?? 10
        let scaleSteps: [Double] = [10, 25, 50, 100, 200, 500, 1000]
        let yScale = CGFloat(scaleSteps.first { $0 >= maxVal } ?? maxVal)
        let padding: CGFloat = 1
        let drawHeight = height - padding * 2
        let drawWidth = width - padding * 2

        // Build points
        var points: [(x: CGFloat, y: CGFloat)] = []
        for i in 0..<dataPoints.count {
            let x = padding + CGFloat(i) / CGFloat(max(dataPoints.count - 1, 1)) * drawWidth
            let y = padding + CGFloat(dataPoints[i]) / yScale * drawHeight
            points.append((x: x, y: y))
        }

        // Map Y position back to latency for gradient coloring
        func latencyForY(_ y: CGFloat) -> Double {
            return Double((y - padding) / drawHeight * yScale)
        }

        // Draw subdivided segments with Y-position-based gradient coloring
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

        image.unlockFocus()
        return image
    }

}
