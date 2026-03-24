import Testing
import AppKit
import QuartzCore
@testable import TraceBar

@Suite(.serialized)
@MainActor
struct SettingsWindowTests {
    private func makeManager() -> WindowManager {
        WindowManager()
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = "Settings"
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.orderFront(nil)
        CATransaction.commit()
        CATransaction.flush()
        return window
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 200, y: 400, width: 300, height: 500),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.orderFront(nil)
        CATransaction.commit()
        CATransaction.flush()
        return panel
    }

    // MARK: - Settings survives app deactivation

    @Test func settingsSurvivesAppDeactivationViaEnsure() {
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

    @Test func reorderWindowsFixesWrongLevel() {
        let manager = makeManager()
        let settings = makeSettingsWindow()
        let panel = makePanel()
        manager.register(settingsWindow: settings)
        manager.register(panelWindow: panel)

        // Put settings at wrong level (simulates what happens after app deactivation)
        settings.level = .normal

        // reorderWindows corrects it
        manager.reorderWindows()
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
