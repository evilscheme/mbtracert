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
                guard visible.count >= 1 else { return }

                // Fixed Y scale matching the color scheme's 0-100ms range
                let yScale: Double = 100
                let padding: CGFloat = 1

                // Build points array
                var points: [(x: CGFloat, y: CGFloat, latencyMs: Double, isTimeout: Bool)] = []
                for probe in visible {
                    let age = now.timeIntervalSince(probe.timestamp)
                    let xFraction = 1.0 - age / totalSeconds
                    let x = padding + CGFloat(xFraction) * (size.width - padding * 2)

                    let y: CGFloat
                    if probe.isTimeout {
                        y = size.height - padding // position tracked but not drawn
                    } else {
                        y = padding + (1 - CGFloat(probe.latencyMs / yScale)) * (size.height - padding * 2)
                    }
                    points.append((x: x, y: y, latencyMs: probe.latencyMs, isTimeout: probe.isTimeout))
                }

                // Single non-timeout probe: render a small dot
                let nonTimeoutPoints = points.filter { !$0.isTimeout }
                if nonTimeoutPoints.count == 1, let pt = nonTimeoutPoints.first {
                    let dot = Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4))
                    context.fill(dot, with: .color(colorScheme.color(for: pt.latencyMs)))
                    return
                }

                // Map Y position back to latency for position-based coloring
                let drawHeight = size.height - padding * 2
                func latencyForY(_ y: CGFloat) -> Double {
                    return (1 - (y - padding) / drawHeight) * yScale
                }

                // Draw connected line segments, subdivided for gradient coloring
                for i in 1..<points.count {
                    let prev = points[i - 1]
                    let curr = points[i]

                    if prev.isTimeout || curr.isTimeout { continue }

                    // Subdivide segment so color follows Y position
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

                        var sub = Path()
                        sub.move(to: CGPoint(x: x0, y: y0))
                        sub.addLine(to: CGPoint(x: x1, y: y1))

                        let midY = (y0 + y1) / 2
                        let color = colorScheme.color(for: latencyForY(midY))
                        context.stroke(sub, with: .color(color), lineWidth: 1.5)
                    }
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
