import Foundation

public enum DisplayMode: String {
    case icon
    case number
}

public struct ThermalColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
}

public enum TemperaturePalette {
    // 45 °C is healthy and 80 °C is already dangerous, so the palette reaches both endpoints early.
    public static func color(for celsius: Double) -> ThermalColor {
        let value = celsius.isFinite ? min(max(celsius, 45), 80) : 80
        switch value {
        case ..<62.5: return blend(green, yellow, fraction: (value - 45) / 17.5)
        default: return blend(yellow, red, fraction: (value - 62.5) / 17.5)
        }
    }

    public static func mercuryTop(for celsius: Double) -> Double {
        let value = celsius.isFinite ? min(max(celsius, 35), 95) : 95
        return 12 + (value - 35) / 60 * 5
    }

    private static let green = rgb(0x75, 0xE0, 0x6B)
    private static let yellow = rgb(0xFF, 0xD4, 0x52)
    private static let red = rgb(0xFF, 0x45, 0x3A)

    private static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> ThermalColor {
        ThermalColor(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
    }

    private static func blend(_ start: ThermalColor, _ end: ThermalColor, fraction: Double) -> ThermalColor {
        ThermalColor(
            red: start.red + (end.red - start.red) * fraction,
            green: start.green + (end.green - start.green) * fraction,
            blue: start.blue + (end.blue - start.blue) * fraction
        )
    }
}

public struct TemperatureThresholds: Equatable {
    public static let defaultWarm = 55.0
    public static let defaultHot = 80.0
    public static let warmChoices = [50.0, 55.0, 60.0, 65.0]
    public static let hotChoices = [70.0, 75.0, 80.0, 85.0]

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

    public var label: String {
        switch self {
        case .cool: "Cool"
        case .warm: "Warm"
        case .hot: "Hot"
        }
    }

    public var thermalMotes: ThermalMotesConfiguration {
        switch self {
        case .cool: ThermalMotesConfiguration(count: 1, emitterCount: 2, cycleDuration: 2.8)
        case .warm: ThermalMotesConfiguration(count: 2, emitterCount: 2, cycleDuration: 2.2)
        case .hot: ThermalMotesConfiguration(count: 4, emitterCount: 4, cycleDuration: 1.2)
        }
    }
}

public struct ThermalMotesConfiguration: Equatable, Sendable {
    public let count: Int
    public let emitterCount: Int
    public let cycleDuration: TimeInterval?
}
