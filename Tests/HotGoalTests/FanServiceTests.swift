import XCTest
@testable import HotGoalCore

final class FanServiceTests: XCTestCase {
    func testTemperatureGapDuringSleepKeepsTargetControl() throws {
        let hardware = FakeFanHardware()
        let service = FanService(hardware: hardware)
        let target = FanControl.targetTemperature(60)
        try service.setControl(FanControlCodec.encode(target)).get()

        // Sleep and wake can leave the CPU temperature keys unreadable.
        hardware.temperature = nil
        service.reconcile()
        XCTAssertEqual(try FanControlCodec.decodeStatus(service.status().get()).control, target)
        // macOS drives the fans while the helper cannot measure.
        XCTAssertEqual(hardware.automaticRestores, 1)

        // Once readings return, the helper resumes the target without a new command from the app.
        hardware.temperature = 75
        for _ in 0..<TemperatureAverage.sampleCount { service.reconcile() }
        XCTAssertFalse(hardware.writtenTargets.isEmpty)
    }

    func testCriticalTemperatureRampsFansInsteadOfJumpingToMaximum() throws {
        let hardware = FakeFanHardware()
        hardware.temperature = 95
        let service = FanService(hardware: hardware)
        try service.setControl(FanControlCodec.encode(.targetTemperature(60))).get()

        // The third consecutive critical sample trips the 90 °C override. The fake fan runs at
        // 2,000 RPM with a 5,000 RPM maximum, so the first override write must land in between.
        service.reconcile()
        service.reconcile()
        let firstOverrideWrite = try XCTUnwrap(hardware.writtenTargets.last?.first)
        XCTAssertGreaterThan(firstOverrideWrite, 2000)
        XCTAssertLessThan(firstOverrideWrite, 5000)
    }
}

private final class FakeFanHardware: FanHardware {
    var temperature: Double? = 70
    private(set) var automaticRestores = 0
    private(set) var writtenTargets: [[Int]] = []

    func cpuAverageTemperature() -> Double? { temperature }

    func fanSnapshots() throws -> [FanSnapshot] {
        [FanSnapshot(index: 0, currentRPM: 2000, minimumRPM: 1000, maximumRPM: 5000, targetRPM: 2000, mode: 1)]
    }

    func setFanPercentage(_ percentage: Int) throws {}

    func setFanTargets(_ targets: [Int]) throws { writtenTargets.append(targets) }

    func restoreAutomatic() throws { automaticRestores += 1 }
}
