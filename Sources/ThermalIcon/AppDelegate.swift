import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum DefaultsKey {
        static let displayMode = "displayMode"
        static let warmThreshold = "warmThreshold"
        static let hotThreshold = "hotThreshold"
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let temperatureItem = NSMenuItem(title: "Reading CPU temperature…", action: nil, keyEquivalent: "")
    private let iconModeItem = NSMenuItem(title: "Icon", action: #selector(selectIconMode), keyEquivalent: "")
    private let numberModeItem = NSMenuItem(title: "Number", action: #selector(selectNumberMode), keyEquivalent: "")
    private let reader: SMCReader?
    private var timer: Timer?
    private var temperature: Double?
    private var displayMode: DisplayMode
    private var thresholds: TemperatureThresholds
    private var warmItems: [NSMenuItem] = []
    private var hotItems: [NSMenuItem] = []

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
        configureStatusItem()
        configureMenu()
        refresh()

        let timer = Timer(timeInterval: 2, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        statusItem.autosaveName = "ThermalIconMenuBarItem"
        button.imageScaling = .scaleProportionallyDown
        button.setAccessibilityLabel("CPU temperature")
        statusItem.menu = menu
    }

    private func configureMenu() {
        menu.delegate = self
        menu.autoenablesItems = false
        temperatureItem.isEnabled = false
        menu.addItem(temperatureItem)
        menu.addItem(.separator())

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
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        guard let temperature else {
            temperatureItem.title = "CPU temperature unavailable"
            statusItem.length = displayMode == .icon ? NSStatusItem.squareLength : NSStatusItem.variableLength
            button.title = displayMode == .number ? "--°" : ""
            button.image = displayMode == .icon ? symbol(named: "exclamationmark.triangle") : nil
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
            button.image = symbol(named: band.symbolName)
            button.imagePosition = .imageOnly
        case .number:
            statusItem.length = NSStatusItem.variableLength
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
        thresholds = TemperatureThresholds(warm: thresholds.warm, hot: Double(sender.tag))
        UserDefaults.standard.set(thresholds.hot, forKey: DefaultsKey.hotThreshold)
        updateChecks()
        updateStatusItem()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
