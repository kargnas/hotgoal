import AppKit
import QuartzCore
import ThermalIconCore

@MainActor
final class ThermalMotesStatusView: NSView {
    private static let coolColor = NSColor(srgbRed: 0x38 / 255, green: 0xBD / 255, blue: 0xF8 / 255, alpha: 1)
    private static let warmColor = NSColor(srgbRed: 0xFF / 255, green: 0xB3 / 255, blue: 0x40 / 255, alpha: 1)
    private static let hotColor = NSColor(srgbRed: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)

    private let contentLayer = CALayer()
    private let tubeLayer = CAShapeLayer()
    private let mercuryLayer = CAShapeLayer()
    private let bulbLayer = CAShapeLayer()
    private var moteLayers: [CAShapeLayer] = []
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

    func update(band newBand: TemperatureBand?) {
        let newReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard newBand != band || newReduceMotion != reduceMotion else { return }
        band = newBand
        reduceMotion = newReduceMotion
        updateTemperatureAppearance()
        rebuildMotes()
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
        mercuryLayer.lineWidth = 2
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
        guard let band else { return }
        let color = temperatureColor(for: band)
        let mercuryTop = CGFloat(band.thermalMotes.mercuryTop)
        let mercuryPath = CGMutablePath()
        mercuryPath.move(to: CGPoint(x: 7.5, y: 7))
        mercuryPath.addLine(to: CGPoint(x: 7.5, y: mercuryTop))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mercuryLayer.path = mercuryPath
        mercuryLayer.strokeColor = color.cgColor
        bulbLayer.fillColor = color.cgColor
        CATransaction.commit()
    }

    private func rebuildMotes() {
        moteLayers.forEach { $0.removeFromSuperlayer() }
        moteLayers.removeAll()

        guard !reduceMotion, let band else { return }
        let configuration = band.thermalMotes
        guard let duration = configuration.cycleDuration else { return }

        let color = temperatureColor(for: band)
        let xPositions: [CGFloat] = [2, 15, 1, 18]
        let repeatPeriod = configuration.count == 1 ? duration * 2 : duration
        let delayStep = repeatPeriod / Double(configuration.emitterCount)
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

    private func temperatureColor(for band: TemperatureBand) -> NSColor {
        switch band {
        case .cool: Self.coolColor
        case .warm: Self.warmColor
        case .hot: Self.hotColor
        }
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
