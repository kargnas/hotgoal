/// Default target applied the first time the privileged helper becomes usable. Without it the
/// user approves the helper and lands back on a menu that still looks inert, with no fan
/// control running and nothing telling them the approval worked.
public enum FirstRunTarget {
    public static let celsius: Double = 60

    /// True only on the edge into an approved helper, never on the polls that follow.
    ///
    /// `previous` is nil on the very first poll of a launch: an app that starts with an
    /// already-approved helper must not treat that as a fresh approval and override whatever
    /// the user last chose.
    public static func approvalJustLanded(previous: Bool?, isEnabled: Bool) -> Bool {
        guard let previous else { return false }
        return !previous && isEnabled
    }

    /// Mirrors the guards on the fan-control command itself, so the pending flag is only
    /// cleared on a poll that actually dispatches. Fans are unknown for the first status
    /// round-trip after approval, and an existing control is one the user picked — leave it.
    public static func shouldApply(
        pending: Bool,
        fanCount: Int,
        existingControl: FanControl?,
        commandInFlight: Bool
    ) -> Bool {
        pending && fanCount > 0 && existingControl == nil && !commandInFlight
    }
}
