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
    private let iconModeItem = NSMenuItem(title: "Icon", action: #selector(selectIconMode), keyEquivalent: "")
    private let numberModeItem = NSMenuItem(title: "Number", action: #selector(selectNumberMode), keyEquivalent: "")
    private let helperActionItem = NSMenuItem(title: "Enable Fan Control…", action: #selector(handleHelperAction), keyEquivalent: "")
    private let reader: SMCReader?
    private let helperManager = FanHelperServiceManager()
    private let helperClient = FanHelperClient()
    private var timer: Timer?
    private var temperature: Double?
    private var fans: [FanSnapshot] = []
    private var hasControllerConflict = false
    private var displayMode: DisplayMode
    private var thresholds: TemperatureThresholds
    private var warmItems: [NSMenuItem] = []
    private var hotItems: [NSMenuItem] = []
    private var fanModeItems: [FanControlMode: NSMenuItem] = [:]
    private var selectedFanMode: FanControlMode? = .standard
    private var fanCommandInFlight = false
    private var fanCommandGeneration = 0
    private var startupStandardAttempted = false

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
            fanCommandGeneration += 1
            selectedFanMode = nil
            fanCommandInFlight = false
            startupStandardAttempted = false
            updateFanItems()
        }
        configureStatusItem()
        configureMenu()
        refresh()

        let timer = Timer(timeInterval: 0.2, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
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
        temperature = reader?.cpuAverageTemperature()
        if let reader {
            fans = (try? reader.fanSnapshots()) ?? []
        }
        let controllerConflict = !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.crystalidea.macsfancontrol"
        ).isEmpty
        if controllerConflict && !hasControllerConflict {
            fanCommandGeneration += 1
            fanCommandInFlight = false
            helperClient.disconnect()
            selectedFanMode = nil
            startupStandardAttempted = true
        } else if !controllerConflict && hasControllerConflict {
            startupStandardAttempted = false
        }
        hasControllerConflict = controllerConflict
        updateStatusItem()
        updateFanItems()
        applyStartupStandardIfReady()
    }

    private func updateFanItems() {
        if hasControllerConflict {
            fanStatusItem.title = "Fans: controlled by Macs Fan Control"
        } else if fans.isEmpty {
            fanStatusItem.title = "Fans: unavailable"
        } else {
            let speeds = fans.map { "Fan \($0.index + 1) \($0.currentRPM) RPM" }.joined(separator: " · ")
            fanStatusItem.title = speeds
        }

        let helperEnabled = helperManager.state == .enabled
        let controlsEnabled = helperEnabled && !fans.isEmpty && !hasControllerConflict && !fanCommandInFlight
        hotItems.forEach { $0.isEnabled = !fanCommandInFlight }
        for (mode, item) in fanModeItems {
            item.isEnabled = controlsEnabled
            item.state = selectedFanMode == mode ? .on : .off
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
            statusView.update(band: nil)
            statusView.isHidden = true
            button.title = displayMode == .number ? "--°" : ""
            button.image = displayMode == .icon ? symbol(named: "exclamationmark.triangle") : nil
            button.imagePosition = displayMode == .icon ? .imageOnly : .noImage
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
            statusView.isHidden = false
            statusView.update(band: band)
        case .number:
            statusItem.length = NSStatusItem.variableLength
            statusView.update(band: nil)
            statusView.isHidden = true
            button.image = nil
            button.title = String(format: "%.0f°", temperature)
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.imagePosition = .noImage
        }
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
        let modeToRefresh = selectedFanMode
        thresholds = TemperatureThresholds(warm: thresholds.warm, hot: Double(sender.tag))
        UserDefaults.standard.set(thresholds.hot, forKey: DefaultsKey.hotThreshold)
        updateChecks()
        updateStatusItem()
        if let modeToRefresh, modeToRefresh != .ultra { applyFanMode(modeToRefresh) }
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
        selectedFanMode = mode
        fanCommandGeneration += 1
        let generation = fanCommandGeneration
        fanStatusItem.title = "Applying \(mode.title)…"
        updateFanItems()
        helperClient.setMode(mode, thresholds: thresholds) { [weak self] result in
            self?.finishFanCommand(result, mode: mode, generation: generation)
        }
    }

    private func applyStartupStandardIfReady() {
        guard !startupStandardAttempted,
              helperManager.state == .enabled,
              !fans.isEmpty,
              !hasControllerConflict else { return }
        startupStandardAttempted = true
        applyFanMode(.standard)
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
    }

    private func finishFanCommand(
        _ result: Result<Void, Error>,
        mode: FanControlMode,
        generation: Int
    ) {
        guard generation == fanCommandGeneration else { return }
        fanCommandGeneration += 1
        fanCommandInFlight = false
        switch result {
        case .success:
            selectedFanMode = mode
            refresh()
        case let .failure(error):
            selectedFanMode = nil
            refresh()
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
