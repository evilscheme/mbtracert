import Testing
import AppKit
@testable import TraceBar

@Suite(.serialized)
@MainActor
struct WindowManagerTests {
    private func makeManager() -> WindowManager {
        WindowManager()
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
