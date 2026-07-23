import Foundation

enum DisplayMode: String {
    case icon
    case number
}

struct TemperatureThresholds: Equatable {
    static let defaultWarm = 55.0
    static let defaultHot = 80.0
    static let warmChoices = [50.0, 55.0, 60.0, 65.0]
    static let hotChoices = [70.0, 75.0, 80.0, 85.0, 90.0]

    let warm: Double
    let hot: Double

    init(warm: Double, hot: Double) {
        self.warm = Self.warmChoices.contains(warm) ? warm : Self.defaultWarm
        self.hot = Self.hotChoices.contains(hot) ? hot : Self.defaultHot
    }
}

enum TemperatureBand: Equatable {
    case cool
    case warm
    case hot

    static func classify(_ celsius: Double, thresholds: TemperatureThresholds) -> Self {
        if celsius >= thresholds.hot {
            return .hot
        }
        if celsius >= thresholds.warm {
            return .warm
        }
        return .cool
    }

    var symbolName: String {
        switch self {
        case .cool: "thermometer.low"
        case .warm: "thermometer.medium"
        case .hot: "thermometer.high"
        }
    }

    var label: String {
        switch self {
        case .cool: "Cool"
        case .warm: "Warm"
        case .hot: "Hot"
        }
    }
}
