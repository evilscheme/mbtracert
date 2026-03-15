import SwiftUI

struct HeatmapChart: LatencyChart {
    let probes: [ProbeResult]
    let now: Date
    let historyMinutes: Double
    let colorScheme: ColorTheme
    let latencyThreshold: Double

    var body: some View {
        Canvas { context, size in
            let visible = visibleProbes
            guard !visible.isEmpty else { return }

            for (i, probe) in visible.enumerated() {
                let x = xPosition(for: probe.timestamp, in: size.width)
                let cellWidth = nextX(after: i, in: visible, width: size.width) - x
                guard cellWidth > 0 else { continue }

                let rect = CGRect(x: x, y: 0, width: cellWidth + 0.5, height: size.height)
                let color = probe.isTimeout ? colorScheme.timeoutColor : colorScheme.color(for: probe.latencyMs, maxMs: latencyThreshold)
                context.fill(Path(rect), with: .color(color))
            }
        }
    }
}
