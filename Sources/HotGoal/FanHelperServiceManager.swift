import Foundation
import ServiceManagement
import HotGoalCore

enum FanHelperRegistrationState {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

@MainActor
final class FanHelperServiceManager {
    private let service = SMAppService.daemon(plistName: fanHelperPlistName)
    private var cache = HelperStatusCache<FanHelperRegistrationState>()

    /// Cached, because the refresh loop reads this several times per tick and every live
    /// `SMAppService.status` call costs a code-signature check in system daemons.
    var state: FanHelperRegistrationState {
        cache.status(now: ProcessInfo.processInfo.systemUptime) {
            switch service.status {
            case .notRegistered: .notRegistered
            case .enabled: .enabled
            case .requiresApproval: .requiresApproval
            case .notFound: .notFound
            @unknown default: .notFound
            }
        }
    }

    /// Makes the next `state` read ask SMAppService. Only for moments the user is actively
    /// looking at or changing the status, never from the refresh loop.
    func invalidateState() {
        cache.invalidate()
    }

    func register() throws {
        // Callers read `state` right after this, on success and failure alike.
        defer { cache.invalidate() }
        try service.register()
    }

    /// The single funnel to System Settings, so no caller can open the pane without the
    /// guidance chip that tells the user what to do once they get there.
    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
        // Reads live while the chip is up and refreshes the cache, so the refresh loop sees
        // the approval on its next tick. Strong capture: `--show-approval-chip` drops its
        // manager right after this call.
        HelperApprovalOverlay.shared.show {
            self.invalidateState()
            return self.state == .enabled
        }
    }
}
