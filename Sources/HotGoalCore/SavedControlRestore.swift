/// Reapplies the user's last fan selection when the helper reports no active controller.
/// The helper deliberately forgets its control whenever the app disconnects or the helper
/// restarts, so without this every relaunch silently lands back on macOS automatic control
/// while the menu shows the last selection as unchecked.
public enum SavedControlRestore {
    /// `alreadyAttempted` is the storm guard: one restore per observed drop. The caller
    /// rearms it when the helper reports a non-nil control again, so a failed restore
    /// leaves the menu honestly on System Default instead of retrying every poll.
    public static func controlToApply(
        saved: FanControl?,
        reported: FanControl?,
        fanCount: Int,
        commandInFlight: Bool,
        alreadyAttempted: Bool
    ) -> FanControl? {
        guard !alreadyAttempted,
              !commandInFlight,
              reported == nil,
              // Fans are unknown for the first status round-trip; wait, do not drop the restore.
              fanCount > 0,
              let saved,
              // systemDefault is exactly what a control-less helper already does; nothing to send.
              saved.requiresContinuousControl
        else { return nil }
        return saved
    }
}
