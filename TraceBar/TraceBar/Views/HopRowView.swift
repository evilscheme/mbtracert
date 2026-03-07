import SwiftUI

struct HopRowView: View {
    let hop: HopData
    let now: Date
    let historyMinutes: Double
    let activeInterval: Double
    let colorScheme: HeatmapColorScheme
    let latencyThreshold: Double
    let showSparkline: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("\(hop.hop)")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 20, alignment: .trailing)
                .foregroundStyle(.secondary)

            Text(hop.hostname ?? hop.address)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(hop.address)

            colorUnderlinedText(
                hop.lastLatencyMs > 0 ? String(format: "%.0fms", hop.lastLatencyMs) : "---",
                color: hop.lastLatencyMs > 0 ? colorScheme.color(for: hop.lastLatencyMs, maxMs: latencyThreshold) : nil,
                width: 38
            )

            colorUnderlinedText(
                hop.avgLatencyMs > 0 ? String(format: "%.0fms", hop.avgLatencyMs) : "---",
                color: hop.avgLatencyMs > 0 ? colorScheme.color(for: hop.avgLatencyMs, maxMs: latencyThreshold) : nil,
                width: 38
            )

            colorUnderlinedText(
                String(format: "%.0f%%", hop.lossPercent),
                color: hop.lossPercent > 0 ? colorScheme.color(for: 50 + hop.lossPercent * 0.5) : nil,
                width: 28
            )

            if showSparkline {
                SparklineBar(probes: hop.probes.elements, now: now, historyMinutes: historyMinutes, colorScheme: colorScheme, latencyThreshold: latencyThreshold)
                    .frame(maxWidth: .infinity)
            } else {
                HeatmapBar(probes: hop.probes.elements, now: now, historyMinutes: historyMinutes, colorScheme: colorScheme, latencyThreshold: latencyThreshold)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func colorUnderlinedText(_ text: String, color: Color?, width: CGFloat) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .trailing)
            .overlay(alignment: .bottom) {
                if let color {
                    Rectangle()
                        .fill(color)
                        .frame(height: 2)
                        .padding(.horizontal, -3)
                        .offset(y: 1)
                }
            }
    }
}
