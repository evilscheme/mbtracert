import SwiftUI

struct HopRowView: View {
    let hop: HopData
    let now: Date
    let historyMinutes: Double
    let colorScheme: ColorTheme
    let latencyThreshold: Double
    let chartMode: ChartMode

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

            InteractiveChart(
                chart: hopChart,
                tooltipBuilder: { fraction in
                    probeTooltip(fraction: fraction, probes: hop.probes.elements, now: now, historyMinutes: historyMinutes)
                },
                colorScheme: colorScheme,
                latencyThreshold: latencyThreshold
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var hopChart: some View {
        chartMode.chartView(probes: hop.probes.elements, now: now, historyMinutes: historyMinutes, colorScheme: colorScheme, latencyThreshold: latencyThreshold)
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
    }

    private func probeTooltip(fraction: CGFloat, probes: [ProbeResult], now: Date, historyMinutes: Double) -> ChartTooltip.Content? {
        let totalSeconds = historyMinutes * 60
        let windowStart = now.addingTimeInterval(-totalSeconds)
        let visible = probes.filter { $0.timestamp >= windowStart }
        guard !visible.isEmpty else { return nil }

        // Convert fraction to the target timestamp the cursor represents
        let targetTime = windowStart.addingTimeInterval(Double(fraction) * totalSeconds)

        // Find the probe whose rendered region contains the cursor.
        // Each bar/segment spans from probe[i].timestamp to probe[i+1].timestamp
        // (last probe extends to `now`). This matches the chart rendering logic.
        var hitIndex: Int? = nil
        for (i, probe) in visible.enumerated() {
            if probe.timestamp <= targetTime {
                hitIndex = i
            } else {
                break
            }
        }

        // Cursor is before the first data point — no bar rendered here
        guard let idx = hitIndex else { return nil }
        let best = visible[idx]

        return .probe(ProbeTooltipData(
            timestamp: best.timestamp,
            address: best.address,
            hostname: best.hostname,
            latencyMs: best.latencyMs,
            isTimeout: best.isTimeout
        ))
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
