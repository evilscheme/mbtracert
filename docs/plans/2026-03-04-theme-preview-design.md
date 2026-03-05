# Theme Preview Tool Design

## Goal

A standalone HTML file for bulk-reviewing and tweaking MenubarTracert's 11 color themes. Addresses both aesthetic and readability concerns by rendering realistic mock UI for each theme side-by-side.

## Deliverable

Single self-contained HTML file (`tools/theme-preview.html`). No dependencies, no build step. Open in any browser.

## Layout

- Dark background (#1a1a1a) matching macOS dark menubar popover
- All 11 themes stacked vertically, each in a card (~400px wide, centered)
- Scrollable page for comparison

## Per-Theme Card Contents

1. **Header**: theme name + gradient bar (0ms to 100ms, continuous)
2. **Timeout swatch**: small color block showing the timeout color
3. **Mock heatmap bars** (Canvas-rendered, same lerp algorithm as HeatmapBar.swift):
   - "Good" hop: mostly 5-15ms with rare spikes
   - "Mediocre" hop: 20-60ms with variance
   - "Bad" hop: 60-150ms with some timeouts
   - "Dead" hop: mostly timeouts
4. **Mock hop rows**: monospaced text with colored latency/loss values matching HopRowView layout
5. **Mock sparkline**: small polyline chart with per-point coloring by latency

## Interactive Editing

- Click a theme card to expand an editor panel
- Color pickers for each gradient stop (2 or 3) + timeout color
- Live preview updates on change
- "Export Swift" button: outputs modified values as copy-pasteable Swift code for HeatmapColorScheme.swift

## Mock Data

Deterministic (seeded PRNG) so all themes render identical patterns, enabling fair visual comparison.

## Color Interpolation

Port the exact algorithm from HeatmapColorScheme.swift:
- Normalize ms to t in [0, 1] (clamped at 100ms)
- 2-stop: lerp(stop0, stop1, t)
- 3-stop: lerp(stop0, stop1, t/0.5) for t<0.5, lerp(stop1, stop2, (t-0.5)/0.5) for t>=0.5
