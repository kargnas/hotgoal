import AppKit
import Foundation
import ThermalIconCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum DefaultsKey {
        static let displayMode = "displayMode"
        static let warmThreshold = "warmThreshold"
        static let hotThreshold = "hotThreshold"
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusView = ThermalMotesStatusView()
    private let menu = NSMenu()
    private let temperatureItem = NSMenuItem(title: "Reading CPU temperature…", action: nil, keyEquivalent: "")
    private let fanStatusItem = NSMenuItem(title: "Reading fans…", action: nil, keyEquivalent: "")
    private let fanStatusView = FanStatusMenuView()
    private let iconModeItem = NSMenuItem(title: "Icon", action: #selector(selectIconMode), keyEquivalent: "")
    private let numberModeItem = NSMenuItem(title: "Icon + Number", action: #selector(selectNumberMode), keyEquivalent: "")
    private let helperActionItem = NSMenuItem(title: "Enable Fan Control…", action: #selector(handleHelperAction), keyEquivalent: "")
    private let reader: SMCReader?
    private let helperManager = FanHelperServiceManager()
    private let helperClient = FanHelperClient()
    private var temperatureTimer: Timer?
    private var fanTimer: Timer?
    private var temperature: Double?
    private var fans: [FanSnapshot] = []
    private var hasControllerConflict = false
    private var displayMode: DisplayMode
    private var thresholds: TemperatureThresholds
    private var warmItems: [NSMenuItem] = []
    private var hotItems: [NSMenuItem] = []
    private var fanModeItems: [FanControlMode: NSMenuItem] = [:]
    private var reportedFanMode: FanControlMode?
    private var fanStatusError: String?
    private var fanStatusRequestInFlight = false
    private var fanCommandInFlight = false
    private var fanConnectionGeneration = 0

    override init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            DefaultsKey.displayMode: DisplayMode.icon.rawValue,
            DefaultsKey.warmThreshold: TemperatureThresholds.defaultWarm,
            DefaultsKey.hotThreshold: TemperatureThresholds.defaultHot,
        ])

        displayMode = DisplayMode(rawValue: defaults.string(forKey: DefaultsKey.displayMode) ?? "") ?? .icon
        thresholds = TemperatureThresholds(
            warm: defaults.double(forKey: DefaultsKey.warmThreshold),
            hot: defaults.double(forKey: DefaultsKey.hotThreshold)
        )
        reader = try? SMCReader()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        helperClient.connectionLostHandler = { [weak self] in
            guard let self else { return }
            fanConnectionGeneration += 1
            reportedFanMode = nil
            fans = []
            fanStatusError = "Fan helper connection lost"
            fanStatusRequestInFlight = false
            fanCommandInFlight = false
            updateFanItems()
        }
        configureStatusItem()
        configureMenu()
        refresh()

        let temperatureTimer = Timer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(refreshTemperature),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(temperatureTimer, forMode: .common)
        self.temperatureTimer = temperatureTimer

        let fanTimer = Timer(timeInterval: 0.2, target: self, selector: #selector(refreshFans), userInfo: nil, repeats: true)
        RunLoop.main.add(fanTimer, forMode: .common)
        self.fanTimer = fanTimer
    }

    func applicationWillTerminate(_ notification: Notification) {
        temperatureTimer?.invalidate()
        fanTimer?.invalidate()
        helperClient.disconnect()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        statusItem.autosaveName = "ThermalIconMenuBarItem"
        button.imageScaling = .scaleProportionallyDown
        button.setAccessibilityLabel("CPU temperature")
        statusView.frame = button.bounds
        statusView.autoresizingMask = [.width, .height]
        button.addSubview(statusView)
        statusItem.menu = menu
    }

    private func configureMenu() {
        menu.delegate = self
        menu.autoenablesItems = false
        temperatureItem.isEnabled = false
        fanStatusItem.isEnabled = false
        menu.addItem(temperatureItem)
        menu.addItem(fanStatusItem)
        menu.addItem(.separator())

        menu.addItem(makeFanControlMenu())

        let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu()
        iconModeItem.target = self
        numberModeItem.target = self
        displayMenu.addItem(iconModeItem)
        displayMenu.addItem(numberModeItem)
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)

        let thresholdItem = NSMenuItem(title: "Thresholds", action: nil, keyEquivalent: "")
        let thresholdMenu = NSMenu()
        thresholdMenu.addItem(makeWarmThresholdMenu())
        thresholdMenu.addItem(makeHotThresholdMenu())
        thresholdItem.submenu = thresholdMenu
        menu.addItem(thresholdItem)

        menu.addItem(.separator())
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "Quit Thermal Icon", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        updateChecks()
    }

    private func makeFanControlMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Fan Control", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for mode in FanControlMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectFanMode), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            submenu.addItem(item)
            fanModeItems[mode] = item
        }

        submenu.addItem(.separator())
        helperActionItem.target = self
        submenu.addItem(helperActionItem)
        parent.submenu = submenu
        return parent
    }

    private func makeWarmThresholdMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Warm", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        warmItems = TemperatureThresholds.warmChoices.map { value in
            let item = NSMenuItem(title: "\(Int(value)) °C", action: #selector(selectWarmThreshold), keyEquivalent: "")
            item.target = self
            item.tag = Int(value)
            submenu.addItem(item)
            return item
        }
        parent.submenu = submenu
        return parent
    }

    private func makeHotThresholdMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Hot", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        hotItems = TemperatureThresholds.hotChoices.map { value in
            let item = NSMenuItem(title: "\(Int(value)) °C", action: #selector(selectHotThreshold), keyEquivalent: "")
            item.target = self
            item.tag = Int(value)
            submenu.addItem(item)
            return item
        }
        parent.submenu = submenu
        return parent
    }

    @objc private func refresh() {
        refreshTemperature()
        refreshFans()
    }

    @objc private func refreshTemperature() {
        temperature = reader?.cpuAverageTemperature()
        updateStatusItem()
    }

    @objc private func refreshFans() {
        let controllerConflict = !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.crystalidea.macsfancontrol"
        ).isEmpty
        if controllerConflict && !hasControllerConflict {
            fanConnectionGeneration += 1
            fanCommandInFlight = false
            fanStatusRequestInFlight = false
            helperClient.disconnect()
            reportedFanMode = nil
            fanStatusError = nil
        }
        hasControllerConflict = controllerConflict

        if hasControllerConflict {
            updateFanItems()
            return
        }

        if helperManager.state == .enabled {
            refreshFanControlStatus()
            return
        }

        if helperClient.isConnected {
            fanConnectionGeneration += 1
            fanStatusRequestInFlight = false
            fanCommandInFlight = false
            helperClient.disconnect()
        }
        reportedFanMode = nil
        do {
            fans = try reader?.fanSnapshots() ?? []
            fanStatusError = nil
        } catch {
            fans = []
            fanStatusError = error.localizedDescription
        }
        updateFanItems()
    }

    private func refreshFanControlStatus() {
        guard !fanStatusRequestInFlight else {
            updateFanItems()
            return
        }
        fanStatusRequestInFlight = true
        let generation = fanConnectionGeneration
        helperClient.getStatus { [weak self] result in
            guard let self, generation == fanConnectionGeneration else { return }
            fanStatusRequestInFlight = false
            guard !hasControllerConflict, helperManager.state == .enabled else { return }
            switch result {
            case let .success(status):
                fans = status.fans
                reportedFanMode = status.mode
                fanStatusError = nil
            case let .failure(error):
                fans = []
                reportedFanMode = nil
                fanStatusError = error.localizedDescription
            }
            updateFanItems()
        }
    }

    private func updateFanItems() {
        if hasControllerConflict {
            fanStatusItem.view = nil
            fanStatusItem.title = "Fans: controlled by Macs Fan Control"
            fanStatusItem.toolTip = nil
        } else if let fanStatusError {
            fanStatusItem.view = nil
            fanStatusItem.title = "Fans: unavailable"
            fanStatusItem.toolTip = fanStatusError
        } else if fans.isEmpty {
            fanStatusItem.view = nil
            fanStatusItem.title = "Fans: unavailable"
            fanStatusItem.toolTip = nil
        } else if fans.count == 2 {
            let labels = fans.map { "Fan \($0.index + 1) \($0.currentRPM) RPM" }
            fanStatusItem.title = labels.joined(separator: ", ")
            fanStatusView.update(left: labels[0], right: labels[1])
            if fanStatusItem.view !== fanStatusView {
                fanStatusItem.view = fanStatusView
            }
            fanStatusItem.toolTip = nil
        } else {
            fanStatusItem.view = nil
            let speeds = fans.map { "Fan \($0.index + 1) \($0.currentRPM) RPM" }.joined(separator: " · ")
            fanStatusItem.title = speeds
            fanStatusItem.toolTip = nil
        }

        let helperEnabled = helperManager.state == .enabled
        let controlsEnabled = helperEnabled && !fans.isEmpty && !hasControllerConflict && !fanCommandInFlight
        hotItems.forEach { $0.isEnabled = !fanCommandInFlight }
        for (mode, item) in fanModeItems {
            item.isEnabled = controlsEnabled
            item.state = reportedFanMode == mode ? .on : .off
        }

        if hasControllerConflict {
            helperActionItem.title = "Quit Macs Fan Control First"
            helperActionItem.isEnabled = false
            return
        }

        switch helperManager.state {
        case .notRegistered:
            helperActionItem.title = "Enable Fan Control…"
            helperActionItem.isEnabled = true
        case .requiresApproval:
            helperActionItem.title = "Approve in System Settings…"
            helperActionItem.isEnabled = true
        case .enabled:
            helperActionItem.title = "Fan Helper Enabled…"
            helperActionItem.isEnabled = true
        case .notFound:
            helperActionItem.title = "Fan Helper Missing"
            helperActionItem.isEnabled = false
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        guard let temperature else {
            temperatureItem.title = "CPU temperature unavailable"
            statusItem.length = displayMode == .icon ? NSStatusItem.squareLength : NSStatusItem.variableLength
            statusView.update(temperature: nil, band: nil)
            statusView.isHidden = true
            button.title = displayMode == .number ? "--°" : ""
            button.image = symbol(named: "exclamationmark.triangle")
            button.imagePosition = displayMode == .icon ? .imageOnly : .imageLeading
            if displayMode == .number { trimCombinedStatusItemWidth(for: button) }
            button.toolTip = "CPU temperature unavailable"
            button.setAccessibilityValue("Unavailable")
            return
        }

        let band = TemperatureBand.classify(temperature, thresholds: thresholds)
        let precise = String(format: "%.1f °C", temperature)
        temperatureItem.title = "CPU: \(precise) · \(band.label)"
        button.toolTip = "CPU \(precise) · \(band.label)"
        button.setAccessibilityValue("\(precise), \(band.label)")

        switch displayMode {
        case .icon:
            statusItem.length = NSStatusItem.squareLength
            button.title = ""
            button.image = nil
            button.imagePosition = .noImage
            showStatusView(in: button, combined: false)
            statusView.update(temperature: temperature, band: band)
        case .number:
            statusItem.length = NSStatusItem.variableLength
            button.image = nil
            // A thin space opens the icon gap without restoring the removed trailing padding.
            button.title = "   \u{2009}\u{2009}" + String(format: "%.0f°", temperature)
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.imagePosition = .noImage
            trimCombinedStatusItemWidth(for: button)
            showStatusView(in: button, combined: true)
            statusView.update(temperature: temperature, band: band)
        }
    }

    private func showStatusView(in button: NSStatusBarButton, combined: Bool) {
        statusView.isHidden = false
        if combined {
            statusView.autoresizingMask = [.height]
            statusView.frame = CGRect(x: 0, y: 0, width: 22, height: button.bounds.height)
        } else {
            statusView.autoresizingMask = [.width, .height]
            statusView.frame = button.bounds
        }
    }

    private func trimCombinedStatusItemWidth(for button: NSStatusBarButton) {
        // AppKit centers the title: trim 4 pt and move the icon 2 pt left so only trailing space loses 2 pt.
        statusItem.length = max(NSStatusItem.squareLength, button.intrinsicContentSize.width - 4)
    }

    private func symbol(named name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "CPU temperature")?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    private func setDisplayMode(_ mode: DisplayMode) {
        displayMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKey.displayMode)
        updateChecks()
        updateStatusItem()
    }

    private func updateChecks() {
        iconModeItem.state = displayMode == .icon ? .on : .off
        numberModeItem.state = displayMode == .number ? .on : .off
        warmItems.forEach { $0.state = $0.tag == Int(thresholds.warm) ? .on : .off }
        hotItems.forEach { $0.state = $0.tag == Int(thresholds.hot) ? .on : .off }
    }

    @objc private func selectIconMode() {
        setDisplayMode(.icon)
    }

    @objc private func selectNumberMode() {
        setDisplayMode(.number)
    }

    @objc private func selectWarmThreshold(_ sender: NSMenuItem) {
        thresholds = TemperatureThresholds(warm: Double(sender.tag), hot: thresholds.hot)
        UserDefaults.standard.set(thresholds.warm, forKey: DefaultsKey.warmThreshold)
        updateChecks()
        updateStatusItem()
    }

    @objc private func selectHotThreshold(_ sender: NSMenuItem) {
        guard !fanCommandInFlight else { return }
        let modeToRefresh = reportedFanMode
        thresholds = TemperatureThresholds(warm: thresholds.warm, hot: Double(sender.tag))
        UserDefaults.standard.set(thresholds.hot, forKey: DefaultsKey.hotThreshold)
        updateChecks()
        updateStatusItem()
        if let modeToRefresh, modeToRefresh == .quiet || modeToRefresh == .standard {
            applyFanMode(modeToRefresh)
        }
    }

    @objc private func selectFanMode(_ sender: NSMenuItem) {
        guard !hasControllerConflict else { return }
        guard let rawMode = sender.representedObject as? String,
              let mode = FanControlMode(rawValue: rawMode) else { return }
        applyFanMode(mode)
    }

    private func applyFanMode(_ mode: FanControlMode) {
        guard !hasControllerConflict,
              helperManager.state == .enabled,
              !fans.isEmpty,
              !fanCommandInFlight else { return }
        fanCommandInFlight = true
        let generation = fanConnectionGeneration
        updateFanItems()
        helperClient.setMode(mode, hotThreshold: thresholds.hot) { [weak self] result in
            self?.finishFanCommand(result, generation: generation)
        }
    }

    @objc private func handleHelperAction() {
        switch helperManager.state {
        case .notRegistered:
            do {
                try helperManager.register()
                if helperManager.state == .requiresApproval {
                    helperManager.openApprovalSettings()
                }
            } catch {
                if helperManager.state == .requiresApproval {
                    helperManager.openApprovalSettings()
                } else {
                    showError(error.localizedDescription)
                }
            }
        case .requiresApproval:
            helperManager.openApprovalSettings()
        case .enabled:
            helperManager.openApprovalSettings()
        case .notFound:
            break
        }
        updateFanItems()
        refreshFans()
    }

    private func finishFanCommand(
        _ result: Result<Void, Error>,
        generation: Int
    ) {
        guard generation == fanConnectionGeneration else { return }
        fanCommandInFlight = false
        switch result {
        case .success:
            refreshFans()
        case let .failure(error):
            refreshFans()
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Fan Control Failed"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@MainActor
private final class FanStatusMenuView: NSView {
    private let leftLabel = NSTextField(labelWithString: "")
    private let rightLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 260, height: 30))
        autoresizingMask = [.width]

        for label in [leftLabel, rightLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .menuFont(ofSize: 0)
            label.textColor = .disabledControlTextColor
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
        rightLabel.alignment = .right

        NSLayoutConstraint.activate([
            leftLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            leftLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leftLabel.trailingAnchor, constant: 16),
            rightLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            rightLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(left: String, right: String) {
        leftLabel.stringValue = left
        rightLabel.stringValue = right
    }
}
