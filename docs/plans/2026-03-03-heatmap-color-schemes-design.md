# Heatmap Color Scheme Selection

## Problem

The current green→yellow→red gradient is visually harsh. Both HeatmapBar and SparklineView have independent, hardcoded color functions.

## Solution

A `HeatmapColorScheme` enum providing 6 aesthetically distinct palettes, selectable in Settings. Both views share the same scheme.

### Schemes

Each scheme defines 3 color stops (0ms, 50ms, 100ms+) with linear RGB interpolation, plus a timeout color.

| Scheme | 0ms (good) | 50ms (mid) | 100ms+ (bad) | Timeout |
|--------|-----------|-----------|-------------|---------|
| Oceanic | Teal #2DD4BF | Sky #38BDF8 | Amber #F59E0B | Slate #1E293B |
| Thermal | Indigo #818CF8 | Purple #C084FC | Hot pink #F472B6 | Black #000000 |
| Verdant | Emerald #34D399 | Lime #A3E635 | Amber #FBBF24 | Charcoal #374151 |
| Grayscale | Light #D1D5DB | Mid #6B7280 | Bright #F9FAFB | Black #111827 |
| Sunset | Peach #FDBA74 | Coral #FB7185 | Deep red #DC2626 | Brown #451A03 |
| Arctic | Ice #BAE6FD | Steel #64748B | White #F1F5F9 | Navy #0F172A |

### Architecture

- `HeatmapColorScheme` enum (String, CaseIterable) in `Models/HeatmapColorScheme.swift`
- Provides `color(for ms:) -> Color` and `nsColor(for ms:) -> NSColor`
- Stored via `@AppStorage("colorScheme")` on TracerouteViewModel
- Settings General tab gets a Picker + gradient preview Canvas

### Files

- **New:** `Models/HeatmapColorScheme.swift`
- **Edit:** `Views/HeatmapBar.swift` — use scheme instead of local colorForLatency
- **Edit:** `Views/SparklineView.swift` — use scheme's NSColor variant
- **Edit:** `Views/SettingsView.swift` — add color scheme picker with preview
- **Edit:** `ViewModels/TracerouteViewModel.swift` — add @AppStorage property
