import SwiftUI

struct VerticalBarsBar: View {
    let probes: [ProbeResult]
    let now: Date
    let historyMinutes: Double
    let colorScheme: HeatmapColorScheme
    let latencyThreshold: Double

    var body: some View {
        Canvas { context, size in
            let totalSeconds = historyMinutes * 60
            let windowStart = now.addingTimeInterval(-totalSeconds)

            let visible = probes.filter { $0.timestamp >= windowStart }
            guard !visible.isEmpty else { return }

            // Y scale from non-timeout latencies
            let maxLatency = visible.filter { !$0.isTimeout }.map(\.latencyMs).max() ?? 10
            let steps: [Double] = [50, 100, 200, 500, 1000]
            let yScale = steps.first { $0 >= maxLatency } ?? maxLatency

            let lossColor = colorScheme.color(for: latencyThreshold, maxMs: latencyThreshold)

            for (i, probe) in visible.enumerated() {
                let age = now.timeIntervalSince(probe.timestamp)
                let leftFraction = 1.0 - age / totalSeconds
                let x = CGFloat(leftFraction) * size.width

                // Bar extends from this probe's timestamp to the next probe's timestamp (or now)
                let nextX: CGFloat
                if i + 1 < visible.count {
                    let nextAge = now.timeIntervalSince(visible[i + 1].timestamp)
                    nextX = CGFloat(1.0 - nextAge / totalSeconds) * size.width
                } else {
                    nextX = size.width
                }

                let barWidth = nextX - x
                guard barWidth > 0 else { continue }

                if probe.isTimeout {
                    // Dashed vertical bar for packet loss
                    let centerX = x + barWidth / 2
                    var dash = Path()
                    dash.move(to: CGPoint(x: centerX, y: 0))
                    dash.addLine(to: CGPoint(x: centerX, y: size.height))
                    context.stroke(
                        dash,
                        with: .color(lossColor),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                    )
                    continue
                }

                let barHeight = CGFloat(probe.latencyMs / yScale) * size.height
                let barY = size.height - barHeight
                let rect = CGRect(x: x, y: barY, width: barWidth + 0.5, height: barHeight)

                let probeColor = colorScheme.color(for: probe.latencyMs, maxMs: latencyThreshold)
                context.fill(Path(rect), with: .color(probeColor))
            }
        }
    }
}
