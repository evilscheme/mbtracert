# Menubar Sparkline Background + Font Reduction

## Summary

Add an optional solid background color behind the menubar sparkline to improve visibility on varied wallpapers. Each theme defines its own background color. Also reduce the latency font size to save menubar space.

## Changes

### 1. Rewrite SparklineLabel as Canvas

Replace the NSImage + lockFocus rendering in `SparklineView.swift` with a SwiftUI `Canvas` view. Port the existing line-segment gradient drawing logic (stepped Y scale, subdivided segments with Y-position-based coloring). Dimensions stay ~32x18.

### 2. Per-theme menuBarBackground on HeatmapColorScheme

Add a `menuBarBackground` computed property returning an RGB tuple for each theme. Hand-picked dark colors that complement each theme's palette. Exposed as both `Color` and used directly in Canvas drawing.

### 3. Settings toggle

New `@AppStorage("showSparklineBackground")` bool, default `false`. Simple on/off toggle in the General settings tab. When enabled, the Canvas draws a filled rounded rect behind the sparkline.

### 4. Font size reduction

Drop latency text from `ofSize: 9` to `ofSize: 8` in `TraceBarApp.swift`.

## Files Modified

- `TraceBar/Views/SparklineView.swift` — rewrite as Canvas, add background support
- `TraceBar/Models/HeatmapColorScheme.swift` — add menuBarBackground per theme
- `TraceBar/ViewModels/TracerouteViewModel.swift` — add showSparklineBackground AppStorage
- `TraceBar/Views/SettingsView.swift` — add toggle
- `TraceBar/TraceBarApp.swift` — pass background setting to SparklineLabel, reduce font size
