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

        assertSnapshot(of: hostingView, as: .image(perceptualPrecision: 0.98, size: rowSize),
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
