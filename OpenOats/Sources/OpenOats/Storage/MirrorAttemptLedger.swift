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
///
/// An attempt that was running when the notes folder changed is superseded in
/// the same way, because it wrote to the folder the user has since replaced:
/// its success says nothing about the new destination and its failure must not
/// back the new destination off.
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
    /// Attempts that were running when the notes folder changed, and so wrote
    /// to a destination the user has since replaced.
    private var staleDestinationAttemptIDs: Set<Int> = []

    /// What the caller must do with a reported attempt.
    enum AttemptOutcome: Equatable {
        /// The report belongs to an attempt this ledger no longer tracks, such
        /// as one for a session that was deleted. Touch no persisted state.
        case ignored
        /// The report describes the current destination. Persist the pending
        /// flag it implies.
        case recorded
        /// The attempt wrote to a destination that has since been replaced, so
        /// the current one still has no export. The session stays pending and
        /// must be re-driven against the new destination.
        case staleDestination
    }

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

    /// Record the outcome of an attempt, and free the session's attempt slot.
    /// - Returns: how the caller must treat the report.
    mutating func finishAttempt(
        sessionID: String,
        attempt: Int,
        succeeded: Bool,
        now: Date = Date()
    ) -> AttemptOutcome {
        guard inFlightAttemptIDs[sessionID] == attempt else { return .ignored }
        inFlightAttemptIDs[sessionID] = nil
        guard staleDestinationAttemptIDs.remove(attempt) == nil else {
            // Neither outcome describes the current notes folder, so record no
            // success and no backoff. The session keeps its durable retry.
            pendingSessionIDs.insert(sessionID)
            return .staleDestination
        }
        if succeeded {
            pendingSessionIDs.remove(sessionID)
            lastFailureDates[sessionID] = nil
        } else {
            pendingSessionIDs.insert(sessionID)
            lastFailureDates[sessionID] = now
        }
        return .recorded
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
        if let attempt = inFlightAttemptIDs[sessionID] {
            staleDestinationAttemptIDs.remove(attempt)
        }
        inFlightAttemptIDs[sessionID] = nil
        rescheduleRequests.remove(sessionID)
    }

    /// Note that the notes folder now points somewhere else.
    ///
    /// Past failures say nothing about the new folder, so the backoff is
    /// dropped. Every running attempt is writing to the old folder, so it is
    /// marked stale: its report leaves the session pending, and the caller
    /// re-drives it against the new destination. No attempt starts here, so a
    /// session still has at most one in flight.
    mutating func destinationChanged() {
        lastFailureDates.removeAll()
        staleDestinationAttemptIDs.formUnion(inFlightAttemptIDs.values)
    }

    private func isBackingOff(_ sessionID: String, now: Date) -> Bool {
        guard let failedAt = lastFailureDates[sessionID] else { return false }
        return now.timeIntervalSince(failedAt) < retryBackoff
    }
}
