import XCTest
@testable import ThermalIconCore

final class TemperaturePresentationTests: XCTestCase {
    func testM4DormantPerformanceCoreTemperatureIsRejected() {
        XCTAssertFalse(SMCReader.isUsableCPUTemperature(40, key: "Tp01", rejectsDormantPcoreReadings: true))
        XCTAssertTrue(SMCReader.isUsableCPUTemperature(40, key: "Te05", rejectsDormantPcoreReadings: true))
        XCTAssertTrue(SMCReader.isUsableCPUTemperature(40, key: "Tp01", rejectsDormantPcoreReadings: false))
        XCTAssertFalse(SMCReader.isUsableCPUTemperature(1.9, key: "Tp01", rejectsDormantPcoreReadings: true))
    }

    func testTemperatureBandsAtThresholdBoundaries() {
        let thresholds = TemperatureThresholds(warm: 55, hot: 80)

        XCTAssertEqual(TemperatureBand.classify(54.9, thresholds: thresholds), .cool)
        XCTAssertEqual(TemperatureBand.classify(55, thresholds: thresholds), .warm)
        XCTAssertEqual(TemperatureBand.classify(79.9, thresholds: thresholds), .warm)
        XCTAssertEqual(TemperatureBand.classify(80, thresholds: thresholds), .hot)
    }

    func testTemperaturePaletteInterpolatesAndClamps() {
        let healthy = TemperaturePalette.color(for: 45)
        let warm = TemperaturePalette.color(for: 62.5)
        let dangerous = TemperaturePalette.color(for: 80)

        XCTAssertEqual(TemperaturePalette.color(for: 0), healthy)
        XCTAssertEqual(TemperaturePalette.color(for: 100), dangerous)
        XCTAssertEqual(healthy.green, Double(0xE0) / 255, accuracy: 0.001)
        XCTAssertEqual(warm.red, 1, accuracy: 0.001)
        XCTAssertEqual(dangerous.green, Double(0x45) / 255, accuracy: 0.001)
        XCTAssertEqual(TemperaturePalette.mercuryTop(for: 35), 12, accuracy: 0.001)
        XCTAssertEqual(TemperaturePalette.mercuryTop(for: 95), 17, accuracy: 0.001)
    }

    func testThermalMotesConfigurationByTemperatureBand() {
        XCTAssertEqual(
            TemperatureBand.cool.thermalMotes,
            ThermalMotesConfiguration(count: 1, emitterCount: 2, cycleDuration: 2.8)
        )
        XCTAssertEqual(
            TemperatureBand.warm.thermalMotes,
            ThermalMotesConfiguration(count: 2, emitterCount: 2, cycleDuration: 2.2)
        )
        XCTAssertEqual(
            TemperatureBand.hot.thermalMotes,
            ThermalMotesConfiguration(count: 4, emitterCount: 4, cycleDuration: 1.2)
        )
    }

    func testFanModesIncludeMutedBeforeStandardModes() {
        XCTAssertEqual(FanControlMode.allCases, [.muted, .quiet, .standard, .ultra])
        XCTAssertFalse(FanControlMode.muted.requiresContinuousControl)
        XCTAssertTrue(FanControlMode.quiet.requiresContinuousControl)
        XCTAssertTrue(FanControlMode.standard.requiresContinuousControl)
        XCTAssertTrue(FanControlMode.ultra.requiresContinuousControl)
    }

    func testInvalidPersistedThresholdsFallBackToDefaults() {
        XCTAssertEqual(
            TemperatureThresholds(warm: 999, hot: -1),
            TemperatureThresholds(warm: 55, hot: 80)
        )
        XCTAssertEqual(
            TemperatureThresholds(warm: 55, hot: 90),
            TemperatureThresholds(warm: 55, hot: 80)
        )
    }

    func testQuietCurveStaysAtMinimumUntilHotThenRamps() {
        XCTAssertEqual(QuietFanCurve.percentage(celsius: 50, hotThreshold: 80), 0)
        XCTAssertEqual(QuietFanCurve.percentage(celsius: 79.9, hotThreshold: 80), 0)
        XCTAssertEqual(QuietFanCurve.percentage(celsius: 80, hotThreshold: 80), 0)
        XCTAssertEqual(QuietFanCurve.percentage(celsius: 85, hotThreshold: 80), 50)
        XCTAssertEqual(QuietFanCurve.percentage(celsius: 90, hotThreshold: 80), 100)

        XCTAssertEqual(QuietFanCurve.percentage(celsius: 85, hotThreshold: 85), 0)
        XCTAssertEqual(QuietFanCurve.percentage(celsius: 87.5, hotThreshold: 85), 50)
        XCTAssertEqual(QuietFanCurve.percentage(celsius: 90, hotThreshold: 85), 100)
    }

    func testQuietCurveTargetsStayInsideHardwareRange() {
        XCTAssertEqual(
            QuietFanCurve.targetRPM(celsius: 20, minimum: 1_350, maximum: 6_000, hotThreshold: 80),
            1_500
        )
        XCTAssertEqual(
            QuietFanCurve.targetRPM(celsius: 20, minimum: 1_500, maximum: 6_000, hotThreshold: 80),
            1_500
        )
        XCTAssertEqual(
            QuietFanCurve.targetRPM(celsius: 20, minimum: 5_500, maximum: 6_000, hotThreshold: 80),
            5_500
        )
        XCTAssertEqual(
            QuietFanCurve.targetRPM(celsius: 85, minimum: 1_500, maximum: 6_000, hotThreshold: 80),
            3_750
        )
        XCTAssertEqual(
            QuietFanCurve.targetRPM(celsius: 95, minimum: 1_500, maximum: 6_000, hotThreshold: 80),
            6_000
        )
    }

    func testStandardCurveUses1800FloorThenRampsToMaximum() {
        XCTAssertEqual(
            StandardFanCurve.targetRPM(celsius: 20, minimum: 1_350, maximum: 5_800, hotThreshold: 80),
            1_800
        )
        XCTAssertEqual(
            StandardFanCurve.targetRPM(celsius: 80, minimum: 1_350, maximum: 5_800, hotThreshold: 80),
            1_800
        )
        XCTAssertEqual(
            StandardFanCurve.targetRPM(celsius: 85, minimum: 1_350, maximum: 5_800, hotThreshold: 80),
            3_800
        )
        XCTAssertEqual(
            StandardFanCurve.targetRPM(celsius: 90, minimum: 1_350, maximum: 5_800, hotThreshold: 80),
            5_800
        )
    }

    func testStandardCurveRespectsHigherHardwareMinimumAndMaximum() {
        XCTAssertEqual(
            StandardFanCurve.targetRPM(celsius: 50, minimum: 2_100, maximum: 6_000, hotThreshold: 80),
            2_100
        )
        XCTAssertEqual(
            StandardFanCurve.targetRPM(celsius: 50, minimum: 1_500, maximum: 1_700, hotThreshold: 80),
            1_700
        )
    }

    func testFanTargetStabilizerHoldsCoolingAndLimitsRpmChanges() {
        var stabilizer = FanTargetStabilizer()

        XCTAssertEqual(stabilizer.effectiveTemperature(for: 85), 85)
        XCTAssertEqual(stabilizer.effectiveTemperature(for: 83), 85)
        XCTAssertEqual(stabilizer.effectiveTemperature(for: 82.5), 85)
        XCTAssertEqual(stabilizer.effectiveTemperature(for: 81.9), 81.9)

        XCTAssertEqual(stabilizer.limitTargets([1_500, 1_500], at: 0), [1_500, 1_500])
        XCTAssertEqual(stabilizer.limitTargets([4_000, 4_000], at: 2), [2_300, 2_300])
        XCTAssertEqual(stabilizer.limitTargets([1_500, 1_500], at: 3), [2_120, 2_120])
        XCTAssertEqual(
            stabilizer.limitTargets([5_800, 5_800], at: 3.1, forceImmediate: true),
            [5_800, 5_800]
        )
    }

    func testFanSnapshotValidationRejectsUnsafeRanges() {
        let validFan = FanSnapshot(
            index: 0,
            currentRPM: 2_000,
            minimumRPM: 0,
            maximumRPM: 6_000,
            targetRPM: 4_200,
            mode: 1
        )
        let invalidFan = FanSnapshot(
            index: 0,
            currentRPM: 2_000,
            minimumRPM: 6_000,
            maximumRPM: 1_500,
            targetRPM: 4_200,
            mode: 1
        )

        XCTAssertTrue(validFan.isValid)
        XCTAssertFalse(invalidFan.isValid)
        XCTAssertEqual(
            try FanStatusCodec.decodeValidated(
                FanStatusCodec.encode(FanControlStatus(mode: .ultra, fans: [validFan]))
            ),
            FanControlStatus(mode: .ultra, fans: [validFan])
        )
        XCTAssertThrowsError(
            try FanStatusCodec.decodeValidated(
                FanStatusCodec.encode(FanControlStatus(mode: .ultra, fans: [invalidFan]))
            )
        )
    }

    func testCodeSigningRequirementRejectsInjectedIdentifiers() {
        XCTAssertNoThrow(try CodeSigningRequirement(
            identifier: fanHelperBundleIdentifier,
            teamID: "6YQH3QFFK8"
        ))
        XCTAssertThrowsError(try CodeSigningRequirement(
            identifier: #"as.kargn.Helper\" or true"#,
            teamID: "6YQH3QFFK8"
        ))
        XCTAssertThrowsError(try CodeSigningRequirement(
            identifier: fanHelperBundleIdentifier,
            teamID: "INVALID"
        ))
    }
}
