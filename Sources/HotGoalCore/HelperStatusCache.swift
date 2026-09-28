import Foundation

/// Holds the fan helper's registration status between refresh ticks.
///
/// `SMAppService.status` is a synchronous round-trip to backgroundtaskmanagementd, which
/// re-evaluates the app's code signature through trustd, syspolicyd, and smd on every call.
/// The 0.5 s refresh loop reads the status four times per tick; answered live, that was a
/// steady 8 queries a second, and whenever those daemons stopped caching the signature check
/// (right after a Sparkle update, on coming back online) it drove the system to load 140+ and
/// 20k log lines a minute until Hot Goal quit.
///
/// ponytail: a fixed lifetime instead of change notifications — ServiceManagement publishes
/// none. Approvals the user makes outside the chip and outside the menu land up to
/// `lifetime` late; call `invalidate()` wherever the user is actively changing the status.
public struct HelperStatusCache<Status> {
    public static var lifetime: TimeInterval { 30 }

    private var entry: (status: Status, queriedAt: TimeInterval)?

    public init() {}

    /// Returns the cached status, calling `query` only once the cached one has expired.
    public mutating func status(now: TimeInterval, query: () -> Status) -> Status {
        if let entry, now - entry.queriedAt < Self.lifetime { return entry.status }
        let status = query()
        entry = (status, now)
        return status
    }

    public mutating func invalidate() {
        entry = nil
    }
}
