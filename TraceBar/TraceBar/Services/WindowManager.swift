import AppKit

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    /// The settings window (discovered from NSApp.windows)
    private(set) var settingsWindow: NSWindow?
    /// The menubar panel (discovered from NSApp.windows)
    private(set) var panelWindow: NSWindow?

    private var observers: [NSObjectProtocol] = []

    init() {}

    /// Convenience initializer that also starts observing window notifications.
    /// Used by the shared singleton; tests use bare init() for isolation.
    static func startShared() {
        shared.setupObservers()
    }

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

    /// Reset all state (for testing). Also removes observers.
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
            guard let self, let window = notification.object as? NSWindow else { return }
            Task { @MainActor in
                self.classify(window)
            }
        })

        // When app becomes active again, ensure settings ordering
        observers.append(nc.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.reorderWindows()
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
