import SwiftUI

struct BandwidthSparklineView: View {
    let downloadHistory: [Double]  // bytes/sec values
    let uploadHistory: [Double]
    let colorScheme: HeatmapColorScheme

    var body: some View {
        Canvas { context, size in
            guard !downloadHistory.isEmpty || !uploadHistory.isEmpty else { return }

            let padding: CGFloat = 1
            let drawWidth = size.width - padding * 2
            let drawHeight = size.height - padding * 2

            // Auto-scale Y axis to the max value across both series
            let maxValue = max(downloadHistory.max() ?? 0, uploadHistory.max() ?? 0, 1)
            let yScale = steppedScale(for: maxValue)
            guard yScale > 0 else { return }

            // Draw download area (behind)
            drawArea(
                context: &context,
                values: downloadHistory,
                color: colorScheme.downloadColor.opacity(0.5),
                strokeColor: colorScheme.downloadColor,
                yScale: yScale, padding: padding,
                drawWidth: drawWidth, drawHeight: drawHeight
            )

            // Draw upload area (in front)
            drawArea(
                context: &context,
                values: uploadHistory,
                color: colorScheme.uploadColor.opacity(0.5),
                strokeColor: colorScheme.uploadColor,
                yScale: yScale, padding: padding,
                drawWidth: drawWidth, drawHeight: drawHeight
            )
        }
        .frame(height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func drawArea(
        context: inout GraphicsContext,
        values: [Double], color: Color, strokeColor: Color,
        yScale: Double, padding: CGFloat,
        drawWidth: CGFloat, drawHeight: CGFloat
    ) {
        guard values.count >= 2 else {
            // Single point: draw a dot
            if let v = values.first, v > 0 {
                let x = padding + drawWidth
                let y = padding + (1 - CGFloat(v / yScale)) * drawHeight
                let dot = Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
                context.fill(dot, with: .color(strokeColor))
            }
            return
        }

        let baseline = padding + drawHeight
        var areaPath = Path()
        var linePath = Path()

        for (i, value) in values.enumerated() {
            let x = padding + CGFloat(i) / CGFloat(values.count - 1) * drawWidth
            let y = padding + (1 - CGFloat(value / yScale)) * drawHeight

            if i == 0 {
                areaPath.move(to: CGPoint(x: x, y: baseline))
                areaPath.addLine(to: CGPoint(x: x, y: y))
                linePath.move(to: CGPoint(x: x, y: y))
            } else {
                areaPath.addLine(to: CGPoint(x: x, y: y))
                linePath.addLine(to: CGPoint(x: x, y: y))
            }
        }

        // Close area path back to baseline
        let lastX = padding + drawWidth
        areaPath.addLine(to: CGPoint(x: lastX, y: baseline))
        areaPath.closeSubpath()

        context.fill(areaPath, with: .color(color))
        context.stroke(linePath, with: .color(strokeColor), lineWidth: 1)
    }

    /// Stepped Y-axis thresholds to avoid constant rescaling.
    private func steppedScale(for maxValue: Double) -> Double {
        let steps: [Double] = [
            1_024,            // 1 KB/s
            10_240,           // 10 KB/s
            102_400,          // 100 KB/s
            1_048_576,        // 1 MB/s
            10_485_760,       // 10 MB/s
            104_857_600,      // 100 MB/s
            1_073_741_824     // 1 GB/s
        ]
        return steps.first { $0 >= maxValue } ?? maxValue
    }
}
