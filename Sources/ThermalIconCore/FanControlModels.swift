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

public enum FanControlMode: String, CaseIterable, Codable, Sendable {
    case muted
    case quiet
    case standard
    case ultra

    public var title: String {
        rawValue.capitalized
    }
}

public enum QuietFanCurve {
    // Keep steady airflow while preserving a clear acoustic gap below Standard.
    public static let minimumRPM = 1_500

    public static func percentage(celsius: Double, thresholds: TemperatureThresholds) -> Int {
        guard celsius.isFinite else { return 100 }
        if celsius >= 90 { return 100 }
        if celsius <= thresholds.hot { return 0 }

        let span = 90 - thresholds.hot
        guard span > 0 else { return 100 }
        return Int((100 * (celsius - thresholds.hot) / span).rounded())
    }

    public static func targetRPM(
        celsius: Double,
        minimum: Int,
        maximum: Int,
        thresholds: TemperatureThresholds
    ) -> Int {
        let floor = min(max(Self.minimumRPM, minimum), maximum)
        let percent = percentage(celsius: celsius, thresholds: thresholds)
        return rampedTargetRPM(floor: floor, maximum: maximum, percent: percent)
    }
}

public enum StandardFanCurve {
    public static let minimumRPM = 1_800

    public static func targetRPM(
        celsius: Double,
        minimum: Int,
        maximum: Int,
        thresholds: TemperatureThresholds
    ) -> Int {
        let floor = min(max(Self.minimumRPM, minimum), maximum)
        let percent = QuietFanCurve.percentage(celsius: celsius, thresholds: thresholds)
        return rampedTargetRPM(floor: floor, maximum: maximum, percent: percent)
    }
}

private func rampedTargetRPM(floor: Int, maximum: Int, percent: Int) -> Int {
    guard maximum > floor else { return maximum }
    let target = Double(floor) + Double(maximum - floor) * Double(percent) / 100
    return min(max(Int(target.rounded()), floor), maximum)
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

public enum FanPayloadCodec {
    public static func encode(_ snapshots: [FanSnapshot]) throws -> Data {
        try JSONEncoder().encode(snapshots)
    }

    public static func decodeValidated(_ data: Data) throws -> [FanSnapshot] {
        let snapshots = try JSONDecoder().decode([FanSnapshot].self, from: data)
        guard snapshots.allSatisfy(\.isValid) else {
            throw FanPayloadError.invalidSnapshot
        }
        return snapshots
    }
}

public enum FanPayloadError: Error, Equatable, Sendable {
    case invalidSnapshot
}

@objc public protocol FanHelperProtocol {
    func getFanStatus(reply: @escaping (Data?, String?) -> Void)
    func setMode(
        mode: String,
        warmThreshold: Double,
        hotThreshold: Double,
        reply: @escaping (Bool, String?) -> Void
    )
    func restoreAutomatic(reply: @escaping (Bool, String?) -> Void)
}
