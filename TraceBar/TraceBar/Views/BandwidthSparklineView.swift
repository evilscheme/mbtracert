import SwiftUI

struct BandwidthSparklineView: View {
    let samples: [BandwidthSample]
    let now: Date
    let historyMinutes: Double
    let colorScheme: HeatmapColorScheme

    var body: some View {
        Canvas { context, size in
            let totalSeconds = historyMinutes * 60
            let windowStart = now.addingTimeInterval(-totalSeconds)

            let visible = samples.filter { $0.timestamp >= windowStart }
            guard !visible.isEmpty else { return }

            let padding: CGFloat = 1
            let drawWidth = size.width - padding * 2
            let midY = size.height / 2

            // Shared Y scale for both directions (symmetric)
            let maxValue = max(
                visible.map(\.downloadBytesPerSec).max() ?? 0,
                visible.map(\.uploadBytesPerSec).max() ?? 0,
                1
            )
            let yScale = steppedScale(for: maxValue)
            let halfHeight = midY - padding

            // Dashed center baseline
            let dashLength: CGFloat = 3
            let gapLength: CGFloat = 3
            var dashX = padding
            while dashX < padding + drawWidth {
                let segEnd = min(dashX + dashLength, padding + drawWidth)
                var dash = Path()
                dash.move(to: CGPoint(x: dashX, y: midY))
                dash.addLine(to: CGPoint(x: segEnd, y: midY))
                context.stroke(dash, with: .color(.primary.opacity(0.15)), lineWidth: 0.5)
                dashX = segEnd + gapLength
            }

            // Build time-based X positions (matching SparklineBar exactly)
            func xFor(_ timestamp: Date) -> CGFloat {
                let age = now.timeIntervalSince(timestamp)
                let fraction = 1.0 - age / totalSeconds
                return padding + CGFloat(fraction) * drawWidth
            }

            // Draw download (above center) and upload (below center) as filled bars
            for sample in visible {
                let x = xFor(sample.timestamp)

                // Download: extends upward from midY
                if sample.downloadBytesPerSec > 0 {
                    let h = CGFloat(sample.downloadBytesPerSec / yScale) * halfHeight
                    let rect = CGRect(x: x - 0.75, y: midY - h, width: 1.5, height: h)
                    context.fill(Path(rect), with: .color(colorScheme.downloadColor))
                }

                // Upload: extends downward from midY
                if sample.uploadBytesPerSec > 0 {
                    let h = CGFloat(sample.uploadBytesPerSec / yScale) * halfHeight
                    let rect = CGRect(x: x - 0.75, y: midY, width: 1.5, height: h)
                    context.fill(Path(rect), with: .color(colorScheme.uploadColor))
                }
            }
        }
        .frame(height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func steppedScale(for maxValue: Double) -> Double {
        let steps: [Double] = [
            1_024, 10_240, 102_400,
            1_048_576, 10_485_760, 104_857_600,
            1_073_741_824
        ]
        return steps.first { $0 >= maxValue } ?? maxValue
    }
}
