# Detail View Sparkline Toggle — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a per-hop sparkline (line chart) as an alternate visualization to the heatmap bar, toggled globally via a footer button.

**Architecture:** New `SparklineBar` SwiftUI Canvas view mirrors `HeatmapBar`'s interface and time-axis logic. `HopRowView` conditionally renders one or the other based on a bool. `TraceroutePanel` owns the toggle state and exposes a footer button.

**Tech Stack:** Swift, SwiftUI Canvas, TimelineView

---

### Task 1: Create SparklineBar view

**Files:**
- Create: `MenubarTracert/MenubarTracert/Views/SparklineBar.swift`
- Reference: `MenubarTracert/MenubarTracert/Views/HeatmapBar.swift` (mirror structure)

**Step 1: Create SparklineBar.swift**

```swift
import SwiftUI

struct SparklineBar: View {
    let probes: [ProbeResult]
    let historyMinutes: Double
    let activeInterval: Double
    let colorScheme: HeatmapColorScheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: activeInterval)) { timeline in
            Canvas { context, size in
                let now = timeline.date
                let totalSeconds = historyMinutes * 60
                let windowStart = now.addingTimeInterval(-totalSeconds)

                let visible = probes.filter { $0.timestamp >= windowStart }
                guard visible.count >= 2 else { return }

                // Auto-scale Y axis: minimum range of 10ms
                let maxLatency = visible.filter { !$0.isTimeout }.map(\.latencyMs).max() ?? 10
                let yScale = max(maxLatency, 10)
                let padding: CGFloat = 1

                // Build points array
                var points: [(x: CGFloat, y: CGFloat, latencyMs: Double, isTimeout: Bool)] = []
                for probe in visible {
                    let age = now.timeIntervalSince(probe.timestamp)
                    let xFraction = 1.0 - age / totalSeconds
                    let x = padding + CGFloat(xFraction) * (size.width - padding * 2)

                    let y: CGFloat
                    if probe.isTimeout {
                        y = size.height - padding // bottom edge for timeouts
                    } else {
                        y = padding + (1 - CGFloat(probe.latencyMs / yScale)) * (size.height - padding * 2)
                    }
                    points.append((x: x, y: y, latencyMs: probe.latencyMs, isTimeout: probe.isTimeout))
                }

                // Draw connected line segments, each colored by latency
                for i in 1..<points.count {
                    let prev = points[i - 1]
                    let curr = points[i]

                    var segment = Path()
                    segment.move(to: CGPoint(x: prev.x, y: prev.y))
                    segment.addLine(to: CGPoint(x: curr.x, y: curr.y))

                    let color: Color
                    if curr.isTimeout {
                        color = colorScheme.timeoutColor
                    } else {
                        color = colorScheme.color(for: curr.latencyMs)
                    }

                    context.stroke(segment, with: .color(color), lineWidth: 1.5)
                }
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}
```

**Step 2: Build to verify it compiles**

Run: `xcodebuild -project MenubarTracert/MenubarTracert.xcodeproj -scheme MenubarTracert -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add MenubarTracert/MenubarTracert/Views/SparklineBar.swift
git commit -m "feat: add SparklineBar view for per-hop line chart visualization"
```

---

### Task 2: Wire up HopRowView toggle

**Files:**
- Modify: `MenubarTracert/MenubarTracert/Views/HopRowView.swift:3` (add parameter)
- Modify: `MenubarTracert/MenubarTracert/Views/HopRowView.swift:41` (conditional rendering)

**Step 1: Add `showSparkline` parameter to HopRowView**

In `HopRowView.swift`, add a new property after line 7:

```swift
let showSparkline: Bool
```

**Step 2: Replace the HeatmapBar call with conditional rendering**

Replace line 41:
```swift
HeatmapBar(probes: hop.probes.elements, historyMinutes: historyMinutes, activeInterval: activeInterval, colorScheme: colorScheme)
```

With:
```swift
if showSparkline {
    SparklineBar(probes: hop.probes.elements, historyMinutes: historyMinutes, activeInterval: activeInterval, colorScheme: colorScheme)
        .frame(maxWidth: .infinity)
} else {
    HeatmapBar(probes: hop.probes.elements, historyMinutes: historyMinutes, activeInterval: activeInterval, colorScheme: colorScheme)
        .frame(maxWidth: .infinity)
}
```

Note: Move the `.frame(maxWidth: .infinity)` into both branches since the current one on line 42 is chained to only HeatmapBar.

**Step 3: This will not compile yet** — TraceroutePanel needs to pass the new parameter. Proceed to Task 3.

---

### Task 3: Add toggle to TraceroutePanel

**Files:**
- Modify: `MenubarTracert/MenubarTracert/Views/TraceroutePanel.swift:3` (add state)
- Modify: `MenubarTracert/MenubarTracert/Views/TraceroutePanel.swift:109` (pass to HopRowView)
- Modify: `MenubarTracert/MenubarTracert/Views/TraceroutePanel.swift:117-148` (add footer button)

**Step 1: Add state property**

After line 5 (`@Environment(\.openSettings)...`), add:

```swift
@State private var showSparkline = false
```

**Step 2: Pass showSparkline to HopRowView**

Change line 109 from:
```swift
HopRowView(hop: hop, historyMinutes: viewModel.historyMinutes, activeInterval: viewModel.activeInterval, colorScheme: viewModel.colorScheme)
```

To:
```swift
HopRowView(hop: hop, historyMinutes: viewModel.historyMinutes, activeInterval: viewModel.activeInterval, colorScheme: viewModel.colorScheme, showSparkline: showSparkline)
```

**Step 3: Add toggle button to the footer**

In the footer (line 117-148), add a visualization toggle button. Insert after the clear/trash button's `Spacer()` (after line 138) and before the Quit button (line 140):

```swift
Button(action: {
    showSparkline.toggle()
}) {
    Image(systemName: showSparkline ? "chart.line.uptrend.xyaxis" : "chart.bar.fill")
}
.preferringGlassStyle()
.help(showSparkline ? "Switch to heatmap" : "Switch to sparkline")

Spacer()
```

**Step 4: Build to verify everything compiles**

Run: `xcodebuild -project MenubarTracert/MenubarTracert.xcodeproj -scheme MenubarTracert -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add MenubarTracert/MenubarTracert/Views/HopRowView.swift MenubarTracert/MenubarTracert/Views/TraceroutePanel.swift
git commit -m "feat: add sparkline/heatmap toggle to detail panel footer"
```

---

### Task 4: Build, test, and verify

**Step 1: Clean build**

Run: `xcodebuild -project MenubarTracert/MenubarTracert.xcodeproj -scheme MenubarTracert -configuration Debug clean build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 2: Verify no warnings**

Run: `xcodebuild -project MenubarTracert/MenubarTracert.xcodeproj -scheme MenubarTracert -configuration Debug build 2>&1 | grep -i "warning:" | grep -v "deprecated"`
Expected: No output (or only pre-existing warnings)
