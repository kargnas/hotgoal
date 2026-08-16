import Dispatch
import Foundation
import XCTest
@testable import HotGoalCore

final class MainActorCallbackTests: XCTestCase {
    func testBackgroundInvocationWithoutArgumentsRunsOnMainActor() async {
        let delivered = expectation(description: "callback delivered")
        let callback: @Sendable () -> Void = MainActorCallback.make {
            XCTAssertTrue(Thread.isMainThread)
            delivered.fulfill()
        }

        DispatchQueue.global().async(execute: callback)

        await fulfillment(of: [delivered], timeout: 1)
    }

    func testBackgroundInvocationDeliversOneArgumentOnMainActor() async {
        let delivered = expectation(description: "callback delivered")
        let callback: @Sendable (Int) -> Void = MainActorCallback.make { number in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(number, 42)
            delivered.fulfill()
        }

        DispatchQueue.global().async {
            callback(42)
        }

        await fulfillment(of: [delivered], timeout: 1)
    }

    func testBackgroundInvocationDeliversArgumentsOnMainActor() async {
        let delivered = expectation(description: "callback delivered")
        let callback: @Sendable (Int, String) -> Void = MainActorCallback.make { number, text in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(number, 42)
            XCTAssertEqual(text, "ready")
            delivered.fulfill()
        }

        DispatchQueue.global().async {
            callback(42, "ready")
        }

        await fulfillment(of: [delivered], timeout: 1)
    }
}
