# Menubar Sparkline Background + Font Reduction — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an optional per-theme solid background color behind the menubar sparkline, and reduce the latency font size.

**Architecture:** Rewrite SparklineLabel from NSImage/CoreGraphics to SwiftUI Canvas. Add a `menuBarBackground` color property to each HeatmapColorScheme theme. Gate via a settings toggle.

**Tech Stack:** Swift, SwiftUI Canvas, AppStorage

---

### Task 1: Add menuBarBackground to HeatmapColorScheme

**Files:**
- Modify: `TraceBar/TraceBar/Models/HeatmapColorScheme.swift`

**Step 1: Add the menuBarBackground property**

After the `timeoutColor` computed property (~line 107), add:

```swift
/// Per-theme background color for the menubar sparkline.
var menuBarBackground: Color {
    let c = menuBarBackgroundRGB
    return Color(red: c.0, green: c.1, blue: c.2)
}

private var menuBarBackgroundRGB: RGB {
    switch self {
    case .lagoon:      return (0.06, 0.10, 0.22)
    case .thermal:     return (0.10, 0.05, 0.18)
    case .verdant:     return (0.02, 0.12, 0.08)
    case .grayscale:   return (0.08, 0.08, 0.08)
    case .sunset:      return (0.18, 0.06, 0.04)
    case .arctic:      return (0.06, 0.10, 0.18)
    case .classic:     return (0.05, 0.05, 0.05)
    case .hotPink:     return (0.14, 0.04, 0.10)
    case .synthwave:   return (0.10, 0.02, 0.14)
    case .skyrose:     return (0.06, 0.08, 0.18)
    case .grape:       return (0.10, 0.04, 0.14)
    case .oceanic:     return (0.02, 0.04, 0.14)
    case .halloween:   return (0.10, 0.04, 0.00)
    case .hotDogStand: return (0.08, 0.02, 0.02)
    }
}
```

**Step 2: Build to verify**

Run: `xcodebuild build -project TraceBar/TraceBar.xcodeproj -scheme TraceBar -quiet`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add TraceBar/TraceBar/Models/HeatmapColorScheme.swift
git commit -m "feat: add per-theme menuBarBackground color"
```

---

### Task 2: Add showSparklineBackground setting

**Files:**
- Modify: `TraceBar/TraceBar/ViewModels/TracerouteViewModel.swift`

**Step 1: Add the AppStorage property**

In the `// MARK: - Settings` section (~line 31, after `showBandwidth`), add:

```swift
@AppStorage("showSparklineBackground") var showSparklineBackground = false
```

**Step 2: Build to verify**

Run: `xcodebuild build -project TraceBar/TraceBar.xcodeproj -scheme TraceBar -quiet`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add TraceBar/TraceBar/ViewModels/TracerouteViewModel.swift
git commit -m "feat: add showSparklineBackground setting"
```

---

### Task 3: Rewrite SparklineLabel as Canvas with background support

**Files:**
- Modify: `TraceBar/TraceBar/Views/SparklineView.swift`

**Step 1: Replace the entire SparklineView.swift contents**

Rewrite SparklineLabel as a Canvas view. The new version:
- Takes the same inputs (`dataPoints`, `colorScheme`, `latencyThreshold`) plus new `showBackground: Bool`
- Uses SwiftUI `Canvas` instead of `NSImage` + `lockFocus`
- Draws optional rounded-rect background first when `showBackground` is true
- Ports the existing stepped Y scale and subdivided gradient segment logic
- Note: Canvas Y-axis is flipped vs NSImage (0 = top), so use `(1 - value/scale)` like SparklineBar does

```swift
import SwiftUI

struct SparklineLabel: View {
    let dataPoints: [Double]
    let colorScheme: HeatmapColorScheme
    let latencyThreshold: Double
    var showBackground: Bool = false

    var body: some View {
        Canvas { context, size in
            let padding: CGFloat = 1

            // Background
            if showBackground {
                let bg = RoundedRectangle(cornerRadius: 3)
                    .path(in: CGRect(origin: .zero, size: size))
                context.fill(bg, with: .color(colorScheme.menuBarBackground))
            }

            guard !dataPoints.isEmpty else {
                // Flat baseline
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height - 1))
                line.addLine(to: CGPoint(x: size.width, y: size.height - 1))
                context.stroke(line, with: .color(.secondary), lineWidth: 1)
                return
            }

            // Stepped Y scale matching SparklineBar
            let maxVal = dataPoints.max() ?? 10
            let scaleSteps: [Double] = [10, 25, 50, 100, 200, 500, 1000]
            let yScale = scaleSteps.first { $0 >= maxVal } ?? maxVal

            let drawHeight = size.height - padding * 2
            let drawWidth = size.width - padding * 2

            // Build points (Y flipped: low latency at bottom, high at top)
            var points: [(x: CGFloat, y: CGFloat)] = []
            for i in 0..<dataPoints.count {
                let x = padding + CGFloat(i) / CGFloat(max(dataPoints.count - 1, 1)) * drawWidth
                let y = padding + (1 - CGFloat(dataPoints[i]) / CGFloat(yScale)) * drawHeight
                points.append((x: x, y: y))
            }

            // Map Y position back to latency for gradient coloring
            func latencyForY(_ y: CGFloat) -> Double {
                return (1 - Double((y - padding) / drawHeight)) * yScale
            }

            // Draw subdivided segments with Y-position-based gradient coloring
            for i in 1..<points.count {
                let prev = points[i - 1]
                let curr = points[i]

                let dx = curr.x - prev.x
                let dy = curr.y - prev.y
                let segmentLength = sqrt(dx * dx + dy * dy)
                let steps = max(Int(segmentLength / 1.5), 1)

                for s in 0..<steps {
                    let t0 = CGFloat(s) / CGFloat(steps)
                    let t1 = CGFloat(s + 1) / CGFloat(steps)
                    let x0 = prev.x + dx * t0
                    let y0 = prev.y + dy * t0
                    let x1 = prev.x + dx * t1
                    let y1 = prev.y + dy * t1

                    var sub = Path()
                    sub.move(to: CGPoint(x: x0, y: y0))
                    sub.addLine(to: CGPoint(x: x1, y: y1))

                    let midY = (y0 + y1) / 2
                    let color = colorScheme.color(for: latencyForY(midY), maxMs: latencyThreshold)
                    context.stroke(sub, with: .color(color), lineWidth: 1.5)
                }
            }
        }
        .frame(width: 32, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
```

**Step 2: Build to verify**

Run: `xcodebuild build -project TraceBar/TraceBar.xcodeproj -scheme TraceBar -quiet`
Expected: BUILD SUCCEEDED (may warn about unused `import AppKit` removal — that's fine)

**Step 3: Commit**

```bash
git add TraceBar/TraceBar/Views/SparklineView.swift
git commit -m "feat: rewrite SparklineLabel as Canvas with background support"
```

---

### Task 4: Wire up in TraceBarApp + reduce font size

**Files:**
- Modify: `TraceBar/TraceBar/TraceBarApp.swift`

**Step 1: Pass showBackground to SparklineLabel and reduce font size**

In `TraceBarApp.swift`:

1. Change both `ofSize: 9` occurrences to `ofSize: 8`

2. Update the SparklineLabel call (~line 24) to pass the background setting:

```swift
SparklineLabel(dataPoints: viewModel.latencyHistory, colorScheme: viewModel.colorScheme, latencyThreshold: viewModel.latencyThreshold, showBackground: viewModel.showSparklineBackground)
```

**Step 2: Build to verify**

Run: `xcodebuild build -project TraceBar/TraceBar.xcodeproj -scheme TraceBar -quiet`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add TraceBar/TraceBar/TraceBarApp.swift
git commit -m "feat: wire up sparkline background, reduce font to 8pt"
```

---

### Task 5: Add settings toggle

**Files:**
- Modify: `TraceBar/TraceBar/Views/SettingsView.swift`

**Step 1: Add toggle to GeneralTab**

In the third `Section` block (the one with "Show interface bandwidth"), add before that toggle (~line 66):

```swift
Toggle("Sparkline background", isOn: $viewModel.showSparklineBackground)
    .help("Show a solid color behind the menubar sparkline for better visibility")
```

**Step 2: Build to verify**

Run: `xcodebuild build -project TraceBar/TraceBar.xcodeproj -scheme TraceBar -quiet`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add TraceBar/TraceBar/Views/SettingsView.swift
git commit -m "feat: add sparkline background toggle to settings"
```

---

### Task 6: Manual smoke test

**Steps:**
1. Build and run the app in Xcode
2. Verify the menubar latency text is smaller than before
3. Open Settings > General, toggle "Sparkline background" on
4. Verify a rounded dark background appears behind the sparkline in the menu bar
5. Switch between several themes and verify the background color changes appropriately
6. Toggle the setting off and verify background disappears
7. Verify the sparkline line rendering looks identical to before (gradient coloring, stepped scale)
