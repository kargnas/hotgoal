import XCTest
@testable import HotGoalCore

final class SavedControlRestoreTests: XCTestCase {
    func testRestoresSavedControlOnlyWhenHelperReportsNone() {
        XCTAssertEqual(
            SavedControlRestore.controlToApply(
                saved: .targetTemperature(50), reported: nil, fanCount: 2,
                commandInFlight: false, alreadyAttempted: false
            ),
            .targetTemperature(50)
        )
        // Presets are the user's last choice too.
        XCTAssertEqual(
            SavedControlRestore.controlToApply(
                saved: .noise(.quiet), reported: nil, fanCount: 2,
                commandInFlight: false, alreadyAttempted: false
            ),
            .noise(.quiet)
        )
        // System Default is already what a control-less helper does; sending it is redundant.
        XCTAssertNil(SavedControlRestore.controlToApply(
            saved: .noise(.systemDefault), reported: nil, fanCount: 2,
            commandInFlight: false, alreadyAttempted: false
        ))
        XCTAssertNil(SavedControlRestore.controlToApply(
            saved: nil, reported: nil, fanCount: 2,
            commandInFlight: false, alreadyAttempted: false
        ))
        // Never stomp a live controller.
        XCTAssertNil(SavedControlRestore.controlToApply(
            saved: .targetTemperature(50), reported: .targetTemperature(60), fanCount: 2,
            commandInFlight: false, alreadyAttempted: false
        ))
        // Fans unknown on the first status round-trip after connecting: wait, do not drop it.
        XCTAssertNil(SavedControlRestore.controlToApply(
            saved: .targetTemperature(50), reported: nil, fanCount: 0,
            commandInFlight: false, alreadyAttempted: false
        ))
        XCTAssertNil(SavedControlRestore.controlToApply(
            saved: .targetTemperature(50), reported: nil, fanCount: 2,
            commandInFlight: true, alreadyAttempted: false
        ))
        // One attempt per drop; a failed restore must not retry on every poll.
        XCTAssertNil(SavedControlRestore.controlToApply(
            saved: .targetTemperature(50), reported: nil, fanCount: 2,
            commandInFlight: false, alreadyAttempted: true
        ))
    }
}
