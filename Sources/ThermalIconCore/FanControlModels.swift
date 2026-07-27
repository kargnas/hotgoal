import Foundation

// Fan hysteresis and asymmetric RPM slew limits are adapted from
// leaperone/smctl (MIT); see THIRD_PARTY_NOTICES.md.

public let fanHelperMachServiceName = "as.kargn.ThermalIcon.FanHelper"
public let fanHelperBundleIdentifier = "as.kargn.ThermalIcon.FanHelper"
public let mainAppBundleIdentifier = "as.kargn.ThermalIcon"
public let fanHelperPlistName = "as.kargn.ThermalIcon.FanHelper.plist"

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

    public func targetRPM(
        celsius: Double,
        minimum: Int,
        maximum: Int,
        hotThreshold: Double
    ) -> Int? {
        switch self {
        case .systemDefault:
            return nil
        case .ultra:
            return maximum
        case .quiet:
            break
        }

        guard celsius.isFinite else { return maximum }
        let floor = min(max(1_500, minimum), maximum)
        let percent = celsius >= 90 ? 1 : max(0, (celsius - hotThreshold) / (90 - hotThreshold))
        return min(max(Int((Double(floor) + Double(maximum - floor) * percent).rounded()), floor), maximum)
    }
}

public enum FanControl: Codable, Equatable, Sendable {
    case noise(NoiseMode, hotThreshold: Double)
    case targetTemperature(Double)

    public static let targetTemperatureChoices = stride(from: 40.0, through: 85.0, by: 5.0).map { $0 }

    public var isValid: Bool {
        switch self {
        case let .noise(_, hotThreshold):
            TemperatureThresholds.hotChoices.contains(hotThreshold)
        case let .targetTemperature(target):
            Self.targetTemperatureChoices.contains(target)
        }
    }

    // Manual SMC targets can reset across sleep, so every non-default control is reconciled.
    public var requiresContinuousControl: Bool {
        if case .noise(.systemDefault, _) = self { return false }
        return true
    }

    public var noiseMode: NoiseMode? {
        guard case let .noise(mode, _) = self else { return nil }
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
    // The helper runs every two seconds; 50 RPM/°C reacts within seconds without large audible jumps.
    public static let rpmPerDegreePerCycle = 50.0

    public static func targets(
        celsius: Double,
        target: Double,
        fans: [FanSnapshot]
    ) -> [Int] {
        guard celsius.isFinite else { return fans.map(\.maximumRPM) }
        if celsius >= 90 { return fans.map(\.maximumRPM) }
        let error = celsius - target
        let adjustment = abs(error) <= deadband ? 0 : Int((error * rpmPerDegreePerCycle).rounded())
        return fans.map { fan in
            // SMC's last target is the integral state; no second copy can drift out of sync.
            // ponytail: add a derivative term only if measured thermal traces show sustained oscillation.
            let currentTarget = fan.targetRPM.flatMap { $0 >= fan.minimumRPM ? $0 : nil } ?? fan.currentRPM
            return min(max(currentTarget + adjustment, fan.minimumRPM), fan.maximumRPM)
        }
    }
}

public struct FanTargetStabilizer: Sendable {
    // A slower fall prevents audible hunting; a faster rise still reacts promptly to heat.
    public static let hysteresisCelsius = 3.0
    public static let riseRPMPerSecond = 400.0
    public static let fallRPMPerSecond = 180.0

    private var previousTemperature: Double?
    private var previousTargets: [Int]?
    private var previousUpdateTime: TimeInterval?

    public init() {}

    public mutating func effectiveTemperature(for temperature: Double) -> Double {
        guard temperature.isFinite else { return temperature }
        let effectiveTemperature: Double
        if let previousTemperature,
           temperature < previousTemperature,
           temperature >= previousTemperature - Self.hysteresisCelsius {
            effectiveTemperature = previousTemperature
        } else {
            effectiveTemperature = temperature
        }
        previousTemperature = effectiveTemperature
        return effectiveTemperature
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

        let elapsed = max(0, time - previousUpdateTime)
        let limited = zip(previousTargets, requestedTargets).map { previous, requested in
            let rate = requested >= previous ? Self.riseRPMPerSecond : Self.fallRPMPerSecond
            let maximumChange = Int((rate * elapsed).rounded(.down))
            if requested >= previous {
                return min(requested, previous + maximumChange)
            }
            return max(requested, previous - maximumChange)
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
