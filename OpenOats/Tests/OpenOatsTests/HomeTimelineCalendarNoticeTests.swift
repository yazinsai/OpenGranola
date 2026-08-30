import XCTest
@testable import OpenOatsKit

final class HomeTimelineCalendarNoticeTests: XCTestCase {
    func testIntegrationOffWinsRegardlessOfAccessState() {
        XCTAssertEqual(
            HomeTimelineCalendarNotice.resolve(integrationEnabled: false, accessState: nil),
            .integrationOff
        )
        XCTAssertEqual(
            HomeTimelineCalendarNotice.resolve(integrationEnabled: false, accessState: .authorized),
            .integrationOff
        )
    }

    func testAuthorizedShowsNoNotice() {
        XCTAssertNil(
            HomeTimelineCalendarNotice.resolve(integrationEnabled: true, accessState: .authorized)
        )
    }

    func testDeniedShowsDeniedNotice() {
        XCTAssertEqual(
            HomeTimelineCalendarNotice.resolve(integrationEnabled: true, accessState: .denied),
            .accessDenied
        )
    }

    func testNotDeterminedShowsWaitingNotice() {
        XCTAssertEqual(
            HomeTimelineCalendarNotice.resolve(integrationEnabled: true, accessState: .notDetermined),
            .waitingForAccess
        )
    }

    func testMissingManagerShowsNoNotice() {
        // Regression: a nil CalendarManager (not yet built for a reshown window)
        // must not read as "waiting for calendar access".
        XCTAssertNil(
            HomeTimelineCalendarNotice.resolve(integrationEnabled: true, accessState: nil)
        )
    }
}
