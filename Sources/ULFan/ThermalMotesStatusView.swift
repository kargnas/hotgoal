import AppKit
import QuartzCore
import HotTargetCore

@MainActor
final class ThermalMotesStatusView: NSView {
    private let contentLayer = CALayer()
    private let tubeLayer = CAShapeLayer()
    private let mercuryLayer = CAShapeLayer()
    private let bulbLayer = CAShapeLayer()
    private var moteLayers: [CAShapeLayer] = []
    private var temperature: Double?
    private var band: TemperatureBand?
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        setAccessibilityElement(false)
        configureThermometer()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.bounds = CGRect(x: 0, y: 0, width: 22, height: 22)
        contentLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateOutlineColor()
    }

    func update(temperature newTemperature: Double?, band newBand: TemperatureBand?) {
        let newReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let needsMoteRebuild = newBand != band || newReduceMotion != reduceMotion
        guard newTemperature != temperature || needsMoteRebuild else { return }
        temperature = newTemperature
        band = newBand
        reduceMotion = newReduceMotion
        updateTemperatureAppearance()
        if needsMoteRebuild {
            rebuildMotes()
        } else {
            updateMoteColors()
        }
    }

    private func configureThermometer() {
        layer?.addSublayer(contentLayer)

        tubeLayer.path = CGPath(
            roundedRect: CGRect(x: 5, y: 6, width: 5, height: 12.5),
            cornerWidth: 2.5,
            cornerHeight: 2.5,
            transform: nil
        )
        tubeLayer.fillColor = NSColor.clear.cgColor
        tubeLayer.lineWidth = 1.25
        contentLayer.addSublayer(tubeLayer)

        let mercuryPath = CGMutablePath()
        mercuryPath.move(to: CGPoint(x: 7.5, y: 7))
        mercuryPath.addLine(to: CGPoint(x: 7.5, y: 15.75))
        mercuryLayer.path = mercuryPath
        mercuryLayer.fillColor = NSColor.clear.cgColor
        mercuryLayer.lineCap = .round
        mercuryLayer.lineWidth = 3
        contentLayer.addSublayer(mercuryLayer)

        bulbLayer.path = CGPath(ellipseIn: CGRect(x: 3.5, y: 2.5, width: 8, height: 8), transform: nil)
        bulbLayer.lineWidth = 1.25
        contentLayer.addSublayer(bulbLayer)

        updateOutlineColor()
    }

    private func updateOutlineColor() {
        var color = NSColor.labelColor.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.cgColor
        }
        tubeLayer.strokeColor = color
        bulbLayer.strokeColor = color
    }

    private func updateTemperatureAppearance() {
        guard let temperature else { return }
        let color = temperatureColor(for: temperature)
        let mercuryTop = CGFloat(TemperaturePalette.mercuryTop(for: temperature))
        let mercuryPath = CGMutablePath()
        mercuryPath.move(to: CGPoint(x: 7.5, y: 7))
        mercuryPath.addLine(to: CGPoint(x: 7.5, y: mercuryTop))
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.45)
        mercuryLayer.path = mercuryPath
        mercuryLayer.strokeColor = color.cgColor
        bulbLayer.fillColor = color.cgColor
        CATransaction.commit()
    }

    private func updateMoteColors() {
        guard let temperature else { return }
        let color = temperatureColor(for: temperature).cgColor
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.45)
        moteLayers.forEach { $0.fillColor = color }
        CATransaction.commit()
    }

    private func rebuildMotes() {
        moteLayers.forEach { $0.removeFromSuperlayer() }
        moteLayers.removeAll()

        guard !reduceMotion, let band, let temperature else { return }
        let configuration = band.thermalMotes
        guard let duration = configuration.cycleDuration else { return }

        let color = temperatureColor(for: temperature)
        let xPositions: [CGFloat] = [2, 15, 1, 18]
        let repeatPeriod = configuration.count == 1 ? duration + 0.8 : duration
        let delayStep = configuration.count == 1 ? 0.45 : repeatPeriod / Double(configuration.emitterCount)
        for index in 0 ..< configuration.emitterCount {
            let mote = CAShapeLayer()
            mote.path = CGPath(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2), transform: nil)
            mote.fillColor = color.cgColor
            mote.position = CGPoint(x: xPositions[index], y: 4 + CGFloat(index % 2) * 2)
            mote.opacity = 0
            contentLayer.addSublayer(mote)
            mote.add(
                moteAnimation(
                    travelDuration: duration,
                    repeatPeriod: repeatPeriod,
                    delay: delayStep * Double(index)
                ),
                forKey: "thermalMote"
            )
            moteLayers.append(mote)
        }
    }

    private func temperatureColor(for celsius: Double) -> NSColor {
        let color = TemperaturePalette.color(for: celsius)
        return NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
    }

    private func moteAnimation(
        travelDuration: CFTimeInterval,
        repeatPeriod: CFTimeInterval,
        delay: CFTimeInterval
    ) -> CAAnimationGroup {
        let rise = CAKeyframeAnimation(keyPath: "transform.translation.y")
        rise.values = [0, 0, 9, 13]
        rise.keyTimes = [0, 0.08, 0.82, 1]
        rise.duration = travelDuration

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.12, 0.72, 1]
        fade.duration = travelDuration

        let group = CAAnimationGroup()
        group.animations = [rise, fade]
        group.beginTime = CACurrentMediaTime() + delay
        group.duration = repeatPeriod
        group.repeatCount = .infinity
        group.isRemovedOnCompletion = false
        group.timingFunction = CAMediaTimingFunction(name: .linear)
        return group
    }

    @objc private func accessibilityDisplayOptionsDidChange() {
        let newReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard newReduceMotion != reduceMotion else { return }
        reduceMotion = newReduceMotion
        rebuildMotes()
    }
}
