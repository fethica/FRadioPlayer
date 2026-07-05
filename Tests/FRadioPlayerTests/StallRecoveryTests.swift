//
//  StallRecoveryTests.swift
//  FRadioPlayerTests
//
//  The retry ladder in isolation, at test speed (50ms intervals).
//

import XCTest
@testable import FRadioPlayer

final class StallRecoveryTests: XCTestCase {

    func testClimbsAllIntervalsThenExhausts() {
        let recovery = StallRecovery(intervals: [0.05, 0.05, 0.05])
        var attempts = 0
        let exhausted = expectation(description: "exhausted")

        recovery.onAttempt = { attempts += 1; return false }
        recovery.onExhausted = { exhausted.fulfill() }

        recovery.start()
        wait(for: [exhausted], timeout: 2)
        XCTAssertEqual(attempts, 3)
        XCTAssertFalse(recovery.isActive)
    }

    func testSuccessfulAttemptStopsTheLadder() {
        let recovery = StallRecovery(intervals: [0.05, 0.05, 0.05])
        var attempts = 0
        let done = expectation(description: "second attempt succeeds")

        recovery.onAttempt = {
            attempts += 1
            if attempts == 2 { done.fulfill(); return true }
            return false
        }
        recovery.onExhausted = { XCTFail("must not exhaust after success") }

        recovery.start()
        wait(for: [done], timeout: 2)
        // Give a beat to prove no further attempts fire
        let quiet = expectation(description: "quiet")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { quiet.fulfill() }
        wait(for: [quiet], timeout: 1)
        XCTAssertEqual(attempts, 2)
        XCTAssertFalse(recovery.isActive)
    }

    func testCancelPreventsPendingAttempts() {
        let recovery = StallRecovery(intervals: [0.05])
        recovery.onAttempt = { XCTFail("canceled ladder must not attempt"); return false }
        recovery.onExhausted = { XCTFail("canceled ladder must not exhaust") }

        recovery.start()
        recovery.cancel()
        XCTAssertFalse(recovery.isActive)

        let quiet = expectation(description: "quiet")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { quiet.fulfill() }
        wait(for: [quiet], timeout: 1)
    }

    func testStartWhileActiveDoesNotResetTheClimb() {
        let recovery = StallRecovery(intervals: [0.05, 0.05])
        var attempts = 0
        let exhausted = expectation(description: "exhausted")

        recovery.onAttempt = {
            attempts += 1
            recovery.start() // repeated stall signals while climbing
            return false
        }
        recovery.onExhausted = { exhausted.fulfill() }

        recovery.start()
        wait(for: [exhausted], timeout: 2)
        XCTAssertEqual(attempts, 2, "re-entrant start must not add attempts")
    }
}
