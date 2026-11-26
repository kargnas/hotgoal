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
