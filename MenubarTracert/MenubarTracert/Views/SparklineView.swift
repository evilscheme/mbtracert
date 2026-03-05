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
                ctx.move(to: CGPoint(x: 0, y: height / 2))
                ctx.addLine(to: CGPoint(x: width, y: height / 2))
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

        let maxVal = max(dataPoints.max() ?? 1, 10)
        let padding: CGFloat = 1

        for i in 0..<dataPoints.count {
            let x = padding + CGFloat(i) / CGFloat(max(dataPoints.count - 1, 1)) * (width - padding * 2)
            let y = padding + (1 - CGFloat(dataPoints[i]) / CGFloat(maxVal)) * (height - padding * 2)

            let color = colorScheme.nsColor(for: dataPoints[i], maxMs: latencyThreshold)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(1.5)

            if i == 0 {
                ctx.move(to: CGPoint(x: x, y: y))
            } else {
                ctx.addLine(to: CGPoint(x: x, y: y))
                ctx.strokePath()
                ctx.move(to: CGPoint(x: x, y: y))
            }
        }

        image.unlockFocus()
        return image
    }

}
