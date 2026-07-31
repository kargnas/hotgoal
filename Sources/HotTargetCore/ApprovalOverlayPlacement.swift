import CoreGraphics
import Foundation

/// Geometry for the floating chip that guides the user through the System Settings
/// approval step. Free of AppKit so the coordinate flip and clamping stay testable.
public enum ApprovalOverlayPlacement {
    /// System Settings sidebar width, measured on macOS 15. The chip centers on the
    /// content pane rather than the whole window so it never sits under the sidebar.
    public static let sidebarWidth: CGFloat = 215
    /// Gap between the chip and the bottom edge of the Settings window.
    public static let windowGap: CGFloat = 8
    /// Fallback inset used when there is no room for the chip below the window.
    public static let bottomInset: CGFloat = 24
    /// Gap kept between the chip and the edge of the usable screen area.
    public static let screenMargin: CGFloat = 8

    /// `CGWindowListCopyWindowInfo` reports top-left-origin global coordinates while
    /// Cocoa windows are bottom-left-origin. Flip against the primary screen height.
    public static func cocoaRect(
        fromWindowBounds bounds: CGRect,
        primaryScreenHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: bounds.origin.x,
            y: primaryScreenHeight - bounds.origin.y - bounds.height,
            width: bounds.width,
            height: bounds.height
        )
    }

    /// Directly under the Settings window, centered on its content pane, clamped inside the
    /// visible screen area.
    ///
    /// ponytail: a fixed sidebar width instead of measuring the pane. Live Accessibility
    /// measurement is not available — the app holds no Accessibility grant. The chip sits
    /// *outside* the window rather than over the list because Login Items & Extensions
    /// scrolls and its sections shift with the number of login items, so every in-window
    /// position eventually covers the row the chip is pointing at. Upgrade path: re-measure
    /// `sidebarWidth` if System Settings changes its layout.
    public static func chipFrame(
        settingsFrame: CGRect,
        chipSize: CGSize,
        visibleFrame: CGRect
    ) -> CGRect {
        let paneLeft = settingsFrame.minX + sidebarWidth
        let paneWidth = max(chipSize.width, settingsFrame.width - sidebarWidth)
        let limit = visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
        let x = paneLeft + (paneWidth - chipSize.width) / 2
        let below = settingsFrame.minY - windowGap - chipSize.height
        let y = below >= limit.minY ? below : settingsFrame.minY + bottomInset
        return CGRect(
            x: min(max(x, limit.minX), max(limit.minX, limit.maxX - chipSize.width)),
            y: min(max(y, limit.minY), max(limit.minY, limit.maxY - chipSize.height)),
            width: chipSize.width,
            height: chipSize.height
        )
    }
}

/// Decides, once per poll, whether the chip should move, stay put, or disappear.
public struct ApprovalOverlayTracker: Sendable {
    public enum Step: Equatable, Sendable {
        /// Settings was first seen, or moved: re-anchor the chip to this frame.
        case reposition(CGRect)
        /// Nothing changed. Never snap the chip back on an unchanged frame, or it fights
        /// a user who dragged it aside.
        case hold
        /// The approval landed, or the Settings window is gone for good.
        case dismiss
    }

    /// Grace period before giving up on a Settings window that has never appeared:
    /// System Settings is slow to show up after the open-URL call.
    public static let startupGrace: TimeInterval = 4
    /// Grace period once Settings has been seen at least once. A closed window should
    /// take the chip down quickly.
    public static let missingGrace: TimeInterval = 2

    private var deadline: TimeInterval
    private var lastFrame: CGRect?

    public init(now: TimeInterval) {
        deadline = now + Self.startupGrace
    }

    public mutating func step(
        now: TimeInterval,
        isSatisfied: Bool,
        settingsFrame: CGRect?
    ) -> Step {
        if isSatisfied { return .dismiss }
        guard let settingsFrame else {
            return now >= deadline ? .dismiss : .hold
        }
        deadline = now + Self.missingGrace
        guard settingsFrame != lastFrame else { return .hold }
        lastFrame = settingsFrame
        return .reposition(settingsFrame)
    }
}
