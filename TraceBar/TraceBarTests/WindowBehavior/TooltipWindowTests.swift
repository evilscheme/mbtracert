import Testing
import AppKit
import QuartzCore
@testable import TraceBar

@Suite(.serialized)
@MainActor
struct TooltipWindowTests {
    private func makeParentPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.orderFront(nil)
        CATransaction.commit()
        CATransaction.flush()
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

        #expect(parent.childWindows?.isEmpty == false)

        // Clean up: detach tooltip before parent goes out of scope
        tooltip.resetForTesting()
        parent.orderOut(nil)
    }

    @Test func tooltipHidesOnRequest() {
        let tooltip = TooltipWindowManager.shared
        tooltip.resetForTesting()

        let parent = makeParentPanel()
        let point = NSPoint(x: 200, y: 200)

        tooltip.show(content: testContent, colorScheme: .lagoon,
                     latencyThreshold: 100, at: point, parentWindow: parent)

        let hadChildren = parent.childWindows?.isEmpty == false
        #expect(hadChildren)

        tooltip.hide()

        // After hide, tooltip child window is removed
        #expect(parent.childWindows?.isEmpty ?? true)

        // Clean up
        tooltip.resetForTesting()
        parent.orderOut(nil)
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

        // Clean up
        parent.orderOut(nil)
    }
}
