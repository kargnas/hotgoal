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

    func testFanControlsAreMutuallyExclusiveAndManualControlsRepeat() {
        XCTAssertEqual(NoiseMode.allCases, [.systemDefault, .quiet, .ultra])
        XCTAssertEqual(NoiseMode.systemDefault.title, "System Default")
        XCTAssertEqual(FanControl.targetTemperatureChoices, [40, 45, 50, 55, 60, 65, 70, 75, 80, 85])
        XCTAssertFalse(FanControl.noise(.systemDefault, hotThreshold: 80).requiresContinuousControl)
        XCTAssertTrue(FanControl.noise(.quiet, hotThreshold: 80).requiresContinuousControl)
        XCTAssertTrue(FanControl.noise(.ultra, hotThreshold: 80).requiresContinuousControl)
        XCTAssertTrue(FanControl.targetTemperature(70).requiresContinuousControl)
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

    func testNoiseModesStayInsideHardwareRange() {
        let cases: [(NoiseMode, Double, Int, Int, Int?)] = [
            (.quiet, 20, 1_350, 6_000, 1_500),
            (.quiet, 20, 1_500, 6_000, 1_500),
            (.quiet, 20, 5_500, 6_000, 5_500),
            (.quiet, 85, 1_500, 6_000, 3_750),
            (.quiet, 95, 1_500, 6_000, 6_000),
        ]
        for (mode, celsius, minimum, maximum, expected) in cases {
            XCTAssertEqual(
                mode.targetRPM(celsius: celsius, minimum: minimum, maximum: maximum, hotThreshold: 80),
                expected
            )
        }
    }

    func testTargetTemperatureControllerConvergesAndKeepsSafetyMaximum() {
        func snapshot(target: Int) -> FanSnapshot {
            FanSnapshot(index: 0, currentRPM: target, minimumRPM: 1_500, maximumRPM: 6_000, targetRPM: target, mode: 1)
        }
        let fan = snapshot(target: 1_500)
        XCTAssertEqual(TargetTemperatureController.targets(celsius: 80, target: 70, fans: [fan]), [1_700])
        XCTAssertEqual(TargetTemperatureController.targets(celsius: 80, target: 70, fans: [snapshot(target: 2_000)]), [2_200])
        XCTAssertEqual(TargetTemperatureController.targets(celsius: 70.4, target: 70, fans: [fan]), [1_500])
        XCTAssertEqual(TargetTemperatureController.targets(celsius: 69, target: 70, fans: [snapshot(target: 3_000)]), [1_500])
        XCTAssertEqual(TargetTemperatureController.targets(celsius: 90, target: 70, fans: [fan]), [6_000])
    }

    func testFanTargetStabilizerHoldsCoolingAndLimitsRpmChanges() {
        var stabilizer = FanTargetStabilizer()

        XCTAssertEqual(stabilizer.effectiveTemperature(for: 85), 85)
        XCTAssertEqual(stabilizer.effectiveTemperature(for: 83), 85)
        XCTAssertEqual(stabilizer.effectiveTemperature(for: 82.5), 85)
        XCTAssertEqual(stabilizer.effectiveTemperature(for: 81.9), 81.9)

        XCTAssertEqual(stabilizer.limitTargets([1_500, 1_500], at: 0), [1_500, 1_500])
        XCTAssertEqual(stabilizer.limitTargets([4_000, 4_000], at: 2), [1_700, 1_700])
        XCTAssertEqual(stabilizer.limitTargets([1_500, 1_500], at: 3), [1_500, 1_500])
        XCTAssertEqual(stabilizer.limitTargets([4_000, 4_000], at: 100), [1_700, 1_700])
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
            try FanControlCodec.decodeStatus(
                FanControlCodec.encode(FanControlStatus(control: .noise(.ultra, hotThreshold: 80), fans: [validFan]))
            ),
            FanControlStatus(control: .noise(.ultra, hotThreshold: 80), fans: [validFan])
        )
        XCTAssertThrowsError(
            try FanControlCodec.decodeStatus(
                FanControlCodec.encode(FanControlStatus(control: .noise(.ultra, hotThreshold: 80), fans: [invalidFan]))
            )
        )
        XCTAssertEqual(
            try FanControlCodec.decodeControl(FanControlCodec.encode(.targetTemperature(70))),
            .targetTemperature(70)
        )
        XCTAssertThrowsError(
            try FanControlCodec.decodeControl(JSONEncoder().encode(FanControl.targetTemperature(90)))
        )
    }

    func testTemperatureLogThrottlesSamplesAndDeletesExpiredFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let expired = directory.appendingPathComponent("expired.csv")
        try Data().write(to: expired)
        let now = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-TemperatureCSVLog.retention - 1)],
            ofItemAtPath: expired.path
        )

        let log = TemperatureCSVLog(directoryURL: directory)
        log.record(targetCelsius: 40, actualCelsius: 45, at: now)
        log.record(targetCelsius: 40, actualCelsius: 44, at: now.addingTimeInterval(1))
        log.record(targetCelsius: 40, actualCelsius: 43, at: now.addingTimeInterval(2))

        XCTAssertFalse(FileManager.default.fileExists(atPath: expired.path))
        let contents = try String(contentsOf: XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first
        ), encoding: .utf8)
        XCTAssertEqual(contents.split(separator: "\n").count, 3)
        XCTAssertTrue(contents.contains("40.0,45.0"))
        XCTAssertTrue(contents.contains("40.0,43.0"))
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
