# Detail View Sparkline Toggle

## Summary

Add a sparkline (line chart) as an alternate visualization to the heatmap bar in the detail panel's hop rows. A global toggle in the footer switches all rows between heatmap and sparkline views.

## New: SparklineBar view

SwiftUI `Canvas` inside `TimelineView`, same as `HeatmapBar`. Same inputs: `probes: [ProbeResult]`, `historyMinutes`, `activeInterval`, `colorScheme`. Same 14pt height, rounded clip, subtle border.

Renders a connected line graph where each segment is colored by latency via `colorScheme.color(for:)`. Y-axis auto-scales: `max(maxLatency, 10)`. Timeouts render as gaps — line drops to bottom edge with `colorScheme.timeoutColor`. X-axis is time-aligned identically to heatmap (newest right, oldest left, positioned by timestamp age).

## Modified: HopRowView

New parameter `showSparkline: Bool`. Conditionally renders `SparklineBar` or `HeatmapBar` in the history column.

## Modified: TraceroutePanel

- `@State var showSparkline = false`
- Footer gets a toggle button: `chart.line.uptrend.xyaxis` when showing sparkline, `chart.bar.fill` when showing heatmap.
- Passes `showSparkline` through to each `HopRowView`.

## Not changed

Menubar `SparklineLabel` — different rendering approach (NSImage) for a different purpose (overall latency, not per-hop).
