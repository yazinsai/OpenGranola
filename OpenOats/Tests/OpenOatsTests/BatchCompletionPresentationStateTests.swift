import XCTest
@testable import OpenOatsKit

final class BatchCompletionPresentationStateTests: XCTestCase {

    func testObserveOnlyEmitsFirstCompletionUntilStatusChanges() {
        var state = BatchCompletionPresentationState()

        XCTAssertNil(state.observe(.loading(model: "Parakeet")))
        XCTAssertEqual(
            state.observe(.completed(sessionID: "session-1")),
            "session-1"
        )
        XCTAssertEqual(state.visibleCompletedSessionID, "session-1")

        XCTAssertNil(state.observe(.completed(sessionID: "session-1")))
        XCTAssertEqual(state.visibleCompletedSessionID, "session-1")
    }

    func testDismissedBannerDoesNotRetriggerWhileEngineStaysCompleted() {
        var state = BatchCompletionPresentationState()

        XCTAssertEqual(
            state.observe(.completed(sessionID: "session-1")),
            "session-1"
        )
        state.dismissCompletedBanner()

        XCTAssertNil(state.observe(.completed(sessionID: "session-1")))
        XCTAssertNil(state.visibleCompletedSessionID)
    }

    func testNewCompletionAfterDifferentStatusIsObserved() {
        var state = BatchCompletionPresentationState()

        XCTAssertEqual(
            state.observe(.completed(sessionID: "session-1")),
            "session-1"
        )
        XCTAssertNil(state.observe(.transcribing(progress: 0.5)))
        XCTAssertNil(state.visibleCompletedSessionID)

        XCTAssertEqual(
            state.observe(.completed(sessionID: "session-2")),
            "session-2"
        )
        XCTAssertEqual(state.visibleCompletedSessionID, "session-2")
    }
}
