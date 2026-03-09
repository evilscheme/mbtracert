import SwiftUI

// MARK: - Tooltip data types

/// Data to display in a chart tooltip for traceroute probes.
struct ProbeTooltipData {
    let timestamp: Date
    let address: String
    let hostname: String?
    let latencyMs: Double
    let isTimeout: Bool
}

/// Data to display in a chart tooltip for bandwidth samples.
struct BandwidthTooltipData {
    let timestamp: Date
    let interfaceName: String
    let downloadBytesPerSec: Double
    let uploadBytesPerSec: Double
}

// MARK: - Tooltip view

/// A visually polished floating tooltip for chart hover.
struct ChartTooltip: View {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss a"
        return f
    }()

    enum Content {
        case probe(ProbeTooltipData)
        case bandwidth(BandwidthTooltipData)
    }

    let content: Content
    let colorScheme: HeatmapColorScheme
    let latencyThreshold: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch content {
            case .probe(let data):
                probeContent(data)
            case .bandwidth(let data):
                bandwidthContent(data)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func probeContent(_ data: ProbeTooltipData) -> some View {
        Text(Self.timeFormatter.string(from: data.timestamp))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)

        HStack(spacing: 5) {
            if data.isTimeout {
                Text("timeout")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                let label = data.hostname ?? data.address
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("–")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(String(format: "%.1fms", data.latencyMs))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(colorScheme.color(for: data.latencyMs, maxMs: latencyThreshold))
            }
        }
    }

    @ViewBuilder
    private func bandwidthContent(_ data: BandwidthTooltipData) -> some View {
        Text(Self.timeFormatter.string(from: data.timestamp))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)

        HStack(spacing: 4) {
            Image(systemName: "arrow.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(colorScheme.downloadColor)
            Text(BandwidthSample.format(data.downloadBytesPerSec))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }

        HStack(spacing: 4) {
            Image(systemName: "arrow.up")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(colorScheme.uploadColor)
            Text(BandwidthSample.format(data.uploadBytesPerSec))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }

        Text(data.interfaceName)
            .font(.system(size: 9, weight: .regular, design: .monospaced))
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Mouse-tracking overlay

/// Wraps a chart view and provides continuous mouse-position tracking via NSTrackingArea.
/// The `onPositionChange` closure fires with the local X position (nil when mouse exits).
struct ChartMouseTracker: NSViewRepresentable {
    let onPositionChange: (CGFloat?) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onPositionChange = onPositionChange
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onPositionChange = onPositionChange
    }

    final class TrackingView: NSView {
        var onPositionChange: ((CGFloat?) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingArea {
                removeTrackingArea(existing)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseMoved(with event: NSEvent) {
            let local = convert(event.locationInWindow, from: nil)
            if bounds.contains(local) {
                onPositionChange?(local.x)
            } else {
                onPositionChange?(nil)
            }
        }

        override func mouseExited(with event: NSEvent) {
            onPositionChange?(nil)
        }
    }
}

// MARK: - Interactive chart wrapper

/// Wraps a chart (SparklineBar / HeatmapBar / BandwidthSparklineView) with
/// mouse tracking and tooltip display. The caller provides a closure that
/// maps an X fraction (0…1) to tooltip content.
struct InteractiveChart<Chart: View>: View {
    let chart: Chart
    let tooltipBuilder: (CGFloat) -> ChartTooltip.Content?
    let colorScheme: HeatmapColorScheme
    let latencyThreshold: Double

    @State private var mouseX: CGFloat?

    var body: some View {
        chart
            .overlay {
                GeometryReader { geo in
                    ChartMouseTracker { x in
                        mouseX = x
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let mx = mouseX {
                        // Vertical crosshair line
                        Path { path in
                            path.move(to: CGPoint(x: mx, y: 0))
                            path.addLine(to: CGPoint(x: mx, y: geo.size.height))
                        }
                        .stroke(.white.opacity(0.35), lineWidth: 0.5)

                        // Tooltip floating above the chart
                        if let content = tooltipBuilder(mx / geo.size.width) {
                            ChartTooltip(content: content, colorScheme: colorScheme, latencyThreshold: latencyThreshold)
                                .fixedSize()
                                .offset(
                                    x: tooltipOffsetX(mouseX: mx, chartWidth: geo.size.width),
                                    y: -48
                                )
                        }
                    }
                }
            }
    }

    private func tooltipOffsetX(mouseX: CGFloat, chartWidth: CGFloat) -> CGFloat {
        // Place tooltip to the right of cursor, or left if near the right edge
        if mouseX > chartWidth * 0.6 {
            return mouseX - 170
        } else {
            return mouseX + 12
        }
    }
}
