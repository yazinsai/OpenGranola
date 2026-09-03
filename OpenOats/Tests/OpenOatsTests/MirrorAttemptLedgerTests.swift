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
        XCTAssertEqual(ledger.finishAttempt(sessionID: "session_a", attempt: attempt, succeeded: true, now: t0), .recorded)
        XCTAssertNotNil(ledger.beginAttempt(sessionID: "session_a"))
    }

    func testRetryPassSkipsSessionsWithARunningAttempt() throws {
        var ledger = makeLedger()

        let attempt = try XCTUnwrap(ledger.beginAttempt(sessionID: "session_a"))
        XCTAssertEqual(ledger.finishAttempt(sessionID: "session_a", attempt: attempt, succeeded: false, now: t0), .recorded)
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
        XCTAssertEqual(ledger.finishAttempt(sessionID: "session_a", attempt: attempt, succeeded: false, now: t0), .recorded)

        XCTAssertTrue(ledger.retryableSessionIDs(now: t0).isEmpty)
        XCTAssertTrue(ledger.retryableSessionIDs(now: t0.addingTimeInterval(backoff - 1)).isEmpty)
        XCTAssertEqual(ledger.retryableSessionIDs(now: t0.addingTimeInterval(backoff)), ["session_a"])
    }

    func testChangingTheNotesFolderClearsTheBackoff() throws {
        var ledger = makeLedger()

        let attempt = try XCTUnwrap(ledger.beginAttempt(sessionID: "session_a"))
        XCTAssertEqual(ledger.finishAttempt(sessionID: "session_a", attempt: attempt, succeeded: false, now: t0), .recorded)
        XCTAssertTrue(ledger.retryableSessionIDs(now: t0).isEmpty)

        ledger.destinationChanged()
        XCTAssertEqual(ledger.retryableSessionIDs(now: t0), ["session_a"])
    }

    // MARK: - Destination changes under a running attempt

    func testSuccessAgainstTheOldFolderKeepsTheSessionPending() throws {
        var ledger = makeLedger()

        // An attempt is running against the old folder when the user picks a
        // new one. The retry pass cannot drive the session while that attempt
        // holds the slot, so the report itself has to hand it over.
        let attempt = try XCTUnwrap(ledger.beginAttempt(sessionID: "session_a"))
        ledger.destinationChanged()
        XCTAssertTrue(ledger.retryableSessionIDs(now: t0).isEmpty)

        XCTAssertEqual(
            ledger.finishAttempt(sessionID: "session_a", attempt: attempt, succeeded: true, now: t0),
            .staleDestination,
            "A success against the replaced folder says nothing about the new one"
        )
        XCTAssertEqual(
            ledger.pendingSessionIDs,
            ["session_a"],
            "The new destination has no export, so the session stays pending"
        )
        XCTAssertEqual(ledger.retryableSessionIDs(now: t0), ["session_a"])
    }

    func testFailureAgainstTheOldFolderDoesNotBackOffTheNewOne() throws {
        var ledger = makeLedger()

        let attempt = try XCTUnwrap(ledger.beginAttempt(sessionID: "session_a"))
        ledger.destinationChanged()

        XCTAssertEqual(
            ledger.finishAttempt(sessionID: "session_a", attempt: attempt, succeeded: false, now: t0),
            .staleDestination
        )
        XCTAssertEqual(
            ledger.retryableSessionIDs(now: t0),
            ["session_a"],
            "A dead old mount must not hold the new folder off for a backoff interval"
        )
    }

    func testOnlyOneAttemptRunsWhileTheDestinationChanges() throws {
        var ledger = makeLedger()

        let attempt = try XCTUnwrap(ledger.beginAttempt(sessionID: "session_a"))
        ledger.destinationChanged()
        ledger.destinationChanged()

        // Repeated changes cannot stack attempts onto a blocked mount: the slot
        // stays taken until the running attempt reports.
        XCTAssertNil(ledger.beginAttempt(sessionID: "session_a"))
        XCTAssertTrue(ledger.retryableSessionIDs(now: t0).isEmpty)

        XCTAssertEqual(
            ledger.finishAttempt(sessionID: "session_a", attempt: attempt, succeeded: false, now: t0),
            .staleDestination
        )
        XCTAssertNotNil(ledger.beginAttempt(sessionID: "session_a"))
    }

    func testAttemptStartedAfterTheChangeIsRecordedNormally() throws {
        var ledger = makeLedger()

        ledger.destinationChanged()
        let attempt = try XCTUnwrap(ledger.beginAttempt(sessionID: "session_a"))
        XCTAssertEqual(
            ledger.finishAttempt(sessionID: "session_a", attempt: attempt, succeeded: false, now: t0),
            .recorded,
            "An attempt started against the new folder reports on the new folder"
        )
        XCTAssertTrue(
            ledger.retryableSessionIDs(now: t0.addingTimeInterval(backoff - 1)).isEmpty,
            "Its failure backs the session off as usual"
        )
    }

    func testExcludedSessionIsNotRetried() throws {
        var ledger = makeLedger()

        let attempt = try XCTUnwrap(ledger.beginAttempt(sessionID: "session_a"))
        XCTAssertEqual(ledger.finishAttempt(sessionID: "session_a", attempt: attempt, succeeded: false, now: t0), .recorded)

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
        XCTAssertEqual(ledger.finishAttempt(sessionID: "session_a", attempt: second, succeeded: false, now: t0), .recorded)
        XCTAssertEqual(ledger.pendingSessionIDs, ["session_a"])

        // Attempt 1 reports success afterwards. It is superseded, so it must
        // neither be accepted nor clear the pending flag attempt 2 set.
        XCTAssertEqual(
            ledger.finishAttempt(sessionID: "session_a", attempt: first, succeeded: true, now: t0),
            .ignored,
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
        XCTAssertEqual(ledger.finishAttempt(sessionID: "session_a", attempt: attempt, succeeded: false, now: t0), .recorded)
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
