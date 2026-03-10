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

    enum Content: Equatable {
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
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .black))
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
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

// Equatable conformances for Content enum
extension ProbeTooltipData: Equatable {}
extension BandwidthTooltipData: Equatable {}

// MARK: - Tooltip floating window

/// Manages a single borderless, transparent NSWindow that displays the tooltip.
/// The window floats above the panel so it's never clipped by ScrollView or parent bounds.
@MainActor
final class TooltipWindowManager {
    static let shared = TooltipWindowManager()

    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?

    private init() {}

    func show(content: ChartTooltip.Content, colorScheme: HeatmapColorScheme, latencyThreshold: Double, at screenPoint: NSPoint, parentWindow: NSWindow?) {
        let tooltipView = ChartTooltip(content: content, colorScheme: colorScheme, latencyThreshold: latencyThreshold)
        let wrapped = AnyView(tooltipView)

        if let hostingView {
            hostingView.rootView = wrapped
        } else {
            let hosting = NSHostingView(rootView: wrapped)
            hostingView = hosting

            let w = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.contentView = hosting
            window = w
        }

        guard let window, let hostingView else { return }

        // Attach as child of the panel window so it renders above it
        if let parent = parentWindow, window.parent != parent {
            // Remove from previous parent if any
            window.parent?.removeChildWindow(window)
            parent.addChildWindow(window, ordered: .above)
        }

        // Force layout so intrinsic size is up to date
        hostingView.layoutSubtreeIfNeeded()
        let intrinsic = hostingView.intrinsicContentSize
        let tooltipWidth = ceil(intrinsic.width)
        let tooltipHeight = ceil(intrinsic.height)

        // Position: above the cursor, offset to the right.
        // If near the right screen edge, flip to the left.
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? .zero

        var x = screenPoint.x + 14
        let y = screenPoint.y + 12  // above cursor (screen coords: Y goes up)

        // Flip horizontally if it would go off the right edge
        if x + tooltipWidth > screenFrame.maxX {
            x = screenPoint.x - tooltipWidth - 8
        }

        // Clamp to screen left edge
        if x < screenFrame.minX {
            x = screenFrame.minX + 4
        }

        window.setFrame(NSRect(x: x, y: y, width: tooltipWidth, height: tooltipHeight), display: true)
        window.orderFront(nil)
    }

    func hide() {
        if let window {
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
        }
    }
}

// MARK: - Mouse-tracking overlay

/// NSView that tracks mouse position via NSTrackingArea.
/// Reports the local X position, screen-space point, and parent NSWindow for tooltip placement.
struct ChartMouseTracker: NSViewRepresentable {
    let onPositionChange: (CGFloat?, NSPoint?, NSWindow?) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onPositionChange = onPositionChange
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onPositionChange = onPositionChange
    }

    final class TrackingView: NSView {
        var onPositionChange: ((CGFloat?, NSPoint?, NSWindow?) -> Void)?
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
                let windowPoint = convert(local, to: nil)
                let screenPoint = window?.convertPoint(toScreen: windowPoint) ?? .zero
                onPositionChange?(local.x, screenPoint, window)
            } else {
                onPositionChange?(nil, nil, nil)
            }
        }

        override func mouseExited(with event: NSEvent) {
            onPositionChange?(nil, nil, nil)
        }
    }
}

// MARK: - Interactive chart wrapper

/// Wraps a chart (SparklineBar / HeatmapBar / BandwidthSparklineView) with
/// mouse tracking and tooltip display. The tooltip renders in a separate
/// floating NSWindow so it's never clipped by ScrollView or parent bounds.
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
                    ChartMouseTracker { localX, screenPoint, parentWindow in
                        mouseX = localX

                        if let lx = localX, let sp = screenPoint,
                           let content = tooltipBuilder(lx / geo.size.width) {
                            TooltipWindowManager.shared.show(
                                content: content,
                                colorScheme: colorScheme,
                                latencyThreshold: latencyThreshold,
                                at: sp,
                                parentWindow: parentWindow
                            )
                        } else {
                            TooltipWindowManager.shared.hide()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let mx = mouseX {
                        // Vertical crosshair line
                        Path { path in
                            path.move(to: CGPoint(x: mx, y: 0))
                            path.addLine(to: CGPoint(x: mx, y: geo.size.height))
                        }
                        .stroke(.white.opacity(0.35), lineWidth: 0.5)
                    }
                }
            }
            .onDisappear {
                TooltipWindowManager.shared.hide()
            }
    }
}
