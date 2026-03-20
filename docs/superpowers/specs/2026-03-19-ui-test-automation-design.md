# UI Test Automation Design

## Problem

Every code change to TraceBar requires extensive manual UI/UX testing. The most painful issues are window behavior bugs (settings window getting buried, panel dismissing unexpectedly) and visual regressions in chart rendering. The existing 45 unit tests cover models and services but nothing in the UI layer.

## Strategy

Two-layer local-first testing approach:

1. **Snapshot tests** for visual correctness (local only)
2. **Programmatic window behavior tests** for interaction correctness (local + CI)

Additionally, add existing unit tests to CI — they currently don't run there.

## Layer 1: Snapshot Testing

### Dependency

[swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) by Point-Free, added via Swift Package Manager as a test-only dependency.

### Mechanism

Each test creates a SwiftUI view with deterministic test data, hosts it in an `NSHostingView`, forces layout, and captures the rendered result as an image for comparison against a reference.

**Rendering approach:** The production `MenuBarView` already uses `ImageRenderer` with Canvas-based chart views (line 103 of MenuBarView.swift) and this works correctly on macOS 14.6+. However, `ImageRenderer` behavior with Canvas can vary across macOS versions, so snapshot tests use the more reliable `NSHostingView` approach:

- **Chart views** (SparklineChart, HeatmapChart, VerticalBarsChart): Host in `NSHostingView`, force layout, then use swift-snapshot-testing's `assertSnapshot(of: nsHostingView, as: .image(size:))`. This is the standard approach for snapshot-testing AppKit-hosted SwiftUI views and avoids any `ImageRenderer`/`Canvas` version-sensitivity.
- **MenuBarView**: The render methods (`renderWideLabel`, `renderCompactLabel`, `renderChartImage`) are currently `private`. To enable snapshot testing, make `renderChartImage(width:height:)` and the label methods `internal` (accessible via `@testable import TraceBar`). Tests can then call these directly and snapshot the returned `NSImage`. Alternatively, use the same `NSHostingView` approach on the full `MenuBarView` — since its `body` is just `Image(nsImage: ...)`, the hosting view triggers the full render pipeline.

Reference images are stored alongside each test file in `__Snapshots__/<TestClassName>/` subdirectories (swift-snapshot-testing's default convention). These are committed to git.

When a visual change is intentional, delete the reference image and re-run to regenerate.

### Test Framework Note

Snapshot tests use **XCTest** (not Swift Testing) because swift-snapshot-testing's `assertSnapshot` depends on `XCTestCase`. This is fine — XCTest and Swift Testing coexist in the same test target. Window behavior tests and existing unit tests continue to use Swift Testing (`@Test`, `@Suite`).

### Rendering Determinism

To ensure reproducible snapshots across developer machines:
- `MenuBarView` snapshots inject a fixed scale factor (2.0) rather than reading `NSScreen.main?.backingScaleFactor`
- All snapshot tests use a fixed view size via `assertSnapshot(of:, as: .image(size: CGSize(width:height:)))` to eliminate layout ambiguity
- Font rendering differences across macOS versions remain a potential source of flakiness; if this becomes a problem, consider a perceptual diff threshold via swift-snapshot-testing's `precision` parameter (e.g., `precision: 0.99`)

### Test Coverage Matrix

| View | Scenarios |
|---|---|
| MenuBarView | wide x dark/light, compact x dark/light, with/without background, all 3 chart modes |
| SparklineChart | empty data, normal latency, high latency, packet loss, timeout hops |
| HeatmapChart | same data scenarios as SparklineChart |
| VerticalBarsChart | same data scenarios as SparklineChart |
| BandwidthChart | idle (no traffic), asymmetric up/down, saturated |
| HopRowView | responding hop, timed-out hop, high-loss hop |
| DetailViewPanel | empty state (no hops), normal trace (~8 hops), full trace (30 hops) |

### Test Data Fixtures

A `TestData` helper provides factory methods for deterministic test data:

- `TestData.hopData(count:latencyRange:lossPercent:)` — creates `HopData` arrays with known values
- `TestData.probeResults(for:)` — creates `ProbeResult` sequences with fixed timestamps
- `TestData.bandwidthSamples(download:upload:count:)` — creates `BandwidthSample` arrays
- All timestamps are fixed (not `Date()`) so snapshots are reproducible across runs
- `HopData` contains `probes: RingBuffer<ProbeResult>`, so `TestData` must construct `RingBuffer` instances with a standard test capacity (180, matching 3 minutes at 1-second intervals) and append probes. Consider adding a convenience initializer `RingBuffer(from: [T], capacity:)` to simplify test data creation.

### @AppStorage and UserDefaults Isolation

Several views (`DetailViewPanel`, `SettingsView`) read from `@AppStorage`, which uses `UserDefaults.standard`. To ensure deterministic snapshots:
- Each snapshot test class resets relevant `UserDefaults` keys in `setUp()` to known values (e.g., `chartMode = "sparkline"`, `showBandwidth = true`)
- `tearDown()` restores defaults to avoid polluting other tests
- Alternatively, for views that accept chart mode and other settings as parameters (like `MenuBarView`, chart views, `HopRowView`), pass values directly — these views are already testable without `@AppStorage`

### DetailViewPanel Test Setup

`DetailViewPanel` depends on `TracerouteViewModel` (`@ObservedObject`), which is a heavyweight `@MainActor` class that owns ICMP engine and probe scheduling. For snapshot tests:
- Create a `TracerouteViewModel` instance with its `@Published` properties set directly (e.g., `vm.hops = testHops`, `vm.errorMessage = nil`). The view model's published properties are `var`, so they can be set from tests without needing a protocol abstraction.
- Do NOT start probing — only set the display state
- `DetailViewPanel` snapshot tests are intentionally last in implementation order (step 7) since they require the most setup. If the view model proves too coupled, consider extracting a lightweight display-state struct as a future refactor.

### SPM Dependency Linkage

When adding swift-snapshot-testing via SPM, link it to the `TraceBarTests` target only (not the main `TraceBar` app target). The Xcode project uses `PBXFileSystemSynchronizedRootGroup` so new test Swift files are auto-discovered, but the package dependency linkage is a manual Xcode project configuration step.

### Why Local Only

Snapshot tests are sensitive to OS-level rendering differences (font rasterization, anti-aliasing, display scale). A reference image generated on a developer's Mac may not pixel-match on a CI runner with a different macOS version or no physical display. Running these locally avoids false failures.

## Layer 2: Programmatic Window Behavior Tests

### No External Dependencies

These tests use the existing test target with real AppKit `NSWindow`/`NSPanel` objects and `NSNotification` posting.

### Key Refactor: WindowManager

The window management behavior is currently implicit in SwiftUI scene declarations. To make it testable, the window ordering/visibility logic must be extracted into a `WindowManager` class.

**Current state and constraints:**
- The settings window is managed by SwiftUI's `Settings { }` scene in `TraceBarApp.swift`. SwiftUI owns this window entirely.
- The panel is managed by `MenuBarExtra` with `.menuBarExtraStyle(.window)`. SwiftUI owns this window too.
- `openSettings()` environment action in `DetailViewPanel.swift` is the only explicit window control.

**Approach — observe, don't replace:**

Rather than replacing SwiftUI's scene-based window management (which would be a massive rewrite), `WindowManager` will **observe and augment** the SwiftUI-managed windows:

1. `WindowManager` is an `@Observable` singleton initialized at app startup
2. It uses `NSApp.windows` to discover the settings window and panel after SwiftUI creates them (identified by content type or window title)
3. It observes `NSWindow.didBecomeKeyNotification`, `didResignKeyNotification`, `willCloseNotification` to track window state
4. It observes `NSApplication.didBecomeActiveNotification`, `didResignActiveNotification` for app lifecycle
5. It exposes corrective methods: `ensureSettingsVisible()`, `reorderWindows()` that adjust `.level` and `.orderFront()` as needed
6. Views call into `WindowManager` at key moments (e.g., after `openSettings()`, after a setting change) to ensure correct ordering

**For testing:** Tests create real `NSWindow` instances that simulate the settings/panel windows, register them with `WindowManager`, and then assert that `WindowManager`'s corrective logic produces correct window state. This tests the ordering/visibility logic without needing SwiftUI scenes.

**Tooltip windows are also in scope:** `TooltipWindowManager` (existing singleton) manages a floating `NSWindow` for chart tooltips. Its window lifecycle (attach as child, reposition, cleanup on panel close) should also be covered by window behavior tests.

### Test Scenarios

| Scenario | Assertions |
|---|---|
| Settings window opens | `.isVisible == true`, `.isKeyWindow == true`, window level is correct |
| Settings stays above panel | Open panel, open settings: settings ordered above panel |
| Settings survives app deactivation | Open settings, post `didResignActiveNotification`, post `didBecomeActiveNotification`: settings `.isVisible` still true |
| Settings survives setting change | Open settings, change a setting value: settings window still visible, panel still visible |
| Panel doesn't dismiss on settings open | Open panel, open settings: panel `.isVisible == true` |
| Panel dismisses on outside click | Open panel, simulate `NSApp.deactivate()`: assert expected panel behavior |
| Window cleanup on quit | Open both windows, trigger cleanup: no orphan windows |
| Tooltip attaches as child window | Show tooltip on chart: tooltip `.parent` is the panel window |
| Tooltip repositions near screen edge | Tooltip near right edge: tooltip adjusts position to stay on screen |
| Tooltip hides on mouse exit | Mouse exits chart area: tooltip `.isVisible == false` |
| Tooltip cleanup on panel close | Panel closes: tooltip window is also removed |

### How Tests Work

- Tests create real `NSWindow`/`NSPanel` instances, register them with `WindowManager`
- `NotificationCenter.default.post()` simulates app activation/deactivation cycles
- Assertions check `.isVisible`, `.isKeyWindow`, `.level`, `.parent` (child window relationships)
- Tests run in-process (no XCUITest app launch overhead), typically < 100ms each
- Window behavior tests use Swift Testing (`@Suite(.serialized)`) to prevent parallel tests from interfering with each other's window state via shared `NotificationCenter`
- `TooltipWindowManager` is `@MainActor` with a `static let shared` singleton — tooltip tests must run on `@MainActor` (annotate the test suite) and reset singleton state between tests (add a `reset()` method for testing)

## Test Target Structure

```
TraceBar/TraceBarTests/
  (existing - unchanged)
  RingBufferTests.swift
  TracerouteModelsTests.swift
  ICMPParsingTests.swift
  ColorThemeTests.swift

  (new)
  Snapshots/
    MenuBarViewSnapshotTests.swift
    ChartSnapshotTests.swift
    DetailViewSnapshotTests.swift
  WindowBehavior/
    WindowManagerTests.swift
    SettingsWindowTests.swift
    PanelDismissalTests.swift
  Helpers/
    TestData.swift
```

Each snapshot test file gets its own `__Snapshots__/<TestClassName>/` sibling directory automatically (swift-snapshot-testing's default convention). These are git-tracked.

## CI Integration

### Changes to `.github/workflows/build.yml`

Add a separate `test` job (not inside the existing Debug/Release build matrix, since tests only need to run once in Debug):

```yaml
test:
  runs-on: macos-26
  steps:
    - uses: actions/checkout@v4
    - name: Select Xcode
      run: sudo xcode-select -s /Applications/Xcode_26.3.app
    - name: Test
      run: |
        xcodebuild test \
          -project TraceBar/TraceBar.xcodeproj \
          -scheme TraceBar \
          -configuration Debug \
          -destination 'platform=macOS' \
          CODE_SIGN_IDENTITY="-" \
          CODE_SIGNING_ALLOWED=NO
```

### What Runs Where

| Test Category | Local (Cmd+U) | CI |
|---|---|---|
| Unit tests (existing 45) | Yes | Yes |
| Window behavior tests | Yes | Yes |
| Snapshot tests | Yes | No (excluded via test plan or `#if !CI`) |

Snapshot tests are excluded from CI using an environment variable check. Each snapshot test class checks `ProcessInfo.processInfo.environment["CI"] != nil` in `setUp()` and calls `XCTSkipIf` to skip. This is simpler than maintaining a separate test plan and doesn't require CI command changes. GitHub Actions sets `CI=true` by default.

## Local Developer Workflow

1. Make a code change
2. Cmd+U runs all tests
   - Snapshot failures show a `_diff` image highlighting exactly what changed
   - Window behavior failures describe the state mismatch
3. If a snapshot failure is intentional, delete the reference image and re-run to regenerate
4. Commit (reference images included in the commit if changed)
5. Push — CI runs unit tests + window behavior tests

## What This Replaces

| Manual Step | Automated Equivalent |
|---|---|
| "Open settings, switch to Safari, come back — is settings still visible?" | `SettingsWindowTests.testSettingsSurvivesAppDeactivation()` |
| "Open settings, change a setting — did the panel close?" | `SettingsWindowTests.testSettingsSurvivesSettingChange()` |
| "Did that color theme change break the chart?" | Snapshot comparison in `ChartSnapshotTests` |
| "Does the menubar icon look right in compact mode?" | `MenuBarViewSnapshotTests.testCompactDarkMode()` |

## Implementation Order

1. Add swift-snapshot-testing SPM dependency
2. Create `TestData` helper with deterministic fixtures
3. Write snapshot tests for charts and MenuBarView (quick wins, no refactoring)
4. Extract `WindowManager` from existing window logic (biggest refactor)
5. Write window behavior tests against `WindowManager`
6. Add unit tests + window tests to CI
7. Add snapshot tests for DetailViewPanel and HopRowView
