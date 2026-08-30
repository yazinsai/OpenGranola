import Foundation

/// Bookkeeping that bounds notes-folder mirror work.
///
/// A mirror writes into a user-chosen folder that may live on a network mount.
/// When that mount is unreachable, a single attempt can block for the mount's
/// own timeout — tens of seconds for SMB. Retries are driven by ordinary app
/// activity (every recording start re-applies the notes folder), so without
/// bookkeeping the outstanding work for a permanently dead mount grows without
/// bound.
///
/// The ledger imposes two limits, which together bound the cost of a dead mount
/// to one blocked attempt per pending session per `retryBackoff`:
///
/// - **In-flight guard.** A session with a running attempt never starts a
///   second one. A request that arrives during an attempt is coalesced into a
///   single re-run.
/// - **Failure backoff.** A session whose last attempt failed is not retried
///   again until `retryBackoff` has elapsed.
///
/// Attempts carry a monotonically increasing id so a report can be matched to
/// the attempt that produced it. A report from a superseded attempt is ignored
/// — otherwise a slow success could clear the pending flag of a newer attempt
/// that actually failed, silently dropping the durable retry.
struct MirrorAttemptLedger: Sendable {
    /// Minimum interval between retries of a session whose last attempt failed.
    let retryBackoff: TimeInterval

    /// Sessions whose most recent mirror failed and which should be retried.
    private(set) var pendingSessionIDs: Set<String> = []

    private var nextAttemptID = 0
    /// Attempt id of the running attempt per session, if any.
    private var inFlightAttemptIDs: [String: Int] = [:]
    private var lastFailureDates: [String: Date] = [:]
    /// Sessions that asked for a mirror while one was already running.
    private var rescheduleRequests: Set<String> = []

    init(retryBackoff: TimeInterval) {
        self.retryBackoff = retryBackoff
    }

    /// Reserve an attempt for `sessionID`.
    /// - Returns: the attempt id, or `nil` when an attempt is already running.
    mutating func beginAttempt(sessionID: String) -> Int? {
        guard inFlightAttemptIDs[sessionID] == nil else { return nil }
        nextAttemptID += 1
        inFlightAttemptIDs[sessionID] = nextAttemptID
        return nextAttemptID
    }

    /// Record the outcome of an attempt.
    /// - Returns: `false` when the report comes from a superseded attempt, in
    ///   which case the caller must not touch any persisted state.
    mutating func finishAttempt(
        sessionID: String,
        attempt: Int,
        succeeded: Bool,
        now: Date = Date()
    ) -> Bool {
        guard inFlightAttemptIDs[sessionID] == attempt else { return false }
        inFlightAttemptIDs[sessionID] = nil
        if succeeded {
            pendingSessionIDs.remove(sessionID)
            lastFailureDates[sessionID] = nil
        } else {
            pendingSessionIDs.insert(sessionID)
            lastFailureDates[sessionID] = now
        }
        return true
    }

    /// Pending sessions the retry pass may drive right now: no attempt running,
    /// and outside the failure backoff window.
    func retryableSessionIDs(excluding excluded: String? = nil, now: Date = Date()) -> [String] {
        pendingSessionIDs
            .filter { sessionID in
                sessionID != excluded
                    && inFlightAttemptIDs[sessionID] == nil
                    && !isBackingOff(sessionID, now: now)
            }
            .sorted()
    }

    /// Note that a mirror was requested while an attempt was already running,
    /// so the newer content is re-mirrored once that attempt reports.
    mutating func requestReschedule(sessionID: String) {
        rescheduleRequests.insert(sessionID)
    }

    /// Consume any coalesced request recorded during the last attempt.
    mutating func takeRescheduleRequest(sessionID: String) -> Bool {
        rescheduleRequests.remove(sessionID) != nil
    }

    /// Seed pending sessions discovered by the startup scan.
    mutating func restorePending(_ sessionIDs: Set<String>) {
        pendingSessionIDs.formUnion(sessionIDs)
    }

    /// Drop every trace of a session, used when it is deleted so a dead mount
    /// cannot keep re-driving it. Any attempt still running is thereby
    /// superseded and its report ignored.
    mutating func forget(sessionID: String) {
        pendingSessionIDs.remove(sessionID)
        lastFailureDates[sessionID] = nil
        inFlightAttemptIDs[sessionID] = nil
        rescheduleRequests.remove(sessionID)
    }

    /// Drop the failure backoff for every session. Called when the notes folder
    /// changes destination: past failures say nothing about the new folder.
    mutating func clearFailureBackoff() {
        lastFailureDates.removeAll()
    }

    private func isBackingOff(_ sessionID: String, now: Date) -> Bool {
        guard let failedAt = lastFailureDates[sessionID] else { return false }
        return now.timeIntervalSince(failedAt) < retryBackoff
    }
}
