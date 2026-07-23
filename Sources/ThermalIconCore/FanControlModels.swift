import Foundation

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
    case quiet
    case standard
    case ultra

    public var title: String {
        rawValue.capitalized
    }
}

public enum QuietFanCurve {
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
        let percent = percentage(celsius: celsius, thresholds: thresholds)
        return min(max(Int((Double(maximum) * Double(percent) / 100).rounded()), minimum), maximum)
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
