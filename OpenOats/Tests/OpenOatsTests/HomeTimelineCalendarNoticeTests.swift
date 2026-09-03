import XCTest
@testable import OpenOatsKit

final class HomeTimelineCalendarNoticeTests: XCTestCase {
    func testIntegrationOffWinsRegardlessOfAccessState() {
        let states: [CalendarManager.AccessState?] = [nil, .authorized, .denied, .notDetermined]
        for state in states {
            XCTAssertEqual(
                HomeTimelineCalendarNotice.resolve(integrationEnabled: false, accessState: state),
                .integrationOff,
                "integration off must win for access state \(String(describing: state))"
            )
        }
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

    // MARK: - Empty timeline copy

    private func copy(
        integrationEnabled: Bool,
        accessState: CalendarManager.AccessState?
    ) -> (title: String, description: String) {
        HomeTimelineCalendarNotice.emptyTimelineCopy(
            integrationEnabled: integrationEnabled,
            accessState: accessState
        )
    }

    func testEmptyCopyMentionsIntegrationOffWhenDisabled() {
        let states: [CalendarManager.AccessState?] = [nil, .authorized, .denied, .notDetermined]
        for state in states {
            XCTAssertEqual(
                copy(integrationEnabled: false, accessState: state).description,
                "Recorded meetings will appear here even while Calendar integration is off."
            )
        }
    }

    func testEmptyCopyIsPermissionFlavouredOnlyForRealPermissionStates() {
        let permissionFlavoured = "Saved meetings will appear here even before Calendar access is available."
        XCTAssertEqual(
            copy(integrationEnabled: true, accessState: .denied).description,
            permissionFlavoured
        )
        XCTAssertEqual(
            copy(integrationEnabled: true, accessState: .notDetermined).description,
            permissionFlavoured
        )
    }

    func testEmptyCopyIsNeutralWhenManagerIsMissing() {
        // Regression: a nil CalendarManager is an internal condition. It must not
        // produce copy that blames a pending Calendar permission decision.
        let neutral = (
            title: "No meetings yet",
            description: "Upcoming calendar meetings and saved history will appear here."
        )
        XCTAssertEqual(copy(integrationEnabled: true, accessState: nil).title, neutral.title)
        XCTAssertEqual(copy(integrationEnabled: true, accessState: nil).description, neutral.description)
        XCTAssertEqual(copy(integrationEnabled: true, accessState: .authorized).title, neutral.title)
        XCTAssertEqual(copy(integrationEnabled: true, accessState: .authorized).description, neutral.description)
    }

    func testEmptyCopyNeverDriftsFromNotice() {
        // The copy must be a function of the resolved notice, never an independent
        // reading of the same inputs.
        let states: [CalendarManager.AccessState?] = [nil, .authorized, .denied, .notDetermined]
        for enabled in [true, false] {
            for state in states {
                let notice = HomeTimelineCalendarNotice.resolve(
                    integrationEnabled: enabled,
                    accessState: state
                )
                let description = copy(integrationEnabled: enabled, accessState: state).description
                let mentionsAccess = description.contains("Calendar access")
                XCTAssertEqual(
                    mentionsAccess,
                    notice == .accessDenied || notice == .waitingForAccess,
                    "copy for notice \(String(describing: notice)) disagrees with the notice"
                )
            }
        }
    }
}
