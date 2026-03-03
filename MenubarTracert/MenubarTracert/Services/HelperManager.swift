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
        switch service.status {
        case .notRegistered, .notFound:
            try service.register()
        case .enabled:
            break
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        @unknown default:
            break
        }
    }

    func unregister() throws {
        try service.unregister()
    }
}
