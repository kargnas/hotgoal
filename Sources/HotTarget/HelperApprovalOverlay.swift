import AppKit
import HotTargetCore

/// Floating chip that rides inside the System Settings window and points at the row the
/// user has to switch on.
///
/// Hot Target is a menu-bar accessory: the moment System Settings opens, the app has no
/// window left to explain itself in, and nothing in the pane says a fan helper is waiting
/// for approval. The chip is the only place that instruction can live.
@MainActor
final class HelperApprovalOverlay {
    static let shared = HelperApprovalOverlay()

    private static let settingsBundleIdentifier = "com.apple.systempreferences"
    /// How long the "it worked" chip stays up before getting out of the way.
    private static let confirmationDuration: TimeInterval = 6

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Hot Target"
    }

    private var panel: NSPanel?
    private var timer: Timer?
    private var tracker: ApprovalOverlayTracker?
    private var isSatisfied: @MainActor () -> Bool = { true }

    private init() {}

    /// - Parameter isSatisfied: read live each poll; the chip closes as soon as it is true.
    func show(isSatisfied: @escaping @MainActor () -> Bool) {
        guard !isSatisfied() else { return }
        self.isSatisfied = isSatisfied

        let appName = Self.appName
        present(ApprovalChipView(
            symbol: "arrow.up",
            bounces: true,
            headline: "Switch on “\(appName)”",
            // Imperative and spatial. The pane scrolls, so name the section instead of
            // relying on "above" alone.
            body: "Find it under “Allow in the Background” and turn the switch on to let fan control run.",
            accessibilityLabel: "\(appName) needs approval in Login Items & Extensions"
        ))

        tracker = ApprovalOverlayTracker(now: ProcessInfo.processInfo.systemUptime)
        schedule(selector: #selector(tick), after: 0.5, repeats: true)
    }

    /// Confirms the grant in the same spot the instruction was, because that is where the user
    /// is still looking. Skipped when Settings is already gone — the status menu covers that
    /// case, and a chip with nothing to anchor to would land in a screen corner.
    func showConfirmation(headline: String, body: String) {
        guard Self.settingsWindowFrame() != nil else {
            close()
            return
        }
        present(ApprovalChipView(
            symbol: "checkmark.circle.fill",
            bounces: false,
            headline: headline,
            body: body,
            accessibilityLabel: "\(headline). \(body)"
        ))
        tracker = nil
        schedule(selector: #selector(closeTimerFired), after: Self.confirmationDuration, repeats: false)
    }

    func close() {
        timer?.invalidate()
        timer = nil
        tracker = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// A fresh panel per state, so no stale content or tracker can leak between them.
    private func present(_ content: ApprovalChipView) {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)

        content.closeAction = { [weak self] in self?.close() }
        let panel = makePanel(content: content)
        self.panel = panel
        if let frame = Self.settingsWindowFrame() {
            reposition(panel, settingsFrame: frame)
        }
        // orderFrontRegardless, not makeKeyAndOrderFront: showing the chip must not pull
        // focus away from System Settings.
        panel.orderFrontRegardless()
    }

    private func schedule(selector: Selector, after interval: TimeInterval, repeats: Bool) {
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: selector,
            userInfo: nil,
            repeats: repeats
        )
        // .common mode so the chip keeps tracking while menus or drags are up.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func closeTimerFired() {
        close()
    }

    @objc private func tick() {
        guard var tracker, let panel else { return }
        let step = tracker.step(
            now: ProcessInfo.processInfo.systemUptime,
            isSatisfied: isSatisfied(),
            settingsFrame: Self.settingsWindowFrame()
        )
        self.tracker = tracker
        switch step {
        case .dismiss:
            close()
        case .hold:
            break
        case let .reposition(frame):
            reposition(panel, settingsFrame: frame)
        }
    }

    private func reposition(_ panel: NSPanel, settingsFrame: CGRect) {
        panel.setFrame(
            ApprovalOverlayPlacement.chipFrame(
                settingsFrame: settingsFrame,
                chipSize: panel.frame.size,
                visibleFrame: Self.visibleFrame(mostlyContaining: settingsFrame)
            ),
            display: true
        )
    }

    private func makePanel(content: ApprovalChipView) -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: ApprovalChipView.chipSize),
            // nonactivatingPanel: dragging or clicking the chip must not steal focus from
            // System Settings, or the pane loses its scroll position.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = content
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        // NSPanel hides itself when the owning app deactivates, and the user is by
        // definition inside System Settings whenever this chip matters.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    /// Window bounds and owner PID are permission-free; only window *titles* sit behind
    /// Screen Recording. Match on PID because the owner name is localized.
    private static func settingsWindowFrame() -> CGRect? {
        guard let settings = NSRunningApplication
            .runningApplications(withBundleIdentifier: settingsBundleIdentifier).first,
            let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else { return nil }

        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let frames = list.compactMap { info -> CGRect? in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid == settings.processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            return ApprovalOverlayPlacement.cocoaRect(
                fromWindowBounds: rect,
                primaryScreenHeight: primaryScreenHeight
            )
        }
        // Settings can own several layer-0 windows; the main one is the largest.
        return frames.max { area($0) < area($1) }
    }

    private static func visibleFrame(mostlyContaining frame: CGRect) -> CGRect {
        let screen = NSScreen.screens.max { area($0.frame.intersection(frame)) < area($1.frame.intersection(frame)) }
        return (screen ?? NSScreen.main)?.visibleFrame ?? frame
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}

@MainActor
private final class ApprovalChipView: NSView {
    static let chipSize = CGSize(width: 292, height: 118)
    private static let arrowHeight: CGFloat = 18

    var closeAction: (() -> Void)?

    private let arrow = NSImageView()
    private let card = NSVisualEffectView()
    private let bounces: Bool

    init(symbol: String, bounces: Bool, headline: String, body: String, accessibilityLabel: String) {
        self.bounces = bounces
        super.init(frame: CGRect(origin: .zero, size: Self.chipSize))
        wantsLayer = true

        arrow.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .bold))
        arrow.contentTintColor = .controlAccentColor
        arrow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(arrow)

        card.material = .popover
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.cornerCurve = .continuous
        card.layer?.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(icon)

        let title = NSTextField(labelWithString: headline)
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

        let detail = NSTextField(wrappingLabelWithString: body)
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 3

        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        text.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(text)

        let close = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Dismiss")!,
            target: self,
            action: #selector(dismiss)
        )
        close.isBordered = false
        close.contentTintColor = .tertiaryLabelColor
        close.setAccessibilityLabel("Dismiss")
        close.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(close)

        NSLayoutConstraint.activate([
            arrow.topAnchor.constraint(equalTo: topAnchor),
            arrow.centerXAnchor.constraint(equalTo: centerXAnchor),
            arrow.heightAnchor.constraint(equalToConstant: Self.arrowHeight),

            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.topAnchor.constraint(equalTo: arrow.bottomAnchor, constant: 2),

            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),

            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            text.centerYAnchor.constraint(equalTo: card.centerYAnchor),

            close.topAnchor.constraint(equalTo: card.topAnchor, constant: 4),
            close.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -4),
        ])

        setAccessibilityRole(.group)
        setAccessibilityLabel(accessibilityLabel)
        updateBorderColor()
        startBounce()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorderColor()
    }

    private func updateBorderColor() {
        card.layer?.borderColor = NSColor.separatorColor.cgColor
    }

    private func startBounce() {
        guard bounces, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        arrow.wantsLayer = true
        // AppKit layers are bottom-left-origin, so a positive translation nudges the arrow
        // toward the list it points at.
        let bounce = CABasicAnimation(keyPath: "transform.translation.y")
        bounce.fromValue = 0
        bounce.toValue = 4
        bounce.duration = 0.7
        bounce.autoreverses = true
        bounce.repeatCount = .greatestFiniteMagnitude
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        arrow.layer?.add(bounce, forKey: "bounce")
    }

    @objc private func dismiss() {
        closeAction?()
    }
}
