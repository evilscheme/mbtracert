import SwiftUI

struct SparklineBar: View {
    let probes: [ProbeResult]
    let historyMinutes: Double
    let activeInterval: Double
    let colorScheme: HeatmapColorScheme
    let latencyThreshold: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: activeInterval)) { timeline in
            Canvas { context, size in
                let now = timeline.date
                let totalSeconds = historyMinutes * 60
                let windowStart = now.addingTimeInterval(-totalSeconds)

                let visible = probes.filter { $0.timestamp >= windowStart }
                guard visible.count >= 2 else { return }

                // Auto-scale Y axis: minimum range of 10ms
                let maxLatency = visible.filter { !$0.isTimeout }.map(\.latencyMs).max() ?? 10
                let yScale = max(maxLatency, 10)
                let padding: CGFloat = 1

                // Build points array
                var points: [(x: CGFloat, y: CGFloat, latencyMs: Double, isTimeout: Bool)] = []
                for probe in visible {
                    let age = now.timeIntervalSince(probe.timestamp)
                    let xFraction = 1.0 - age / totalSeconds
                    let x = padding + CGFloat(xFraction) * (size.width - padding * 2)

                    let y: CGFloat
                    if probe.isTimeout {
                        y = size.height - padding // bottom edge for timeouts
                    } else {
                        y = padding + (1 - CGFloat(probe.latencyMs / yScale)) * (size.height - padding * 2)
                    }
                    points.append((x: x, y: y, latencyMs: probe.latencyMs, isTimeout: probe.isTimeout))
                }

                // Draw connected line segments, each colored by latency
                for i in 1..<points.count {
                    let prev = points[i - 1]
                    let curr = points[i]

                    var segment = Path()
                    segment.move(to: CGPoint(x: prev.x, y: prev.y))
                    segment.addLine(to: CGPoint(x: curr.x, y: curr.y))

                    let color: Color
                    if curr.isTimeout {
                        color = colorScheme.timeoutColor
                    } else {
                        color = colorScheme.color(for: curr.latencyMs)
                    }

                    context.stroke(segment, with: .color(color), lineWidth: 1.5)
                }
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}
