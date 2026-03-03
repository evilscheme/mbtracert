import Foundation
import ServiceManagement

final class HelperManager {
    static let shared = HelperManager()

    private let service = SMAppService.daemon(
        plistName: "org.evilscheme.MenubarTracert.TracertHelper.plist"
    )

    var status: SMAppService.Status { service.status }

    var isInstalled: Bool {
        service.status == .enabled
    }

    func registerIfNeeded() throws {
        let currentStatus = service.status
        NSLog("[HelperManager] Current status: %d (%@)", currentStatus.rawValue, "\(currentStatus)")

        switch currentStatus {
        case .notRegistered, .notFound:
            NSLog("[HelperManager] Registering daemon...")
            try service.register()
            NSLog("[HelperManager] Registration succeeded, new status: %d", service.status.rawValue)
        case .enabled:
            NSLog("[HelperManager] Daemon is enabled and should be loaded")
        case .requiresApproval:
            NSLog("[HelperManager] Requires approval — opening System Settings")
            SMAppService.openSystemSettingsLoginItems()
        @unknown default:
            NSLog("[HelperManager] Unknown status: %d", currentStatus.rawValue)
        }
    }

    func unregister() throws {
        try service.unregister()
    }
}
