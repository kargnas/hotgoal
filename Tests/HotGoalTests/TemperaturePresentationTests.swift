import XCTest
@testable import HotGoalCore

final class TemperaturePresentationTests: XCTestCase {
    func testTemperatureSmootherDampsSpikesAndResetsAfterUnavailableReading() {
        var smoother = TemperatureSmoother()

        XCTAssertEqual(smoother.update(72)!, 72, accuracy: 0.001)
        XCTAssertEqual(smoother.update(82)!, 73, accuracy: 0.001)
        XCTAssertNil(smoother.update(nil))
        XCTAssertEqual(smoother.update(80)!, 80, accuracy: 0.001)
    }

    func testFirstRunTargetAppliesOnceOnTheApprovalEdge() {
        // A launch that already has an approved helper is not a fresh approval.
        XCTAssertFalse(FirstRunTarget.approvalJustLanded(previous: nil, isEnabled: true))
        XCTAssertTrue(FirstRunTarget.approvalJustLanded(previous: false, isEnabled: true))
        // Every poll after the edge must be quiet, or the user's own choice gets overwritten.
        XCTAssertFalse(FirstRunTarget.approvalJustLanded(previous: true, isEnabled: true))
        XCTAssertFalse(FirstRunTarget.approvalJustLanded(previous: true, isEnabled: false))

        // Fans are unknown for the first status round-trip after approval: wait, do not drop it.
        XCTAssertFalse(FirstRunTarget.shouldApply(
            pending: true, fanCount: 0, existingControl: nil, commandInFlight: false
        ))
        XCTAssertTrue(FirstRunTarget.shouldApply(
            pending: true, fanCount: 2, existingControl: nil, commandInFlight: false
        ))
        // Never stomp a control the user already picked, and never race a command in flight.
        XCTAssertFalse(FirstRunTarget.shouldApply(
            pending: true, fanCount: 2, existingControl: .noise(.quiet), commandInFlight: false
        ))
        XCTAssertFalse(FirstRunTarget.shouldApply(
            pending: true, fanCount: 2, existingControl: nil, commandInFlight: true
        ))
        XCTAssertFalse(FirstRunTarget.shouldApply(
            pending: false, fanCount: 2, existingControl: nil, commandInFlight: false
        ))

        // The default target has to be a value the menu can actually show as selected.
        XCTAssertTrue(FanControl.targetTemperatureChoices.contains(FirstRunTarget.celsius))
    }

    func testApprovalOverlayChipFlipsWindowBoundsAndStaysOnScreen() {
        // CGWindow reports top-left-origin bounds; Cocoa wants bottom-left.
        let settings = ApprovalOverlayPlacement.cocoaRect(
            fromWindowBounds: CGRect(x: 100, y: 80, width: 700, height: 600),
            primaryScreenHeight: 1000
        )
        XCTAssertEqual(settings, CGRect(x: 100, y: 320, width: 700, height: 600))

        let chipSize = CGSize(width: 268, height: 116)
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 942)
        let chip = ApprovalOverlayPlacement.chipFrame(
            settingsFrame: settings,
            chipSize: chipSize,
            visibleFrame: visible
        )
        // Centered on the content pane, not the whole window, and clear of the sidebar.
        XCTAssertEqual(chip.midX, settings.minX + ApprovalOverlayPlacement.sidebarWidth + (700 - 215) / 2)
        XCTAssertGreaterThan(chip.minX, settings.minX + ApprovalOverlayPlacement.sidebarWidth)
        // Below the window, never over the list it points at.
        XCTAssertEqual(chip.maxY, settings.minY - ApprovalOverlayPlacement.windowGap)

        // No room below: fall back inside the window rather than off-screen.
        let lowWindow = CGRect(x: 200, y: visible.minY + 4, width: 700, height: 600)
        let fallback = ApprovalOverlayPlacement.chipFrame(
            settingsFrame: lowWindow,
            chipSize: chipSize,
            visibleFrame: visible
        )
        XCTAssertEqual(fallback.minY, lowWindow.minY + ApprovalOverlayPlacement.bottomInset)

        // A Settings window hanging off the screen edge must not drag the chip off with it.
        let clamped = ApprovalOverlayPlacement.chipFrame(
            settingsFrame: CGRect(x: 1300, y: -400, width: 700, height: 600),
            chipSize: chipSize,
            visibleFrame: visible
        )
        XCTAssertEqual(clamped.minY, visible.minY + ApprovalOverlayPlacement.screenMargin)
        XCTAssertLessThanOrEqual(clamped.maxX, visible.maxX - ApprovalOverlayPlacement.screenMargin)
    }

    func testApprovalOverlayTrackerDismissesOnGrantAndOnLostSettingsWindow() {
        let frameA = CGRect(x: 0, y: 0, width: 700, height: 600)
        let frameB = frameA.offsetBy(dx: 40, dy: 0)

        var granted = ApprovalOverlayTracker(now: 0)
        XCTAssertEqual(granted.step(now: 0, isSatisfied: true, settingsFrame: frameA), .dismiss)

        // Settings is slow to launch: a window that has never appeared gets the longer grace.
        var slowLaunch = ApprovalOverlayTracker(now: 0)
        XCTAssertEqual(slowLaunch.step(now: 3.9, isSatisfied: false, settingsFrame: nil), .hold)
        XCTAssertEqual(slowLaunch.step(now: 4, isSatisfied: false, settingsFrame: nil), .dismiss)

        var tracker = ApprovalOverlayTracker(now: 0)
        XCTAssertEqual(tracker.step(now: 1, isSatisfied: false, settingsFrame: frameA), .reposition(frameA))
        // An unchanged frame must not snap a chip the user dragged aside.
        XCTAssertEqual(tracker.step(now: 1.5, isSatisfied: false, settingsFrame: frameA), .hold)
        XCTAssertEqual(tracker.step(now: 2, isSatisfied: false, settingsFrame: frameB), .reposition(frameB))
        XCTAssertEqual(tracker.step(now: 3, isSatisfied: false, settingsFrame: nil), .hold)
        XCTAssertEqual(tracker.step(now: 4, isSatisfied: false, settingsFrame: nil), .dismiss)
    }

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
        XCTAssertFalse(FanControl.noise(.systemDefault).requiresContinuousControl)
        XCTAssertTrue(FanControl.noise(.quiet).requiresContinuousControl)
        XCTAssertTrue(FanControl.noise(.ultra).requiresContinuousControl)
        XCTAssertTrue(FanControl.targetTemperature(70).requiresContinuousControl)
    }

    func testTargetTemperatureIsThePrimaryFanControlMenuSection() {
        XCTAssertEqual(
            FanControlMenuSection.primaryOrder,
            [.targetTemperature, .presets]
        )
        XCTAssertEqual(FanControlMenuSection.targetTemperature.title, "Maintain Target Temperature")
        XCTAssertEqual(FanControlMenuSection.presets.title, "Preset Fan Modes")
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

    func testTargetTemperatureControllerConvergesAndKeepsSafetyMaximum() {
        func snapshot(target: Int) -> FanSnapshot {
            FanSnapshot(index: 0, currentRPM: target, minimumRPM: 1_500, maximumRPM: 6_000, targetRPM: target, mode: 1)
        }
        let fan = snapshot(target: 1_500)
        XCTAssertEqual(TargetTemperatureController.targets(celsius: 80, target: 70, fans: [fan]), [1_600])
        XCTAssertEqual(TargetTemperatureController.targets(celsius: 80, target: 70, fans: [snapshot(target: 2_000)]), [2_100])
        XCTAssertEqual(TargetTemperatureController.targets(celsius: 70.4, target: 70, fans: [fan]), [1_500])
        XCTAssertEqual(TargetTemperatureController.targets(celsius: 69, target: 70, fans: [snapshot(target: 3_000)]), [2_980])
        XCTAssertEqual(TargetTemperatureController.targets(celsius: 90, target: 70, fans: [fan]), [6_000])
    }

    func testTemperatureAverageNeedsTenConsecutiveOneSecondSamples() {
        var average = TemperatureAverage()
        for sample in 1..<10 {
            XCTAssertNil(average.append(Double(sample), at: Double(sample)))
        }
        XCTAssertEqual(average.append(10, at: 10), 5.5)
        XCTAssertNil(average.append(20, at: 20))
    }

    func testCriticalTemperatureGateIgnoresSingleSampleSensorGlitches() {
        var gate = CriticalTemperatureGate()
        // One glitched 90+ reading between normal readings must not trip the override.
        XCTAssertFalse(gate.register(55, at: 0))
        XCTAssertFalse(gate.register(93, at: 1))
        XCTAssertFalse(gate.register(56, at: 2))

        // Three consecutive readings are genuine overheating and must trip it.
        XCTAssertFalse(gate.register(91, at: 3))
        XCTAssertFalse(gate.register(92, at: 4))
        XCTAssertTrue(gate.register(95, at: 5))
        // The gate stays latched while the temperature remains critical.
        XCTAssertTrue(gate.register(94, at: 6))
        XCTAssertFalse(gate.register(70, at: 7))

        // A wake gap breaks streak continuity: stale critical samples cannot combine.
        var wakeGate = CriticalTemperatureGate()
        XCTAssertFalse(wakeGate.register(91, at: 0))
        XCTAssertFalse(wakeGate.register(92, at: 1))
        XCTAssertFalse(wakeGate.register(93, at: 10))
    }

    func testFanTargetStabilizerHoldsCoolingAndLimitsRpmChanges() {
        var stabilizer = FanTargetStabilizer()

        XCTAssertEqual(stabilizer.limitTargets([1_500, 1_500], at: 0), [1_500, 1_500])
        XCTAssertEqual(stabilizer.limitTargets([4_000, 4_000], at: 2), [1_700, 1_700])
        XCTAssertEqual(stabilizer.limitTargets([1_000, 1_000], at: 3), [1_500, 1_500])
        XCTAssertEqual(stabilizer.limitTargets([4_000, 4_000], at: 100), [1_700, 1_700])
        XCTAssertEqual(
            stabilizer.limitTargets([5_800, 5_800], at: 3.1, forceImmediate: true),
            [5_800, 5_800]
        )

        let safetyFan = FanSnapshot(
            index: 0,
            currentRPM: 2_000,
            minimumRPM: 1_500,
            maximumRPM: 6_000,
            targetRPM: 2_000,
            mode: 1
        )
        var safetyStabilizer = FanTargetStabilizer()
        XCTAssertEqual(safetyStabilizer.limitTargets([2_000], at: 0), [2_000])
        XCTAssertEqual(safetyStabilizer.forceMaximumTargets(for: [safetyFan], at: 1), [6_000])
        XCTAssertEqual(safetyStabilizer.limitTargets([2_000], at: 2), [5_800])
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
                FanControlCodec.encode(FanControlStatus(control: .noise(.ultra), fans: [validFan]))
            ),
            FanControlStatus(control: .noise(.ultra), fans: [validFan])
        )
        XCTAssertThrowsError(
            try FanControlCodec.decodeStatus(
                FanControlCodec.encode(FanControlStatus(control: .noise(.ultra), fans: [invalidFan]))
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

        let now = Date(timeIntervalSince1970: 1_000_000)
        let expired = directory.appendingPathComponent("expired.csv")
        try Data().write(to: expired)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-TemperatureCSVLog.retention - 1)],
            ofItemAtPath: expired.path
        )
        let unrelated = directory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelated)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-TemperatureCSVLog.retention - 1)],
            ofItemAtPath: unrelated.path
        )

        let log = TemperatureCSVLog(directoryURL: directory)
        log.record(targetCelsius: 40, actualCelsius: 45, at: now)
        log.record(targetCelsius: 40, actualCelsius: 44, at: now.addingTimeInterval(1))
        log.record(targetCelsius: 40, actualCelsius: 43, at: now.addingTimeInterval(2))

        XCTAssertFalse(FileManager.default.fileExists(atPath: expired.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        let csvFile = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .first { $0.pathExtension == "csv" }
        )
        let contents = try String(contentsOf: csvFile, encoding: .utf8)
        XCTAssertEqual(contents.split(separator: "\n").count, 4)
        XCTAssertTrue(contents.contains("40.0,45.0"))
        XCTAssertTrue(contents.contains("40.0,44.0"))
        XCTAssertTrue(contents.contains("40.0,43.0"))
        XCTAssertTrue(try log.contents().contains("target_celsius,actual_celsius"))
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
