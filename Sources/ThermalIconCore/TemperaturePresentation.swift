import Foundation

public enum DisplayMode: String {
    case icon
    case number
}

public struct TemperatureThresholds: Equatable {
    public static let defaultWarm = 55.0
    public static let defaultHot = 80.0
    public static let warmChoices = [50.0, 55.0, 60.0, 65.0]
    public static let hotChoices = [70.0, 75.0, 80.0, 85.0, 90.0]

    public let warm: Double
    public let hot: Double

    public init(warm: Double, hot: Double) {
        self.warm = Self.warmChoices.contains(warm) ? warm : Self.defaultWarm
        self.hot = Self.hotChoices.contains(hot) ? hot : Self.defaultHot
    }
}

public enum TemperatureBand: Equatable {
    case cool
    case warm
    case hot

    public static func classify(_ celsius: Double, thresholds: TemperatureThresholds) -> Self {
        if celsius >= thresholds.hot {
            return .hot
        }
        if celsius >= thresholds.warm {
            return .warm
        }
        return .cool
    }

    public var symbolName: String {
        switch self {
        case .cool: "thermometer.low"
        case .warm: "thermometer.medium"
        case .hot: "thermometer.high"
        }
    }

    public var label: String {
        switch self {
        case .cool: "Cool"
        case .warm: "Warm"
        case .hot: "Hot"
        }
    }
}
