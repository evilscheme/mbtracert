import SwiftUI

struct HeatmapBar: View {
    let probes: [ProbeResult]
    let historyMinutes: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Canvas { context, size in
                let now = timeline.date
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
                    let color = probe.isTimeout ? Color.black : colorForLatency(probe.latencyMs)
                    context.fill(Path(rect), with: .color(color))
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

    private func colorForLatency(_ ms: Double) -> Color {
        let normalized = min(ms / 100.0, 1.0)
        if normalized < 0.5 {
            return Color(red: normalized * 2, green: 1.0, blue: 0)
        } else {
            return Color(red: 1.0, green: 1.0 - (normalized - 0.5) * 2, blue: 0)
        }
    }
}
