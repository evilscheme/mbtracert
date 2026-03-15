import SwiftUI

struct VerticalBarsChart: LatencyChart {
    let probes: [ProbeResult]
    let now: Date
    let historyMinutes: Double
    let colorScheme: ColorTheme
    let latencyThreshold: Double

    var body: some View {
        Canvas { context, size in
            let visible = visibleProbes
            guard !visible.isEmpty else { return }

            let yScale = latencyYScale(for: visible)
            let lossColor = colorScheme.color(for: latencyThreshold, maxMs: latencyThreshold)

            for (i, probe) in visible.enumerated() {
                let x = xPosition(for: probe.timestamp, in: size.width)
                let barWidth = nextX(after: i, in: visible, width: size.width) - x
                guard barWidth > 0 else { continue }

                if probe.isTimeout {
                    let centerX = x + barWidth / 2
                    let dot = Path(ellipseIn: CGRect(x: centerX - 1, y: 0, width: 2, height: 2))
                    context.fill(dot, with: .color(lossColor))
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
