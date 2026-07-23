import ServiceManagement
import ThermalIconCore

enum FanHelperRegistrationState {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

@MainActor
final class FanHelperServiceManager {
    private let service = SMAppService.daemon(plistName: fanHelperPlistName)

    var state: FanHelperRegistrationState {
        switch service.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
