import SwiftUI

struct SparklineLabel: View {
    let dataPoints: [Double]
    let colorScheme: HeatmapColorScheme
    let latencyThreshold: Double
    var showBackground: Bool = false

    var body: some View {
        Canvas { context, size in
            let padding: CGFloat = 1

            // Background
            if showBackground {
                let bg = RoundedRectangle(cornerRadius: 3)
                    .path(in: CGRect(origin: .zero, size: size))
                context.fill(bg, with: .color(colorScheme.menuBarBackground))
            }

            guard !dataPoints.isEmpty else {
                // Flat baseline
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height - 1))
                line.addLine(to: CGPoint(x: size.width, y: size.height - 1))
                context.stroke(line, with: .color(.secondary), lineWidth: 1)
                return
            }

            // Stepped Y scale matching SparklineBar
            let maxVal = dataPoints.max() ?? 10
            let scaleSteps: [Double] = [10, 25, 50, 100, 200, 500, 1000]
            let yScale = scaleSteps.first { $0 >= maxVal } ?? maxVal

            let drawHeight = size.height - padding * 2
            let drawWidth = size.width - padding * 2

            // Build points (Y flipped: low latency at bottom, high at top)
            var points: [(x: CGFloat, y: CGFloat)] = []
            for i in 0..<dataPoints.count {
                let x = padding + CGFloat(i) / CGFloat(max(dataPoints.count - 1, 1)) * drawWidth
                let y = padding + (1 - CGFloat(dataPoints[i]) / CGFloat(yScale)) * drawHeight
                points.append((x: x, y: y))
            }

            // Map Y position back to latency for gradient coloring
            func latencyForY(_ y: CGFloat) -> Double {
                return (1 - Double((y - padding) / drawHeight)) * yScale
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

                    var sub = Path()
                    sub.move(to: CGPoint(x: x0, y: y0))
                    sub.addLine(to: CGPoint(x: x1, y: y1))

                    let midY = (y0 + y1) / 2
                    let color = colorScheme.color(for: latencyForY(midY), maxMs: latencyThreshold)
                    context.stroke(sub, with: .color(color), lineWidth: 1.5)
                }
            }
        }
        .frame(width: 32, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
