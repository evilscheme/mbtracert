import SwiftUI

struct HopRowView: View {
    let hop: HopData
    let historyMinutes: Double
    let activeInterval: Double
    let colorScheme: HeatmapColorScheme

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

            Text(hop.lastLatencyMs > 0 ? String(format: "%.0fms", hop.lastLatencyMs) : "---")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(hop.lastLatencyMs > 0 ? colorScheme.color(for: hop.lastLatencyMs) : .secondary)
                .frame(width: 38, alignment: .trailing)

            Text(hop.avgLatencyMs > 0 ? String(format: "%.0fms", hop.avgLatencyMs) : "---")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(hop.avgLatencyMs > 0 ? colorScheme.color(for: hop.avgLatencyMs) : .secondary)
                .frame(width: 38, alignment: .trailing)

            Text(String(format: "%.0f%%", hop.lossPercent))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(hop.lossPercent > 0 ? colorScheme.color(for: 50 + hop.lossPercent * 0.5) : .secondary)
                .frame(width: 28, alignment: .trailing)

            HeatmapBar(probes: hop.probes.elements, historyMinutes: historyMinutes, activeInterval: activeInterval, colorScheme: colorScheme)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
    }
}
