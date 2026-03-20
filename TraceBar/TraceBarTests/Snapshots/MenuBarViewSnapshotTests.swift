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
            latencyMs: latencyMs,
            scaleOverride: 2.0,
            colorSchemeOverride: .light
        )
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
