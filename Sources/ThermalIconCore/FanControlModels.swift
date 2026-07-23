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

public enum FanBoost: Int, CaseIterable, Codable, Sendable {
    case seventy = 70
    case eightyFive = 85
    case maximum = 100

    public func targetRPM(minimum: Int, maximum: Int) -> Int {
        min(max(Int((Double(maximum) * Double(rawValue) / 100).rounded()), minimum), maximum)
    }

    public var title: String {
        rawValue == 100 ? "Maximum" : "Boost \(rawValue)%"
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
    func setBoost(percent: Int, reply: @escaping (Bool, String?) -> Void)
    func restoreAutomatic(reply: @escaping (Bool, String?) -> Void)
}
