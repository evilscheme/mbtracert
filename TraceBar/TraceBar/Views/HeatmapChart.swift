import SwiftUI

struct HeatmapChart: View {
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

            for (i, probe) in visible.enumerated() {
                let age = now.timeIntervalSince(probe.timestamp)
                let leftFraction = 1.0 - age / totalSeconds
                let x = CGFloat(leftFraction) * size.width

                let nextX: CGFloat
                if i + 1 < visible.count {
                    let nextAge = now.timeIntervalSince(visible[i + 1].timestamp)
                    nextX = CGFloat(1.0 - nextAge / totalSeconds) * size.width
                } else {
                    nextX = size.width
                }

                let cellWidth = nextX - x
                guard cellWidth > 0 else { continue }

                let rect = CGRect(x: x, y: 0, width: cellWidth + 0.5, height: size.height)
                let color = probe.isTimeout ? colorScheme.timeoutColor : colorScheme.color(for: probe.latencyMs, maxMs: latencyThreshold)
                context.fill(Path(rect), with: .color(color))
            }
        }
    }
}
