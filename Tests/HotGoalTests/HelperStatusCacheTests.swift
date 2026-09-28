import XCTest
@testable import HotGoalCore

final class HelperStatusCacheTests: XCTestCase {
    func testRefreshLoopQueriesOncePerLifetime() {
        var cache = HelperStatusCache<Int>()
        var queries = 0
        // One minute of the app's 0.5 s refresh loop, reading the status four times a tick.
        for tick in 0..<120 {
            for _ in 0..<4 {
                _ = cache.status(now: Double(tick) * 0.5) {
                    queries += 1
                    return 1
                }
            }
        }
        XCTAssertEqual(queries, 2)
    }

    func testInvalidateForcesTheNextReadToQuery() {
        var cache = HelperStatusCache<Int>()
        XCTAssertEqual(cache.status(now: 0) { 2 }, 2)
        XCTAssertEqual(cache.status(now: 1) { 1 }, 2)
        cache.invalidate()
        XCTAssertEqual(cache.status(now: 1) { 1 }, 1)
    }
}
