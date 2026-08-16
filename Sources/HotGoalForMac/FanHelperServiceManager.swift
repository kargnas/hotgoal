import ServiceManagement
import HotGoalForMacCore

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

    /// The single funnel to System Settings, so no caller can open the pane without the
    /// guidance chip that tells the user what to do once they get there.
    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
        let service = service
        HelperApprovalOverlay.shared.show { service.status == .enabled }
    }
}
