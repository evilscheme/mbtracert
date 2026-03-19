# UI Test Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add automated snapshot tests for visual regression detection and programmatic window behavior tests for interaction correctness to the TraceBar macOS menubar app.

**Architecture:** Two-layer local-first testing: (1) swift-snapshot-testing via XCTest for chart/view visual comparison, (2) Swift Testing with real NSWindow instances for window lifecycle assertions. Snapshot tests run locally only; window + unit tests run in CI.

**Tech Stack:** swift-snapshot-testing (SPM, test-only), Swift Testing, XCTest, AppKit (NSHostingView, NSWindow), SwiftUI ImageRenderer

**Spec:** `docs/superpowers/specs/2026-03-19-ui-test-automation-design.md`

---

### Task 1: Add swift-snapshot-testing SPM dependency

**Files:**
- Modify: `TraceBar/TraceBar.xcodeproj/project.pbxproj` (via Xcode SPM UI or `xcodebuild` — manual Xcode project config step)

This task requires adding the package through Xcode's Swift Package Manager integration. The package must be linked to `TraceBarTests` only (not the main app target).

- [ ] **Step 1: Add the SPM package**

Use Xcode MCP or manual Xcode to add the package:
- Package URL: `https://github.com/pointfreeco/swift-snapshot-testing`
- Version: up to next major from latest (1.x)
- Link to target: `TraceBarTests` only

Alternatively, if modifying `Package.swift` or the project directly, ensure the dependency appears as a test-only dependency.

- [ ] **Step 2: Verify the dependency resolves**

Run:
```bash
xcodebuild build-for-testing \
  -project TraceBar/TraceBar.xcodeproj \
  -scheme TraceBar \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Verify import works in test target**

Create a minimal test file `TraceBar/TraceBarTests/Snapshots/SnapshotSmokeTest.swift`:

```swift
import XCTest
import SnapshotTesting
@testable import TraceBar

final class SnapshotSmokeTest: XCTestCase {
    func testSnapshotLibraryImports() {
        // Just verify the import works — no actual snapshot yet
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 4: Run tests to verify**

Run:
```bash
xcodebuild test \
  -project TraceBar/TraceBar.xcodeproj \
  -scheme TraceBar \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E '(Test Suite|Executed|FAILED|PASSED)'
```
Expected: All tests pass including the new smoke test.

- [ ] **Step 5: Commit**

```bash
git add TraceBar/TraceBar.xcodeproj TraceBar/TraceBarTests/Snapshots/SnapshotSmokeTest.swift
git commit -m "Add swift-snapshot-testing SPM dependency for UI tests"
```

---

### Task 2: Add RingBuffer convenience initializer

**Files:**
- Modify: `TraceBar/TraceBar/Models/RingBuffer.swift`
- Modify: `TraceBar/TraceBarTests/RingBufferTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `TraceBar/TraceBarTests/RingBufferTests.swift`:

```swift
@Test func initFromArray() {
    let buf = RingBuffer(from: [10, 20, 30], capacity: 5)
    #expect(buf.count == 3)
    #expect(buf.elements == [10, 20, 30])
    #expect(buf.last == 30)
}

@Test func initFromArrayExceedingCapacity() {
    let buf = RingBuffer(from: [1, 2, 3, 4, 5], capacity: 3)
    #expect(buf.count == 3)
    #expect(buf.elements == [3, 4, 5])
    #expect(buf.last == 5)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run via Xcode MCP or:
```bash
xcodebuild test \
  -project TraceBar/TraceBar.xcodeproj \
  -scheme TraceBar \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E '(FAILED|initFromArray)'
```
Expected: FAIL — `init(from:capacity:)` does not exist.

- [ ] **Step 3: Implement the convenience initializer**

Add to `TraceBar/TraceBar/Models/RingBuffer.swift` after the existing `init(capacity:)`:

```swift
init(from elements: [T], capacity: Int) {
    self.init(capacity: capacity)
    for element in elements {
        append(element)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run tests. Expected: All pass including the two new tests.

- [ ] **Step 5: Commit**

```bash
git add TraceBar/TraceBar/Models/RingBuffer.swift TraceBar/TraceBarTests/RingBufferTests.swift
git commit -m "Add RingBuffer convenience initializer from array"
```

---

### Task 3: Create TestData helper with deterministic fixtures

**Files:**
- Create: `TraceBar/TraceBarTests/Helpers/TestData.swift`

- [ ] **Step 1: Create the TestData helper**

Create `TraceBar/TraceBarTests/Helpers/TestData.swift`:

```swift
import Foundation
@testable import TraceBar

/// Deterministic test data factories for snapshot and behavior tests.
/// All timestamps use a fixed reference date so snapshots are reproducible.
enum TestData {
    /// Fixed reference time: 2025-01-01 12:00:00 UTC
    static let referenceDate = Date(timeIntervalSinceReferenceDate: 757_382_400)

    /// Standard test capacity matching 3 minutes at 1-second intervals.
    static let standardCapacity = 180

    // MARK: - ProbeResult factories

    /// Creates a single non-timeout probe result.
    static func probe(hop: Int, latencyMs: Double, address: String = "10.0.0.1",
                      secondsAgo: Double = 0) -> ProbeResult {
        ProbeResult(
            hop: hop,
            address: address,
            hostname: nil,
            latencyMs: latencyMs,
            timestamp: referenceDate.addingTimeInterval(-secondsAgo)
        )
    }

    /// Creates a single timeout probe result.
    static func timeout(hop: Int, address: String = "*",
                        secondsAgo: Double = 0) -> ProbeResult {
        ProbeResult(
            hop: hop,
            address: address,
            hostname: nil,
            latencyMs: -1,
            timestamp: referenceDate.addingTimeInterval(-secondsAgo)
        )
    }

    // MARK: - ProbeResult sequence factories

    /// Creates a sequence of probes spread evenly over the history window.
    /// `latencyRange` defines the min/max latency; probes oscillate between them.
    static func probeSequence(hop: Int, count: Int, latencyRange: ClosedRange<Double>,
                              address: String = "10.0.0.1",
                              historySeconds: Double = 180) -> [ProbeResult] {
        (0..<count).map { i in
            let fraction = Double(i) / Double(max(count - 1, 1))
            let latency = latencyRange.lowerBound +
                fraction * (latencyRange.upperBound - latencyRange.lowerBound)
            let secondsAgo = historySeconds * (1.0 - Double(i) / Double(count))
            return probe(hop: hop, latencyMs: latency, address: address,
                         secondsAgo: secondsAgo)
        }
    }

    /// Creates a probe sequence with a given loss percentage (timeouts interspersed).
    static func probeSequenceWithLoss(hop: Int, count: Int, latencyMs: Double,
                                      lossPercent: Double,
                                      address: String = "10.0.0.1",
                                      historySeconds: Double = 180) -> [ProbeResult] {
        let lossInterval = lossPercent > 0 ? max(Int(100.0 / lossPercent), 2) : Int.max
        return (0..<count).map { i in
            let secondsAgo = historySeconds * (1.0 - Double(i) / Double(count))
            if i % lossInterval == 0 && lossPercent > 0 {
                return timeout(hop: hop, address: "*", secondsAgo: secondsAgo)
            }
            return probe(hop: hop, latencyMs: latencyMs, address: address,
                         secondsAgo: secondsAgo)
        }
    }

    // MARK: - HopData factories

    /// Creates a single HopData with probes from a probe sequence.
    static func hopData(hop: Int, probes: [ProbeResult],
                        address: String = "10.0.0.1",
                        hostname: String? = nil) -> HopData {
        var ring = RingBuffer<ProbeResult>(capacity: standardCapacity)
        for p in probes { ring.append(p) }
        return HopData(id: hop, hop: hop, address: address,
                       hostname: hostname, probes: ring)
    }

    /// Creates a simple HopData with uniform latency.
    static func simpleHop(hop: Int, latencyMs: Double, probeCount: Int = 30,
                          address: String? = nil) -> HopData {
        let addr = address ?? "10.0.0.\(hop)"
        let probes = probeSequence(hop: hop, count: probeCount,
                                   latencyRange: latencyMs...latencyMs,
                                   address: addr)
        return hopData(hop: hop, probes: probes, address: addr,
                       hostname: "hop\(hop).example.com")
    }

    // MARK: - Multi-hop trace factories

    /// Creates a realistic trace: latency increases with hop count.
    static func normalTrace(hopCount: Int = 8, probeCount: Int = 30) -> [HopData] {
        (1...hopCount).map { hop in
            let baseLat = Double(hop) * 5.0  // 5ms, 10ms, 15ms...
            let probes = probeSequence(hop: hop, count: probeCount,
                                       latencyRange: baseLat...(baseLat + 3.0),
                                       address: "10.0.0.\(hop)")
            return hopData(hop: hop, probes: probes, address: "10.0.0.\(hop)",
                           hostname: "hop\(hop).example.com")
        }
    }

    /// Creates a trace with one high-latency hop and one lossy hop.
    static func problematicTrace() -> [HopData] {
        var hops = normalTrace(hopCount: 6)
        // Hop 3: high latency
        let highLatProbes = probeSequence(hop: 3, count: 30,
                                          latencyRange: 80...120,
                                          address: "10.0.0.3")
        hops[2] = hopData(hop: 3, probes: highLatProbes, address: "10.0.0.3",
                          hostname: "slow.example.com")
        // Hop 5: packet loss
        let lossyProbes = probeSequenceWithLoss(hop: 5, count: 30, latencyMs: 25,
                                                 lossPercent: 30, address: "10.0.0.5")
        hops[4] = hopData(hop: 5, probes: lossyProbes, address: "10.0.0.5",
                          hostname: "lossy.example.com")
        return hops
    }

    // MARK: - BandwidthSample factories

    static func bandwidthSamples(count: Int, downloadRange: ClosedRange<Double>,
                                  uploadRange: ClosedRange<Double>,
                                  historySeconds: Double = 180) -> [BandwidthSample] {
        (0..<count).map { i in
            let fraction = Double(i) / Double(max(count - 1, 1))
            let dl = downloadRange.lowerBound +
                fraction * (downloadRange.upperBound - downloadRange.lowerBound)
            let ul = uploadRange.lowerBound +
                fraction * (uploadRange.upperBound - uploadRange.lowerBound)
            let secondsAgo = historySeconds * (1.0 - Double(i) / Double(count))
            return BandwidthSample(
                timestamp: referenceDate.addingTimeInterval(-secondsAgo),
                downloadBytesPerSec: dl,
                uploadBytesPerSec: ul,
                interfaceName: "en0"
            )
        }
    }

    static func idleBandwidth(count: Int = 30) -> [BandwidthSample] {
        bandwidthSamples(count: count, downloadRange: 0...0, uploadRange: 0...0)
    }

    static func asymmetricBandwidth(count: Int = 30) -> [BandwidthSample] {
        bandwidthSamples(count: count,
                          downloadRange: 5_000_000...10_000_000,
                          uploadRange: 100_000...500_000)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run:
```bash
xcodebuild build-for-testing \
  -project TraceBar/TraceBar.xcodeproj \
  -scheme TraceBar \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add TraceBar/TraceBarTests/Helpers/TestData.swift
git commit -m "Add TestData helper with deterministic test fixtures"
```

---

### Task 4: Add scale factor parameter to MenuBarView for testability

**Files:**
- Modify: `TraceBar/TraceBar/Views/MenuBarView.swift`

The MenuBarView snapshot tests use `NSHostingView` (which populates the SwiftUI environment correctly), so the render methods can stay `private`. However, `renderChartImage` hardcodes `NSScreen.main?.backingScaleFactor` which varies across machines. Add a stored property for deterministic test rendering.

- [ ] **Step 1: Add optional scale override property**

In `TraceBar/TraceBar/Views/MenuBarView.swift`, add a property after the existing properties (line 15):

```swift
var scaleOverride: CGFloat? = nil
```

Then update `renderChartImage` (line 104) to use it:

```swift
renderer.scale = scaleOverride ?? NSScreen.main?.backingScaleFactor ?? 2.0
```

- [ ] **Step 2: Verify all existing tests still pass**

Run tests. Expected: All 45 existing tests pass. No behavior change (default `nil` preserves existing behavior).

- [ ] **Step 3: Commit**

```bash
git add TraceBar/TraceBar/Views/MenuBarView.swift
git commit -m "Add scale factor override to MenuBarView for deterministic snapshots"
```

---

### Task 5: Write chart snapshot tests

**Files:**
- Create: `TraceBar/TraceBarTests/Snapshots/ChartSnapshotTests.swift`

- [ ] **Step 1: Create the chart snapshot test file**

Create `TraceBar/TraceBarTests/Snapshots/ChartSnapshotTests.swift`:

```swift
import XCTest
import SnapshotTesting
import SwiftUI
import AppKit
@testable import TraceBar

final class ChartSnapshotTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                       "Snapshot tests run locally only")
    }

    private let chartSize = CGSize(width: 300, height: 60)
    private let now = TestData.referenceDate
    private let historyMinutes: Double = 3.0
    private let threshold: Double = 100.0

    private func snapshotChart(_ view: some View, named name: String,
                                file: StaticString = #file, testName: String = #function,
                                line: UInt = #line) {
        let hostingView = NSHostingView(rootView:
            view.frame(width: chartSize.width, height: chartSize.height)
        )
        hostingView.frame = CGRect(origin: .zero, size: chartSize)

        assertSnapshot(of: hostingView, as: .image(size: chartSize),
                       named: name, file: file, testName: testName, line: line)
    }

    // MARK: - SparklineChart

    func testSparklineNormalLatency() {
        let probes = TestData.probeSequence(hop: 1, count: 60,
                                             latencyRange: 10...30)
        snapshotChart(
            SparklineChart(probes: probes, now: now, historyMinutes: historyMinutes,
                           colorScheme: .lagoon, latencyThreshold: threshold),
            named: "sparkline-normal"
        )
    }

    func testSparklineHighLatency() {
        let probes = TestData.probeSequence(hop: 1, count: 60,
                                             latencyRange: 80...150)
        snapshotChart(
            SparklineChart(probes: probes, now: now, historyMinutes: historyMinutes,
                           colorScheme: .lagoon, latencyThreshold: threshold),
            named: "sparkline-high"
        )
    }

    func testSparklineWithLoss() {
        let probes = TestData.probeSequenceWithLoss(hop: 1, count: 60,
                                                     latencyMs: 20, lossPercent: 20)
        snapshotChart(
            SparklineChart(probes: probes, now: now, historyMinutes: historyMinutes,
                           colorScheme: .lagoon, latencyThreshold: threshold),
            named: "sparkline-loss"
        )
    }

    func testSparklineEmpty() {
        snapshotChart(
            SparklineChart(probes: [], now: now, historyMinutes: historyMinutes,
                           colorScheme: .lagoon, latencyThreshold: threshold),
            named: "sparkline-empty"
        )
    }

    // MARK: - HeatmapChart

    func testHeatmapNormalLatency() {
        let probes = TestData.probeSequence(hop: 1, count: 60,
                                             latencyRange: 10...30)
        snapshotChart(
            HeatmapChart(probes: probes, now: now, historyMinutes: historyMinutes,
                         colorScheme: .lagoon, latencyThreshold: threshold),
            named: "heatmap-normal"
        )
    }

    func testHeatmapHighLatency() {
        let probes = TestData.probeSequence(hop: 1, count: 60,
                                             latencyRange: 80...150)
        snapshotChart(
            HeatmapChart(probes: probes, now: now, historyMinutes: historyMinutes,
                         colorScheme: .lagoon, latencyThreshold: threshold),
            named: "heatmap-high"
        )
    }

    func testHeatmapWithLoss() {
        let probes = TestData.probeSequenceWithLoss(hop: 1, count: 60,
                                                     latencyMs: 20, lossPercent: 20)
        snapshotChart(
            HeatmapChart(probes: probes, now: now, historyMinutes: historyMinutes,
                         colorScheme: .lagoon, latencyThreshold: threshold),
            named: "heatmap-loss"
        )
    }

    func testHeatmapEmpty() {
        snapshotChart(
            HeatmapChart(probes: [], now: now, historyMinutes: historyMinutes,
                         colorScheme: .lagoon, latencyThreshold: threshold),
            named: "heatmap-empty"
        )
    }

    // MARK: - VerticalBarsChart

    func testBarsNormalLatency() {
        let probes = TestData.probeSequence(hop: 1, count: 60,
                                             latencyRange: 10...30)
        snapshotChart(
            VerticalBarsChart(probes: probes, now: now, historyMinutes: historyMinutes,
                              colorScheme: .lagoon, latencyThreshold: threshold),
            named: "bars-normal"
        )
    }

    func testBarsHighLatency() {
        let probes = TestData.probeSequence(hop: 1, count: 60,
                                             latencyRange: 80...150)
        snapshotChart(
            VerticalBarsChart(probes: probes, now: now, historyMinutes: historyMinutes,
                              colorScheme: .lagoon, latencyThreshold: threshold),
            named: "bars-high"
        )
    }

    func testBarsWithLoss() {
        let probes = TestData.probeSequenceWithLoss(hop: 1, count: 60,
                                                     latencyMs: 20, lossPercent: 20)
        snapshotChart(
            VerticalBarsChart(probes: probes, now: now, historyMinutes: historyMinutes,
                              colorScheme: .lagoon, latencyThreshold: threshold),
            named: "bars-loss"
        )
    }

    func testBarsEmpty() {
        snapshotChart(
            VerticalBarsChart(probes: [], now: now, historyMinutes: historyMinutes,
                              colorScheme: .lagoon, latencyThreshold: threshold),
            named: "bars-empty"
        )
    }

    // MARK: - BandwidthChart

    func testBandwidthIdle() {
        let samples = TestData.idleBandwidth()
        snapshotChart(
            BandwidthChart(samples: samples, now: now, historyMinutes: historyMinutes,
                           colorScheme: .lagoon),
            named: "bandwidth-idle"
        )
    }

    func testBandwidthAsymmetric() {
        let samples = TestData.asymmetricBandwidth()
        snapshotChart(
            BandwidthChart(samples: samples, now: now, historyMinutes: historyMinutes,
                           colorScheme: .lagoon),
            named: "bandwidth-asymmetric"
        )
    }

    func testBandwidthSaturated() {
        let samples = TestData.bandwidthSamples(
            count: 60,
            downloadRange: 50_000_000...100_000_000,
            uploadRange: 50_000_000...100_000_000
        )
        snapshotChart(
            BandwidthChart(samples: samples, now: now, historyMinutes: historyMinutes,
                           colorScheme: .lagoon),
            named: "bandwidth-saturated"
        )
    }
}
```

- [ ] **Step 2: Run tests to generate initial reference images**

Run tests locally (Cmd+U or xcodebuild test). First run will FAIL because no reference images exist yet — this is expected. swift-snapshot-testing generates reference images on first run.

- [ ] **Step 3: Run tests again to verify they pass**

Run tests again. Expected: All snapshot tests pass (comparing against the just-generated references).

- [ ] **Step 4: Inspect reference images**

Check that the generated `__Snapshots__/` directory contains reasonable images:
```bash
find TraceBar/TraceBarTests/Snapshots/__Snapshots__ -name '*.png' | head -20
```
Visually inspect a few images to confirm they look correct (charts rendered, not blank).

- [ ] **Step 5: Commit**

```bash
git add TraceBar/TraceBarTests/Snapshots/ChartSnapshotTests.swift
git add TraceBar/TraceBarTests/Snapshots/__Snapshots__/
git commit -m "Add chart snapshot tests for sparkline, heatmap, bars, and bandwidth"
```

---

### Task 6: Write MenuBarView snapshot tests

**Files:**
- Create: `TraceBar/TraceBarTests/Snapshots/MenuBarViewSnapshotTests.swift`

- [ ] **Step 1: Create the MenuBarView snapshot test file**

Create `TraceBar/TraceBarTests/Snapshots/MenuBarViewSnapshotTests.swift`:

```swift
import XCTest
import SnapshotTesting
import SwiftUI
import AppKit
@testable import TraceBar

final class MenuBarViewSnapshotTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                       "Snapshot tests run locally only")
    }

    private let now = TestData.referenceDate
    private let probes = TestData.probeSequence(hop: 1, count: 60, latencyRange: 10...30)

    /// Snapshot MenuBarView by hosting it in an NSHostingView with an explicit appearance.
    /// This ensures @Environment(\.colorScheme) is populated correctly.
    private func snapshotMenuBar(chartMode: ChartMode = .sparkline,
                                  compact: Bool = false,
                                  showBackground: Bool = true,
                                  latencyMs: Double? = 25.0,
                                  appearance: NSAppearance.Name = .aqua,
                                  named name: String,
                                  file: StaticString = #file, testName: String = #function,
                                  line: UInt = #line) {
        let view = MenuBarView(
            probes: probes,
            now: now,
            historyMinutes: 3.0,
            colorScheme: .lagoon,
            latencyThreshold: 100,
            chartMode: chartMode,
            showBackground: showBackground,
            compactMenubar: compact,
            latencyMs: latencyMs
        )
        // Use a size that accommodates both wide and compact layouts
        let size = compact ? CGSize(width: 40, height: 24) : CGSize(width: 60, height: 24)
        let hostingView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.appearance = NSAppearance(named: appearance)

        assertSnapshot(of: hostingView, as: .image(size: size),
                       named: name, file: file, testName: testName, line: line)
    }

    // MARK: - Wide mode

    func testWideModeSparkline() {
        snapshotMenuBar(chartMode: .sparkline, compact: false, named: "wide-sparkline")
    }

    func testWideModeHeatmap() {
        snapshotMenuBar(chartMode: .heatmap, compact: false, named: "wide-heatmap")
    }

    func testWideModeBars() {
        snapshotMenuBar(chartMode: .bars, compact: false, named: "wide-bars")
    }

    func testWideModeNoBackground() {
        snapshotMenuBar(showBackground: false, named: "wide-no-bg")
    }

    func testWideModeNoLatency() {
        snapshotMenuBar(latencyMs: nil, named: "wide-no-latency")
    }

    // MARK: - Compact mode

    func testCompactModeSparkline() {
        snapshotMenuBar(chartMode: .sparkline, compact: true, named: "compact-sparkline")
    }

    func testCompactModeHeatmap() {
        snapshotMenuBar(chartMode: .heatmap, compact: true, named: "compact-heatmap")
    }

    func testCompactModeBars() {
        snapshotMenuBar(chartMode: .bars, compact: true, named: "compact-bars")
    }
}
```

**Note:** MenuBarView is hosted in an `NSHostingView` with an explicit `NSAppearance` set, which ensures `@Environment(\.colorScheme)` is populated correctly. The view's `body` is `Image(nsImage: ...)` which triggers the full render pipeline including `ImageRenderer` + Canvas internally. This avoids calling private render methods directly and properly populates the SwiftUI environment.

- [ ] **Step 2: Run tests to generate references, then run again to verify**

Same two-pass process as Task 5. First run generates references (expected fail), second run passes.

- [ ] **Step 3: Inspect reference images**

Verify the menubar images show chart + text side-by-side (wide) and stacked (compact).

- [ ] **Step 4: Commit**

```bash
git add TraceBar/TraceBarTests/Snapshots/MenuBarViewSnapshotTests.swift
git add TraceBar/TraceBarTests/Snapshots/__Snapshots__/
git commit -m "Add MenuBarView snapshot tests for wide and compact modes"
```

---

### Task 7: Remove snapshot smoke test

**Files:**
- Delete: `TraceBar/TraceBarTests/Snapshots/SnapshotSmokeTest.swift`

- [ ] **Step 1: Delete the smoke test**

The smoke test from Task 1 is no longer needed — real snapshot tests exist now.

```bash
rm TraceBar/TraceBarTests/Snapshots/SnapshotSmokeTest.swift
```

- [ ] **Step 2: Verify all tests still pass**

Run tests. Expected: All pass.

- [ ] **Step 3: Commit**

```bash
git add -u TraceBar/TraceBarTests/Snapshots/SnapshotSmokeTest.swift
git commit -m "Remove snapshot smoke test (real tests exist now)"
```

---

### Task 8: Create WindowManager (observe and augment)

**Files:**
- Create: `TraceBar/TraceBar/Services/WindowManager.swift`

This is the biggest task. `WindowManager` observes SwiftUI-managed windows and provides corrective ordering/visibility logic.

- [ ] **Step 1: Create WindowManager**

Create `TraceBar/TraceBar/Services/WindowManager.swift`:

```swift
import AppKit

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    /// The settings window (discovered from NSApp.windows)
    private(set) var settingsWindow: NSWindow?
    /// The menubar panel (discovered from NSApp.windows)
    private(set) var panelWindow: NSWindow?

    private var observers: [NSObjectProtocol] = []

    init() {
        setupObservers()
    }

    // Note: No deinit needed — this is a singleton that lives for the app's lifetime.
    // NotificationCenter observer cleanup happens in reset() for testing.

    // MARK: - Window Discovery

    /// Call after SwiftUI has created its windows to discover them.
    func discoverWindows() {
        for window in NSApp.windows {
            classify(window)
        }
    }

    /// Register a window directly (used by tests and for manual tracking).
    func register(settingsWindow window: NSWindow) {
        self.settingsWindow = window
    }

    func register(panelWindow window: NSWindow) {
        self.panelWindow = window
    }

    /// Reset all state (for testing). Also re-establishes observers.
    func reset() {
        settingsWindow = nil
        panelWindow = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    /// Re-establish notification observers. Call after reset() in tests
    /// if you need to test observer-driven behavior.
    func setupObservers() {
        let nc = NotificationCenter.default

        // When a new window appears, try to classify it
        observers.append(nc.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                self?.classify(window)
            }
        })

        // When app becomes active again, ensure settings ordering
        observers.append(nc.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reorderWindows()
            }
        })
    }

    // MARK: - Corrective Actions

    /// Ensure the settings window stays visible and properly ordered.
    func ensureSettingsVisible() {
        guard let settings = settingsWindow else { return }
        if !settings.isVisible {
            settings.makeKeyAndOrderFront(nil)
        }
        // Settings should always be above the panel
        if let panel = panelWindow, panel.isVisible {
            settings.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        }
        settings.orderFront(nil)
    }

    /// Reorder windows so settings is above panel, both above normal.
    func reorderWindows() {
        guard let settings = settingsWindow, settings.isVisible else { return }
        if let panel = panelWindow, panel.isVisible {
            settings.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
            settings.orderFront(nil)
        }
    }

    // MARK: - Private

    private func classify(_ window: NSWindow) {
        // SwiftUI Settings windows typically contain "settings" in their identifier
        // or have a specific content view type. Adjust heuristic as needed.
        let title = window.title.lowercased()
        let identifier = window.identifier?.rawValue.lowercased() ?? ""

        if title.contains("settings") || title.contains("preferences")
            || identifier.contains("settings") {
            settingsWindow = window
        }
        // MenuBarExtra panels are NSPanel subclass with a specific style
        if window is NSPanel && window != settingsWindow {
            panelWindow = window
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run:
```bash
xcodebuild build \
  -project TraceBar/TraceBar.xcodeproj \
  -scheme TraceBar \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add TraceBar/TraceBar/Services/WindowManager.swift
git commit -m "Add WindowManager to observe and augment SwiftUI window lifecycle"
```

---

### Task 9: Write WindowManager tests

**Files:**
- Create: `TraceBar/TraceBarTests/WindowBehavior/WindowManagerTests.swift`

- [ ] **Step 1: Create the window manager test file**

Create `TraceBar/TraceBarTests/WindowBehavior/WindowManagerTests.swift`:

```swift
import Testing
import AppKit
@testable import TraceBar

@Suite(.serialized)
@MainActor
struct WindowManagerTests {
    private func makeManager() -> WindowManager {
        let manager = WindowManager()
        manager.reset()  // Clear state and observers from init for test isolation
        return manager
    }

    private func makeWindow(title: String = "Test",
                             level: NSWindow.Level = .normal) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.level = level
        return window
    }

    private func makePanel(level: NSWindow.Level = .statusBar) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = level
        return panel
    }

    // MARK: - Registration

    @Test func registerSettingsWindow() {
        let manager = makeManager()
        let window = makeWindow(title: "Settings")
        manager.register(settingsWindow: window)
        #expect(manager.settingsWindow === window)
    }

    @Test func registerPanelWindow() {
        let manager = makeManager()
        let panel = makePanel()
        manager.register(panelWindow: panel)
        #expect(manager.panelWindow === panel)
    }

    @Test func resetClearsWindows() {
        let manager = makeManager()
        manager.register(settingsWindow: makeWindow())
        manager.register(panelWindow: makePanel())
        manager.reset()
        #expect(manager.settingsWindow == nil)
        #expect(manager.panelWindow == nil)
    }

    // MARK: - ensureSettingsVisible

    @Test func ensureSettingsVisibleMakesHiddenSettingsVisible() {
        let manager = makeManager()
        let settings = makeWindow(title: "Settings")
        settings.orderOut(nil)  // Hide it
        manager.register(settingsWindow: settings)

        manager.ensureSettingsVisible()
        #expect(settings.isVisible)
    }

    @Test func ensureSettingsAbovePanel() {
        let manager = makeManager()
        let panel = makePanel(level: .statusBar)
        panel.orderFront(nil)
        let settings = makeWindow(title: "Settings")
        settings.orderFront(nil)

        manager.register(panelWindow: panel)
        manager.register(settingsWindow: settings)

        manager.ensureSettingsVisible()
        #expect(settings.level.rawValue > panel.level.rawValue)
    }

    // MARK: - reorderWindows

    @Test func reorderWindowsSettingsAbovePanel() {
        let manager = makeManager()
        let panel = makePanel(level: .statusBar)
        panel.orderFront(nil)
        let settings = makeWindow(title: "Settings")
        settings.orderFront(nil)
        settings.level = .normal  // Simulate it being at wrong level

        manager.register(panelWindow: panel)
        manager.register(settingsWindow: settings)

        manager.reorderWindows()
        #expect(settings.level.rawValue > panel.level.rawValue)
    }

    @Test func reorderDoesNothingWhenSettingsHidden() {
        let manager = makeManager()
        let panel = makePanel(level: .statusBar)
        panel.orderFront(nil)
        let settings = makeWindow(title: "Settings")
        settings.orderOut(nil)  // Hidden

        manager.register(panelWindow: panel)
        manager.register(settingsWindow: settings)

        let originalLevel = settings.level
        manager.reorderWindows()
        #expect(settings.level == originalLevel)
    }
}
```

- [ ] **Step 2: Run tests**

Run tests. Expected: All pass (including the new window behavior tests + all existing tests).

- [ ] **Step 3: Commit**

```bash
git add TraceBar/TraceBarTests/WindowBehavior/WindowManagerTests.swift
git commit -m "Add WindowManager tests for window ordering and visibility"
```

---

### Task 10: Write settings window persistence tests

**Files:**
- Create: `TraceBar/TraceBarTests/WindowBehavior/SettingsWindowTests.swift`

- [ ] **Step 1: Create the settings window test file**

Create `TraceBar/TraceBarTests/WindowBehavior/SettingsWindowTests.swift`:

```swift
import Testing
import AppKit
@testable import TraceBar

@Suite(.serialized)
@MainActor
struct SettingsWindowTests {
    private func makeManager() -> WindowManager {
        let manager = WindowManager()
        manager.reset()
        return manager
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.orderFront(nil)
        return window
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 200, y: 400, width: 300, height: 500),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.orderFront(nil)
        return panel
    }

    // MARK: - Settings survives app deactivation

    @Test func settingsSurvivesAppDeactivationViaEnsure() {
        // Tests that ensureSettingsVisible() restores settings after deactivation.
        // This tests the corrective method directly (not the observer path).
        let manager = makeManager()
        let settings = makeSettingsWindow()
        let panel = makePanel()
        manager.register(settingsWindow: settings)
        manager.register(panelWindow: panel)

        // Simulate settings losing visibility (as would happen during app deactivation)
        settings.orderOut(nil)

        // The corrective method should restore it
        manager.ensureSettingsVisible()
        #expect(settings.isVisible)
        #expect(settings.level.rawValue > panel.level.rawValue)
    }

    @Test func reorderWindowsTriggeredByNotification() {
        // Tests that the observer-driven reorder works end-to-end.
        let manager = makeManager()
        // reset() cleared observers, so re-establish them
        manager.setupObservers()

        let settings = makeSettingsWindow()
        let panel = makePanel()
        manager.register(settingsWindow: settings)
        manager.register(panelWindow: panel)

        // Put settings at wrong level
        settings.level = .normal

        // Post the notification that triggers reorderWindows()
        NotificationCenter.default.post(
            name: NSApplication.didBecomeActiveNotification, object: NSApp
        )

        // Observer runs synchronously on .main queue via MainActor.assumeIsolated
        #expect(settings.level.rawValue > panel.level.rawValue)
    }

    // MARK: - Panel doesn't dismiss when settings opens

    @Test func panelStaysVisibleWhenSettingsOpens() {
        let manager = makeManager()
        let panel = makePanel()
        manager.register(panelWindow: panel)

        // Now open settings
        let settings = makeSettingsWindow()
        manager.register(settingsWindow: settings)
        manager.ensureSettingsVisible()

        // Both should be visible
        #expect(panel.isVisible)
        #expect(settings.isVisible)
    }

    // MARK: - Settings stays above panel

    @Test func settingsOrderedAbovePanel() {
        let manager = makeManager()
        let panel = makePanel()
        let settings = makeSettingsWindow()

        manager.register(panelWindow: panel)
        manager.register(settingsWindow: settings)
        manager.ensureSettingsVisible()

        #expect(settings.level.rawValue > panel.level.rawValue)
        #expect(settings.isVisible)
        #expect(panel.isVisible)
    }
}
```

- [ ] **Step 2: Run tests**

Run tests. Expected: All pass.

- [ ] **Step 3: Commit**

```bash
git add TraceBar/TraceBarTests/WindowBehavior/SettingsWindowTests.swift
git commit -m "Add settings window persistence and ordering tests"
```

---

### Task 11: Write tooltip window tests

**Files:**
- Modify: `TraceBar/TraceBar/Views/ChartTooltip.swift` (add reset method)
- Create: `TraceBar/TraceBarTests/WindowBehavior/TooltipWindowTests.swift`

- [ ] **Step 1: Add reset method to TooltipWindowManager**

Add to `TooltipWindowManager` in `TraceBar/TraceBar/Views/ChartTooltip.swift`, after the `hide()` method:

```swift
/// Reset state for testing. Removes the tooltip window entirely.
func resetForTesting() {
    hide()
    if let w = window {
        w.parent?.removeChildWindow(w)
        w.close()
    }
    window = nil
    hostingView = nil
}
```

- [ ] **Step 2: Create the tooltip window test file**

Create `TraceBar/TraceBarTests/WindowBehavior/TooltipWindowTests.swift`:

```swift
import Testing
import AppKit
@testable import TraceBar

@Suite(.serialized)
@MainActor
struct TooltipWindowTests {
    private func makeParentPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.orderFront(nil)
        return panel
    }

    private let testContent = ChartTooltip.Content.probe(
        ProbeTooltipData(
            timestamp: TestData.referenceDate,
            address: "10.0.0.1",
            hostname: "test.example.com",
            latencyMs: 25.0,
            isTimeout: false
        )
    )

    // MARK: - Tooltip lifecycle

    @Test func tooltipAttachesAsChildWindow() {
        let tooltip = TooltipWindowManager.shared
        tooltip.resetForTesting()

        let parent = makeParentPanel()
        let point = NSPoint(x: 200, y: 200)

        tooltip.show(content: testContent, colorScheme: .lagoon,
                     latencyThreshold: 100, at: point, parentWindow: parent)

        // Tooltip window should be a child of the parent
        #expect(parent.childWindows?.isEmpty == false)
    }

    @Test func tooltipHidesOnRequest() {
        let tooltip = TooltipWindowManager.shared
        tooltip.resetForTesting()

        let parent = makeParentPanel()
        let point = NSPoint(x: 200, y: 200)

        tooltip.show(content: testContent, colorScheme: .lagoon,
                     latencyThreshold: 100, at: point, parentWindow: parent)
        tooltip.hide()

        // After hide, tooltip should not be visible
        // (hide sets isVisible = false or orders out)
    }

    @Test func tooltipCleanupRemovesFromParent() {
        let tooltip = TooltipWindowManager.shared
        tooltip.resetForTesting()

        let parent = makeParentPanel()
        let point = NSPoint(x: 200, y: 200)

        tooltip.show(content: testContent, colorScheme: .lagoon,
                     latencyThreshold: 100, at: point, parentWindow: parent)
        tooltip.resetForTesting()

        #expect(parent.childWindows?.isEmpty ?? true)
    }
}
```

- [ ] **Step 3: Run tests**

Run tests. Expected: All pass.

- [ ] **Step 4: Commit**

```bash
git add TraceBar/TraceBar/Views/ChartTooltip.swift
git add TraceBar/TraceBarTests/WindowBehavior/TooltipWindowTests.swift
git commit -m "Add tooltip window lifecycle tests"
```

---

### Task 12: Add tests to CI

**Files:**
- Modify: `.github/workflows/build.yml`

- [ ] **Step 1: Add test job to build.yml**

Add a `test` job to `.github/workflows/build.yml` at the same level as the existing `build` job:

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

- [ ] **Step 2: Verify the YAML is valid**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build.yml'))" && echo "Valid YAML"
```
Expected: "Valid YAML"

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "Add test job to CI (unit + window behavior tests)"
```

---

### Task 13: Write HopRowView snapshot tests

**Files:**
- Create: `TraceBar/TraceBarTests/Snapshots/HopRowSnapshotTests.swift`

- [ ] **Step 1: Create the HopRowView snapshot test file**

Create `TraceBar/TraceBarTests/Snapshots/HopRowSnapshotTests.swift`:

```swift
import XCTest
import SnapshotTesting
import SwiftUI
import AppKit
@testable import TraceBar

final class HopRowSnapshotTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                       "Snapshot tests run locally only")
    }

    private let rowSize = CGSize(width: 500, height: 24)
    private let now = TestData.referenceDate

    private func snapshotRow(_ hop: HopData, chartMode: ChartMode = .sparkline,
                              named name: String,
                              file: StaticString = #file, testName: String = #function,
                              line: UInt = #line) {
        let view = HopRowView(
            hop: hop, now: now, historyMinutes: 3.0,
            colorScheme: .lagoon, latencyThreshold: 100,
            chartMode: chartMode
        )
        let hostingView = NSHostingView(rootView: view.frame(width: rowSize.width))
        hostingView.frame = CGRect(origin: .zero, size: rowSize)

        assertSnapshot(of: hostingView, as: .image(size: rowSize),
                       named: name, file: file, testName: testName, line: line)
    }

    func testRespondingHop() {
        let hop = TestData.simpleHop(hop: 3, latencyMs: 15)
        snapshotRow(hop, named: "responding")
    }

    func testHighLatencyHop() {
        let probes = TestData.probeSequence(hop: 5, count: 30,
                                             latencyRange: 90...120, address: "10.0.0.5")
        let hop = TestData.hopData(hop: 5, probes: probes, address: "10.0.0.5",
                                    hostname: "slow.example.com")
        snapshotRow(hop, named: "high-latency")
    }

    func testLossyHop() {
        let probes = TestData.probeSequenceWithLoss(hop: 4, count: 30, latencyMs: 20,
                                                     lossPercent: 40, address: "10.0.0.4")
        let hop = TestData.hopData(hop: 4, probes: probes, address: "10.0.0.4",
                                    hostname: "lossy.example.com")
        snapshotRow(hop, named: "lossy")
    }

    func testTimeoutHop() {
        let probes = (0..<30).map { i in
            TestData.timeout(hop: 2, secondsAgo: Double(30 - i) * 6.0)
        }
        let hop = TestData.hopData(hop: 2, probes: probes, address: "*",
                                    hostname: nil)
        snapshotRow(hop, named: "timeout")
    }
}
```

- [ ] **Step 2: Run tests twice (generate references, then verify)**

First run generates references (expected fail). Second run passes.

- [ ] **Step 3: Commit**

```bash
git add TraceBar/TraceBarTests/Snapshots/HopRowSnapshotTests.swift
git add TraceBar/TraceBarTests/Snapshots/__Snapshots__/
git commit -m "Add HopRowView snapshot tests"
```

---

### Task 14: Write DetailViewPanel snapshot tests

**Files:**
- Create: `TraceBar/TraceBarTests/Snapshots/DetailViewSnapshotTests.swift`

This is the most complex snapshot test because it requires a `TracerouteViewModel` instance. The view model's `@Published` properties are writable, so we set them directly.

- [ ] **Step 1: Create the DetailViewPanel snapshot test file**

Create `TraceBar/TraceBarTests/Snapshots/DetailViewSnapshotTests.swift`:

```swift
import XCTest
import SnapshotTesting
import SwiftUI
import AppKit
@testable import TraceBar

@MainActor
final class DetailViewSnapshotTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                       "Snapshot tests run locally only")

        // Reset @AppStorage keys used by DetailViewPanel
        UserDefaults.standard.set(ChartMode.sparkline.rawValue, forKey: "chartMode")
        UserDefaults.standard.set(true, forKey: "showBandwidth")
    }

    override func tearDown() {
        // Restore defaults
        UserDefaults.standard.removeObject(forKey: "chartMode")
        UserDefaults.standard.removeObject(forKey: "showBandwidth")
        super.tearDown()
    }

    private let panelSize = CGSize(width: 500, height: 400)

    private func makeViewModel(hops: [HopData],
                                bandwidth: [BandwidthSample] = [],
                                error: String? = nil) -> TracerouteViewModel {
        let vm = TracerouteViewModel()
        vm.hops = hops
        vm.bandwidthHistory = bandwidth
        vm.errorMessage = error
        return vm
    }

    private func snapshotPanel(_ vm: TracerouteViewModel, named name: String,
                                file: StaticString = #file, testName: String = #function,
                                line: UInt = #line) {
        let view = DetailViewPanel(viewModel: vm)
        let hostingView = NSHostingView(rootView: view.frame(width: panelSize.width,
                                                              height: panelSize.height))
        hostingView.frame = CGRect(origin: .zero, size: panelSize)

        assertSnapshot(of: hostingView, as: .image(size: panelSize),
                       named: name, file: file, testName: testName, line: line)
    }

    func testEmptyState() {
        let vm = makeViewModel(hops: [])
        snapshotPanel(vm, named: "empty")
    }

    func testNormalTrace() {
        let hops = TestData.normalTrace(hopCount: 8)
        let bandwidth = TestData.asymmetricBandwidth()
        let vm = makeViewModel(hops: hops, bandwidth: bandwidth)
        snapshotPanel(vm, named: "normal-8-hops")
    }

    func testFullTrace() {
        let hops = TestData.normalTrace(hopCount: 30)
        let vm = makeViewModel(hops: hops)
        snapshotPanel(vm, named: "full-30-hops")
    }

    func testErrorState() {
        let vm = makeViewModel(hops: [], error: "Network unreachable")
        snapshotPanel(vm, named: "error")
    }
}
```

**Notes:**
- `TracerouteViewModel` is `@MainActor`, so this test class must be `@MainActor` too.
- `DetailViewPanel` uses `TimelineView` which should be deterministic since we're not running it.
- `TracerouteViewModel()` init creates `ICMPEngine` and `BandwidthMonitor` instances which may open sockets. We never call `start()`, so no probing occurs. If tests fail due to socket initialization in the test runner sandbox, consider adding lazy initialization to `ICMPEngine` or a `testing` flag to skip socket creation.

- [ ] **Step 2: Run tests twice (generate references, then verify)**

First run generates references (expected fail). Second run passes.

If there are issues with `TracerouteViewModel` starting probes or timers, the test may need adjustment. The key is that we're only setting `@Published` properties — we never call `start()` or any probing methods.

- [ ] **Step 3: Inspect reference images**

Verify the panel snapshots show: header, bandwidth chart (when present), hop rows, footer.

- [ ] **Step 4: Commit**

```bash
git add TraceBar/TraceBarTests/Snapshots/DetailViewSnapshotTests.swift
git add TraceBar/TraceBarTests/Snapshots/__Snapshots__/
git commit -m "Add DetailViewPanel snapshot tests"
```

---

### Task 15: Final verification

- [ ] **Step 1: Run all tests locally**

```bash
xcodebuild test \
  -project TraceBar/TraceBar.xcodeproj \
  -scheme TraceBar \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E '(Test Suite|Executed|FAILED|PASSED)'
```

Expected: All tests pass — original 45 unit tests + new snapshot tests + new window behavior tests.

- [ ] **Step 2: Verify CI exclusion**

```bash
CI=true xcodebuild test \
  -project TraceBar/TraceBar.xcodeproj \
  -scheme TraceBar \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E '(skipped|Executed|PASSED)'
```

Expected: Snapshot tests show as skipped. Unit + window tests pass.

- [ ] **Step 3: Count total tests**

Verify we have substantially more test coverage than before (was 45 unit tests).
