import SwiftUI

struct TraceroutePanel: View {
    @ObservedObject var viewModel: TracerouteViewModel
    @Environment(\.openSettings) private var openSettings
    @AppStorage("showSparkline") private var showSparkline = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: viewModel.activeInterval)) { timeline in
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.targetHost)
                            .font(.headline)
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    Spacer()

                    if let lastHop = viewModel.destinationLatencyHop {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(String(format: "%.0fms", lastHop.lastLatencyMs))
                                .font(.system(.title3, design: .monospaced))
                                .foregroundStyle(.primary)
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(viewModel.colorScheme.color(for: lastHop.lastLatencyMs, maxMs: viewModel.latencyThreshold))
                                        .frame(height: 2)
                                        .offset(y: 1)
                                }
                            if lastHop.avgLatencyMs > 0 {
                                Text(String(format: "avg %.0fms", lastHop.avgLatencyMs))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                if viewModel.showBandwidth {
                    bandwidthSection(now: timeline.date)
                    Divider()
                }

                columnHeaders
                Divider()
                hopList(now: timeline.date)
                Divider()
                footer
            }
            .frame(width: 600)
        }
    }

    private func bandwidthSection(now: Date) -> some View {
        let sparkline = BandwidthSparklineView(
            samples: viewModel.bandwidthHistory,
            now: now,
            historyMinutes: viewModel.historyMinutes,
            colorScheme: viewModel.colorScheme
        )
        let scaleLabel = BandwidthSparklineView.formatScale(sparkline.yScale)

        return HStack(spacing: 6) {
            // Left label area — matches combined width of #/Host/Last/Avg/Loss columns
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.currentInterface.isEmpty ? "—" : viewModel.currentInterface)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)

                if let sample = viewModel.lastBandwidthSample {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                            .font(.caption2)
                            .foregroundStyle(viewModel.colorScheme.uploadColor)
                        Text(sample.uploadFormatted)
                            .font(.system(.caption, design: .monospaced))
                    }
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                            .font(.caption2)
                            .foregroundStyle(viewModel.colorScheme.downloadColor)
                        Text(sample.downloadFormatted)
                            .font(.system(.caption, design: .monospaced))
                    }
                } else {
                    Text("Measuring…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // 5 columns (20+130+38+38+28) + 4 inter-column gaps (4×6) = 278
            .frame(width: 278, alignment: .leading)
            .overlay(alignment: .trailing) {
                Text(scaleLabel)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.6))
            }

            // Chart with tooltip
            InteractiveChart(
                chart: sparkline,
                tooltipBuilder: { fraction in
                    bandwidthTooltip(fraction: fraction, now: now)
                },
                colorScheme: viewModel.colorScheme,
                latencyThreshold: viewModel.latencyThreshold
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .help("Total bandwidth on \(viewModel.currentInterface.isEmpty ? "active interface" : viewModel.currentInterface). Includes all applications using this interface.")
    }

    private func bandwidthTooltip(fraction: CGFloat, now: Date) -> ChartTooltip.Content? {
        let totalSeconds = viewModel.historyMinutes * 60
        let windowStart = now.addingTimeInterval(-totalSeconds)
        let visible = viewModel.bandwidthHistory.filter { $0.timestamp >= windowStart }
        guard !visible.isEmpty else { return nil }

        let targetTime = windowStart.addingTimeInterval(Double(fraction) * totalSeconds)

        // Find the sample whose rendered bar contains the cursor.
        // Each bar spans from sample[i].timestamp to sample[i+1].timestamp.
        var hitIndex: Int? = nil
        for (i, sample) in visible.enumerated() {
            if sample.timestamp <= targetTime {
                hitIndex = i
            } else {
                break
            }
        }

        guard let idx = hitIndex else { return nil }
        let best = visible[idx]

        return .bandwidth(BandwidthTooltipData(
            timestamp: best.timestamp,
            interfaceName: best.interfaceName,
            downloadBytesPerSec: best.downloadBytesPerSec,
            uploadBytesPerSec: best.uploadBytesPerSec
        ))
    }

    private var columnHeaders: some View {
        HStack(spacing: 6) {
            Text("#")
                .frame(width: 20, alignment: .trailing)
            Text("Host")
                .frame(width: 130, alignment: .leading)
            Text("Last")
                .frame(width: 38, alignment: .trailing)
            Text("Avg")
                .frame(width: 38, alignment: .trailing)
            Text("Loss")
                .frame(width: 28, alignment: .trailing)
            Text("History")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func hopList(now: Date) -> some View {
        if viewModel.visibleHops.isEmpty && !viewModel.isProbing {
            Text("Waiting for first probe...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.visibleHops) { hop in
                        HopRowView(hop: hop, now: now, historyMinutes: viewModel.historyMinutes, activeInterval: viewModel.activeInterval, colorScheme: viewModel.colorScheme, latencyThreshold: viewModel.latencyThreshold, showSparkline: showSparkline)
                    }
                }
            }
            .frame(maxHeight: 600)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Button(action: {
                NSApp.activate()
                openSettings()
            }) {
                Image(systemName: "gearshape")
            }
            .preferringGlassStyle()
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings")

            Spacer()

            Button(action: {
                viewModel.clearHistory()
            }) {
                Image(systemName: "trash")
            }
            .preferringGlassStyle()
            .help("Reset historical data")

            Spacer()

            Button(action: {
                showSparkline.toggle()
            }) {
                Image(systemName: showSparkline ? "chart.line.uptrend.xyaxis" : "chart.bar.fill")
            }
            .preferringGlassStyle()
            .help(showSparkline ? "Switch to heatmap" : "Switch to sparkline")

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .preferringGlassStyle()
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private extension View {
    @ViewBuilder
    func preferringGlassStyle() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.borderless)
        }
        #else
        self.buttonStyle(.borderless)
        #endif
    }
}
