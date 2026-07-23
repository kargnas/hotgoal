import XCTest
@testable import ThermalIconCore

final class TemperaturePresentationTests: XCTestCase {
    func testTemperatureBandsAtThresholdBoundaries() {
        let thresholds = TemperatureThresholds(warm: 55, hot: 80)

        XCTAssertEqual(TemperatureBand.classify(54.9, thresholds: thresholds), .cool)
        XCTAssertEqual(TemperatureBand.classify(55, thresholds: thresholds), .warm)
        XCTAssertEqual(TemperatureBand.classify(79.9, thresholds: thresholds), .warm)
        XCTAssertEqual(TemperatureBand.classify(80, thresholds: thresholds), .hot)
    }

    func testInvalidPersistedThresholdsFallBackToDefaults() {
        XCTAssertEqual(
            TemperatureThresholds(warm: 999, hot: -1),
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

        let lateRamp = TemperatureThresholds(warm: 65, hot: 90)
        XCTAssertEqual(QuietFanCurve.percentage(celsius: 89.9, thresholds: lateRamp), 0)
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
            QuietFanCurve.targetRPM(celsius: 95, minimum: 1_500, maximum: 6_000, thresholds: thresholds),
            6_000
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
