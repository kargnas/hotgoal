import XCTest
@testable import ThermalIconCore

final class TemperaturePresentationTests: XCTestCase {
    func testTemperatureSmootherDampsSpikesAndResetsAfterUnavailableReading() {
        var smoother = TemperatureSmoother()

        XCTAssertEqual(smoother.update(72)!, 72, accuracy: 0.001)
        XCTAssertEqual(smoother.update(82)!, 74.5, accuracy: 0.001)
        XCTAssertNil(smoother.update(nil))
        XCTAssertEqual(smoother.update(80)!, 80, accuracy: 0.001)
    }

    func testTemperatureBandsAtThresholdBoundaries() {
        let thresholds = TemperatureThresholds(warm: 55, hot: 80)

        XCTAssertEqual(TemperatureBand.classify(54.9, thresholds: thresholds), .cool)
        XCTAssertEqual(TemperatureBand.classify(55, thresholds: thresholds), .warm)
        XCTAssertEqual(TemperatureBand.classify(79.9, thresholds: thresholds), .warm)
        XCTAssertEqual(TemperatureBand.classify(80, thresholds: thresholds), .hot)
    }

    func testThermalMotesConfigurationByTemperatureBand() {
        XCTAssertEqual(
            TemperatureBand.cool.thermalMotes,
            ThermalMotesConfiguration(count: 1, emitterCount: 2, cycleDuration: 2.8, mercuryTop: 11)
        )
        XCTAssertEqual(
            TemperatureBand.warm.thermalMotes,
            ThermalMotesConfiguration(count: 2, emitterCount: 2, cycleDuration: 2.2, mercuryTop: 15)
        )
        XCTAssertEqual(
            TemperatureBand.hot.thermalMotes,
            ThermalMotesConfiguration(count: 4, emitterCount: 4, cycleDuration: 1.2, mercuryTop: 18)
        )
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
        let thresholds = TemperatureThresholds(warm: 55, hot: 80)

        XCTAssertEqual(QuietFanCurve.percentage(celsius: 50, thresholds: thresholds), 0)
        XCTAssertEqual(QuietFanCurve.percentage(celsius: 79.9, thresholds: thresholds), 0)
        XCTAssertEqual(QuietFanCurve.percentage(celsius: 80, thresholds: thresholds), 0)
        XCTAssertEqual(QuietFanCurve.percentage(celsius: 85, thresholds: thresholds), 50)
        XCTAssertEqual(QuietFanCurve.percentage(celsius: 90, thresholds: thresholds), 100)

        let lateRamp = TemperatureThresholds(warm: 65, hot: 85)
        XCTAssertEqual(QuietFanCurve.percentage(celsius: 85, thresholds: lateRamp), 0)
        XCTAssertEqual(QuietFanCurve.percentage(celsius: 87.5, thresholds: lateRamp), 50)
        XCTAssertEqual(QuietFanCurve.percentage(celsius: 90, thresholds: lateRamp), 100)
    }

    func testQuietCurveTargetsStayInsideHardwareRange() {
        let thresholds = TemperatureThresholds(warm: 55, hot: 80)

        XCTAssertEqual(
            QuietFanCurve.targetRPM(celsius: 20, minimum: 1_500, maximum: 6_000, thresholds: thresholds),
            1_500
        )
        XCTAssertEqual(
            QuietFanCurve.targetRPM(celsius: 20, minimum: 5_500, maximum: 6_000, thresholds: thresholds),
            5_500
        )
        XCTAssertEqual(
            QuietFanCurve.targetRPM(celsius: 85, minimum: 1_500, maximum: 6_000, thresholds: thresholds),
            3_750
        )
        XCTAssertEqual(
            QuietFanCurve.targetRPM(celsius: 95, minimum: 1_500, maximum: 6_000, thresholds: thresholds),
            6_000
        )
    }

    func testStandardCurveUses1800FloorThenRampsToMaximum() {
        let thresholds = TemperatureThresholds(warm: 55, hot: 80)

        XCTAssertEqual(
            StandardFanCurve.targetRPM(celsius: 20, minimum: 1_350, maximum: 5_800, thresholds: thresholds),
            1_800
        )
        XCTAssertEqual(
            StandardFanCurve.targetRPM(celsius: 80, minimum: 1_350, maximum: 5_800, thresholds: thresholds),
            1_800
        )
        XCTAssertEqual(
            StandardFanCurve.targetRPM(celsius: 85, minimum: 1_350, maximum: 5_800, thresholds: thresholds),
            3_800
        )
        XCTAssertEqual(
            StandardFanCurve.targetRPM(celsius: 90, minimum: 1_350, maximum: 5_800, thresholds: thresholds),
            5_800
        )
    }

    func testStandardCurveRespectsHigherHardwareMinimumAndMaximum() {
        let thresholds = TemperatureThresholds(warm: 55, hot: 80)

        XCTAssertEqual(
            StandardFanCurve.targetRPM(celsius: 50, minimum: 2_100, maximum: 6_000, thresholds: thresholds),
            2_100
        )
        XCTAssertEqual(
            StandardFanCurve.targetRPM(celsius: 50, minimum: 1_500, maximum: 1_700, thresholds: thresholds),
            1_700
        )
    }

    func testFanSnapshotValidationRejectsUnsafeRanges() {
        XCTAssertTrue(FanSnapshot(
            index: 0,
            currentRPM: 2_000,
            minimumRPM: 0,
            maximumRPM: 6_000,
            targetRPM: 4_200,
            mode: 1
        ).isValid)
        XCTAssertFalse(FanSnapshot(
            index: 0,
            currentRPM: 2_000,
            minimumRPM: 6_000,
            maximumRPM: 1_500,
            targetRPM: 4_200,
            mode: 1
        ).isValid)
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
