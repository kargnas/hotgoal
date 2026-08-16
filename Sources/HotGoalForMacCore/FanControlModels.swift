import Foundation

// Fan hysteresis and asymmetric RPM slew limits are adapted from
// leaperone/smctl (MIT); see THIRD_PARTY_NOTICES.md.

public let fanHelperMachServiceName = "as.kargn.hotgoalformac.helper"
public let fanHelperBundleIdentifier = "as.kargn.hotgoalformac.helper"
public let mainAppBundleIdentifier = "as.kargn.hotgoalformac"
public let fanHelperPlistName = "as.kargn.hotgoalformac.helper.plist"

public struct FanSnapshot: Codable, Equatable, Sendable {
    public let index: Int
    public let currentRPM: Int
    public let minimumRPM: Int
    public let maximumRPM: Int
    public let targetRPM: Int?
    public let mode: Int

    public init(
        index: Int,
        currentRPM: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        targetRPM: Int?,
        mode: Int
    ) {
        self.index = index
        self.currentRPM = currentRPM
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.targetRPM = targetRPM
        self.mode = mode
    }

    public var isValid: Bool {
        index >= 0 &&
            currentRPM >= 0 &&
            minimumRPM >= 0 &&
            maximumRPM > minimumRPM &&
            targetRPM.map { $0 >= 0 && $0 <= maximumRPM } != false &&
            [0, 1, 3].contains(mode)
    }

    public var isManual: Bool { mode == 1 }
}

public enum NoiseMode: String, CaseIterable, Codable, Sendable {
    case systemDefault
    case quiet
    case ultra

    public var title: String {
        self == .systemDefault ? "System Default" : rawValue.capitalized
    }
}

public enum FanControlMenuSection: Equatable, Sendable {
    case targetTemperature
    case presets

    public static let primaryOrder: [Self] = [.targetTemperature, .presets]

    public var title: String {
        switch self {
        case .targetTemperature: "Maintain Target Temperature"
        case .presets: "Preset Fan Modes"
        }
    }
}

public enum FanControl: Codable, Equatable, Sendable {
    case noise(NoiseMode)
    case targetTemperature(Double)

    public static let targetTemperatureChoices = stride(from: 40.0, through: 85.0, by: 5.0).map { $0 }

    public var isValid: Bool {
        switch self {
        case .noise:
            true
        case let .targetTemperature(target):
            Self.targetTemperatureChoices.contains(target)
        }
    }

    // Manual SMC targets can reset across sleep, so every non-default control is reconciled.
    public var requiresContinuousControl: Bool {
        if case .noise(.systemDefault) = self { return false }
        return true
    }

    public var noiseMode: NoiseMode? {
        guard case let .noise(mode) = self else { return nil }
        return mode
    }

    public var targetTemperature: Double? {
        guard case let .targetTemperature(target) = self else { return nil }
        return target
    }
}

public struct FanControlStatus: Codable, Equatable, Sendable {
    public let control: FanControl?
    public let fans: [FanSnapshot]

    public init(control: FanControl?, fans: [FanSnapshot]) {
        self.control = control
        self.fans = fans
    }

    public var isValid: Bool {
        control?.isValid != false && fans.allSatisfy(\.isValid)
    }
}

public enum TargetTemperatureController {
    public static let deadband = 0.5
    // The helper runs every second; small upward steps avoid sudden acoustic changes.
    public static let rpmPerDegreePerCycle = 10.0
    public static let coolingRPMPerDegreePerCycle = 20.0

    public static func targets(
        celsius: Double,
        target: Double,
        fans: [FanSnapshot]
    ) -> [Int] {
        guard celsius.isFinite else { return fans.map(\.maximumRPM) }
        if celsius >= 90 { return fans.map(\.maximumRPM) }
        let error = celsius - target
        let gain = error < -deadband ? coolingRPMPerDegreePerCycle : rpmPerDegreePerCycle
        let adjustment = abs(error) <= deadband ? 0 : Int((error * gain).rounded())
        return fans.map { fan in
            // SMC's last target is the integral state; no second copy can drift out of sync.
            // ponytail: add a derivative term only if measured thermal traces show sustained oscillation.
            let currentTarget = fan.targetRPM.flatMap { $0 >= fan.minimumRPM ? $0 : nil } ?? fan.currentRPM
            return min(max(currentTarget + adjustment, fan.minimumRPM), fan.maximumRPM)
        }
    }
}

public struct CriticalTemperatureGate: Sendable {
    public static let criticalCelsius = 90.0
    // Apple Silicon SMC sensor averages show ±8-13 °C single-sample noise (dormant-core
    // subset changes), so one instantaneous reading above 90 °C is not evidence of real
    // overheating. Three consecutive one-second samples filter every observed glitch while
    // delaying a genuine runaway response by at most two seconds.
    public static let requiredConsecutiveSamples = 3
    public static let maximumSampleGap: TimeInterval = 2

    private var consecutiveCriticalSamples = 0
    private var previousSampleTime: TimeInterval?

    public init() {}

    public mutating func register(_ celsius: Double, at time: TimeInterval) -> Bool {
        // A wake or stalled timer invalidates streak continuity the same way it invalidates
        // the rolling average, so stale critical counts must not combine with fresh ones.
        if let previousSampleTime, time - previousSampleTime > Self.maximumSampleGap {
            consecutiveCriticalSamples = 0
        }
        previousSampleTime = time
        consecutiveCriticalSamples = celsius >= Self.criticalCelsius ? consecutiveCriticalSamples + 1 : 0
        return consecutiveCriticalSamples >= Self.requiredConsecutiveSamples
    }
}

public struct TemperatureAverage: Sendable {
    public static let sampleCount = 10
    public static let maximumSampleGap: TimeInterval = 2

    private var samples: [Double] = []
    private var previousSampleTime: TimeInterval?

    public init() {}

    public mutating func append(_ celsius: Double, at time: TimeInterval) -> Double? {
        guard celsius.isFinite else { return nil }
        if let previousSampleTime, time - previousSampleTime > Self.maximumSampleGap {
            samples.removeAll(keepingCapacity: true)
        }
        previousSampleTime = time
        samples.append(celsius)
        if samples.count > Self.sampleCount { samples.removeFirst() }
        guard samples.count == Self.sampleCount else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }
}

public struct FanTargetStabilizer: Sendable {
    // Falling is faster than rising but remains bounded to prevent abrupt acoustic changes.
    public static let riseRPMPerSecond = 100.0
    public static let fallRPMPerSecond = 200.0

    private var previousTargets: [Int]?
    private var previousUpdateTime: TimeInterval?

    public init() {}

    public mutating func forceMaximumTargets(
        for fans: [FanSnapshot],
        at time: TimeInterval
    ) -> [Int] {
        limitTargets(fans.map(\.maximumRPM), at: time, forceImmediate: true)
    }

    public mutating func limitTargets(
        _ requestedTargets: [Int],
        at time: TimeInterval,
        forceImmediate: Bool = false
    ) -> [Int] {
        defer {
            previousUpdateTime = time
        }
        guard !forceImmediate,
              let previousTargets,
              previousTargets.count == requestedTargets.count,
              let previousUpdateTime else {
            previousTargets = requestedTargets
            return requestedTargets
        }

        // A wake or stalled timer must not turn elapsed time into one large RPM jump.
        let elapsed = min(max(0, time - previousUpdateTime), 2)
        let limited = zip(previousTargets, requestedTargets).map { previous, requested in
            let rate = requested > previous ? Self.riseRPMPerSecond : Self.fallRPMPerSecond
            let maximumChange = Int((rate * elapsed).rounded(.down))
            return requested > previous
                ? min(requested, previous + maximumChange)
                : max(requested, previous - maximumChange)
        }
        self.previousTargets = limited
        return limited
    }
}

public enum FanControlCodec {
    public static func encode(_ control: FanControl) throws -> Data {
        guard control.isValid else { throw FanControlError.invalidControl }
        return try JSONEncoder().encode(control)
    }

    public static func decodeControl(_ data: Data) throws -> FanControl {
        let control = try JSONDecoder().decode(FanControl.self, from: data)
        guard control.isValid else { throw FanControlError.invalidControl }
        return control
    }

    public static func encode(_ status: FanControlStatus) throws -> Data {
        try JSONEncoder().encode(status)
    }

    public static func decodeStatus(_ data: Data) throws -> FanControlStatus {
        let status = try JSONDecoder().decode(FanControlStatus.self, from: data)
        guard status.isValid else {
            throw FanControlError.invalidSnapshot
        }
        return status
    }
}

public enum FanControlError: Error, Equatable, Sendable {
    case invalidControl
    case invalidSnapshot
}

@objc public protocol FanHelperProtocol {
    func getStatus(reply: @escaping (Data?, String?) -> Void)
    func setControl(_ control: Data, reply: @escaping (Bool, String?) -> Void)
}
