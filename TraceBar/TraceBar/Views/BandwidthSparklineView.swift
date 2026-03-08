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

            let midY = size.height / 2

            // Shared Y scale for both directions (symmetric)
            let maxValue = max(
                visible.map(\.downloadBytesPerSec).max() ?? 0,
                visible.map(\.uploadBytesPerSec).max() ?? 0,
                1
            )
            let yScale = steppedScale(for: maxValue)
            let halfHeight = midY

            // Dashed center baseline
            let dashLength: CGFloat = 3
            let gapLength: CGFloat = 3
            var dashX: CGFloat = 0
            while dashX < size.width {
                let segEnd = min(dashX + dashLength, size.width)
                var dash = Path()
                dash.move(to: CGPoint(x: dashX, y: midY))
                dash.addLine(to: CGPoint(x: segEnd, y: midY))
                context.stroke(dash, with: .color(.primary.opacity(0.15)), lineWidth: 0.5)
                dashX = segEnd + gapLength
            }

            // Time-based X position (matching SparklineBar / HeatmapBar exactly)
            func xFor(_ timestamp: Date) -> CGFloat {
                let age = now.timeIntervalSince(timestamp)
                let fraction = 1.0 - age / totalSeconds
                return CGFloat(fraction) * size.width
            }

            // Draw bars with time-proportional widths (like HeatmapBar)
            for (i, sample) in visible.enumerated() {
                let x = xFor(sample.timestamp)

                let nextX: CGFloat
                if i + 1 < visible.count {
                    nextX = xFor(visible[i + 1].timestamp)
                } else {
                    nextX = size.width
                }

                let barWidth = nextX - x
                guard barWidth > 0 else { continue }

                // Download: extends upward from midY
                if sample.downloadBytesPerSec > 0 {
                    let h = CGFloat(sample.downloadBytesPerSec / yScale) * halfHeight
                    let rect = CGRect(x: x, y: midY - h, width: barWidth + 0.5, height: h)
                    context.fill(Path(rect), with: .color(colorScheme.downloadColor))
                }

                // Upload: extends downward from midY
                if sample.uploadBytesPerSec > 0 {
                    let h = CGFloat(sample.uploadBytesPerSec / yScale) * halfHeight
                    let rect = CGRect(x: x, y: midY, width: barWidth + 0.5, height: h)
                    context.fill(Path(rect), with: .color(colorScheme.uploadColor))
                }
            }
        }
        .frame(height: 44)
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
