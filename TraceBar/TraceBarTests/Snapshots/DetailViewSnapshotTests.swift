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
        UserDefaults.standard.removeObject(forKey: "chartMode")
        UserDefaults.standard.removeObject(forKey: "showBandwidth")
        super.tearDown()
    }

    private let panelWidth: CGFloat = 600

    private func makeViewModel(hops: [HopData],
                                bandwidth: [BandwidthSample] = [],
                                error: String? = nil) -> TracerouteViewModel {
        let vm = TracerouteViewModel()
        vm.hops = hops
        vm.bandwidthHistory = bandwidth
        vm.errorMessage = error
        // Pin visually-relevant settings to deterministic values
        vm.colorSchemeName = ColorTheme.thermal.rawValue
        vm.latencyThreshold = 100
        vm.historyMinutes = 3.0
        return vm
    }

    private func snapshotPanel(_ vm: TracerouteViewModel, named name: String,
                                file: StaticString = #file, testName: String = #function,
                                line: UInt = #line) {
        let view = DetailViewPanel(viewModel: vm)
            .fixedSize(horizontal: false, vertical: true)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame.size.width = panelWidth
        hostingView.layoutSubtreeIfNeeded()
        let size = CGSize(width: panelWidth, height: hostingView.fittingSize.height)
        hostingView.frame = CGRect(origin: .zero, size: size)

        assertSnapshot(of: hostingView, as: .image(perceptualPrecision: 0.98, size: size),
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
