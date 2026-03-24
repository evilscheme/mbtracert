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

        assertSnapshot(of: hostingView, as: .image(perceptualPrecision: 0.98, size: chartSize),
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
