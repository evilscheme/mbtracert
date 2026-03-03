import SwiftUI

struct HeatmapBar: View {
    let probes: [ProbeResult]

    var body: some View {
        Canvas { context, size in
            guard !probes.isEmpty else { return }
            let cellWidth = size.width / CGFloat(probes.count)

            for (i, probe) in probes.enumerated() {
                let rect = CGRect(
                    x: CGFloat(i) * cellWidth,
                    y: 0,
                    width: cellWidth + 0.5,
                    height: size.height
                )
                let color = probe.isTimeout ? Color.black : colorForLatency(probe.latencyMs)
                context.fill(Path(rect), with: .color(color))
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
