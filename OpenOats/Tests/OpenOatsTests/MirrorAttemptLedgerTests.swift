import XCTest
@testable import OpenOatsKit

final class MirrorAttemptLedgerTests: XCTestCase {

    private let backoff: TimeInterval = 300
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeLedger() -> MirrorAttemptLedger {
        MirrorAttemptLedger(retryBackoff: backoff)
    }

    // MARK: - In-flight guard

    func testSecondAttemptIsRefusedWhileOneIsRunning() throws {
        var ledger = makeLedger()

        XCTAssertNotNil(ledger.beginAttempt(sessionID: "session_a"))
        XCTAssertNil(
            ledger.beginAttempt(sessionID: "session_a"),
            "A session with a running attempt must not start a second one"
        )
        // A different session is unaffected.
        XCTAssertNotNil(ledger.beginAttempt(sessionID: "session_b"))
    }

    func testAttemptCanRestartAfterTheRunningOneReports() throws {
        var ledger = makeLedger()

        let attempt = try XCTUnwrap(ledger.beginAttempt(sessionID: "session_a"))
        XCTAssertTrue(ledger.finishAttempt(sessionID: "session_a", attempt: attempt, succeeded: true, now: t0))
        XCTAssertNotNil(ledger.beginAttempt(sessionID: "session_a"))
    }

    func testRetryPassSkipsSessionsWithARunningAttempt() throws {
        var ledger = makeLedger()

        let attempt = try XCTUnwrap(ledger.beginAttempt(sessionID: "session_a"))
        XCTAssertTrue(ledger.finishAttempt(sessionID: "session_a", attempt: attempt, succeeded: false, now: t0))
        XCTAssertEqual(
            ledger.retryableSessionIDs(now: t0.addingTimeInterval(backoff + 1)),
            ["session_a"]
        )

        // Once the retry starts, the session drops out of the retryable set, so
        // repeated passes cannot pile attempts onto a blocked mount.
        XCTAssertNotNil(ledger.beginAttempt(sessionID: "session_a"))
        XCTAssertTrue(ledger.retryableSessionIDs(now: t0.addingTimeInterval(backoff + 1)).isEmpty)
    }

    // MARK: - Failure backoff

    func testFailedSessionIsNotRetriedInsideTheBackoffWindow() throws {
        var ledger = makeLedger()

        let attempt = try XCTUnwrap(ledger.beginAttempt(sessionID: "session_a"))
        XCTAssertTrue(ledger.finishAttempt(sessionID: "session_a", attempt: attempt, succeeded: false, now: t0))

        XCTAssertTrue(ledger.retryableSessionIDs(now: t0).isEmpty)
        XCTAssertTrue(ledger.retryableSessionIDs(now: t0.addingTimeInterval(backoff - 1)).isEmpty)
        XCTAssertEqual(ledger.retryableSessionIDs(now: t0.addingTimeInterval(backoff)), ["session_a"])
    }

    func testChangingTheNotesFolderClearsTheBackoff() throws {
        var ledger = makeLedger()

        let attempt = try XCTUnwrap(ledger.beginAttempt(sessionID: "session_a"))
        XCTAssertTrue(ledger.finishAttempt(sessionID: "session_a", attempt: attempt, succeeded: false, now: t0))
        XCTAssertTrue(ledger.retryableSessionIDs(now: t0).isEmpty)

        ledger.clearFailureBackoff()
        XCTAssertEqual(ledger.retryableSessionIDs(now: t0), ["session_a"])
    }

    func testExcludedSessionIsNotRetried() throws {
        var ledger = makeLedger()

        let attempt = try XCTUnwrap(ledger.beginAttempt(sessionID: "session_a"))
        XCTAssertTrue(ledger.finishAttempt(sessionID: "session_a", attempt: attempt, succeeded: false, now: t0))

        let later = t0.addingTimeInterval(backoff + 1)
        XCTAssertTrue(ledger.retryableSessionIDs(excluding: "session_a", now: later).isEmpty)
        XCTAssertEqual(ledger.retryableSessionIDs(excluding: "session_b", now: later), ["session_a"])
    }

    // MARK: - Attempt ordering

    func testLateReportFromSupersededAttemptIsIgnored() throws {
        var ledger = makeLedger()

        // Attempt 1 starts and blocks (e.g. on an unreachable mount).
        let first = try XCTUnwrap(ledger.beginAttempt(sessionID: "session_a"))

        // The session is deleted and re-created, which clears the reservation
        // and lets a second attempt start while the first is still running.
        ledger.forget(sessionID: "session_a")
        let second = try XCTUnwrap(ledger.beginAttempt(sessionID: "session_a"))
        XCTAssertNotEqual(first, second)

        // Attempt 2 finishes first, and fails.
        XCTAssertTrue(ledger.finishAttempt(sessionID: "session_a", attempt: second, succeeded: false, now: t0))
        XCTAssertEqual(ledger.pendingSessionIDs, ["session_a"])

        // Attempt 1 reports success afterwards. It is superseded, so it must
        // neither be accepted nor clear the pending flag attempt 2 set.
        XCTAssertFalse(
            ledger.finishAttempt(sessionID: "session_a", attempt: first, succeeded: true, now: t0),
            "A report from a superseded attempt must be rejected"
        )
        XCTAssertEqual(
            ledger.pendingSessionIDs,
            ["session_a"],
            "A superseded success must not drop the durable retry"
        )
    }

    func testForgettingASessionDropsPendingAndBackoffState() throws {
        var ledger = makeLedger()

        let attempt = try XCTUnwrap(ledger.beginAttempt(sessionID: "session_a"))
        XCTAssertTrue(ledger.finishAttempt(sessionID: "session_a", attempt: attempt, succeeded: false, now: t0))
        XCTAssertEqual(ledger.pendingSessionIDs, ["session_a"])

        ledger.forget(sessionID: "session_a")
        XCTAssertTrue(ledger.pendingSessionIDs.isEmpty)
        XCTAssertTrue(ledger.retryableSessionIDs(now: t0).isEmpty)
    }

    // MARK: - Coalescing

    func testRescheduleRequestIsDeliveredOnce() throws {
        var ledger = makeLedger()

        XCTAssertFalse(ledger.takeRescheduleRequest(sessionID: "session_a"))

        ledger.requestReschedule(sessionID: "session_a")
        ledger.requestReschedule(sessionID: "session_a")
        XCTAssertTrue(
            ledger.takeRescheduleRequest(sessionID: "session_a"),
            "Requests arriving during an attempt collapse into one re-run"
        )
        XCTAssertFalse(ledger.takeRescheduleRequest(sessionID: "session_a"))
    }

    // MARK: - Restore

    func testRestoredPendingSessionsAreImmediatelyRetryable() throws {
        var ledger = makeLedger()

        ledger.restorePending(["session_a", "session_b"])
        XCTAssertEqual(ledger.retryableSessionIDs(now: t0), ["session_a", "session_b"])
    }
}
