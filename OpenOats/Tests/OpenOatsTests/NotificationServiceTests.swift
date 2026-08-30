import UserNotifications
import XCTest
@testable import OpenOatsKit

@MainActor
final class NotificationServiceTests: XCTestCase {

    func testBatchCompletedNotificationCopyUsesReTranscriptionWording() {
        XCTAssertEqual(NotificationService.batchCompletedTitle, "Re-transcription Complete")
        XCTAssertEqual(
            NotificationService.batchCompletedBody,
            "Re-transcription is complete. Your meeting transcript has been updated with higher-quality text."
        )
    }

    func testNotesFailedNotificationCopyPointsAtManualRegeneration() {
        XCTAssertEqual(NotificationService.notesFailedTitle, "Notes Generation Failed")
        XCTAssertEqual(
            NotificationService.notesFailedBody(reason: ""),
            "Meeting notes could not be generated. Open the meeting and choose Generate Notes to try again."
        )
    }

    func testNotesFailedNotificationCopyLeadsWithTheSpecificReason() {
        XCTAssertEqual(
            NotificationService.notesFailedBody(reason: "  OpenRouter API key required  "),
            "OpenRouter API key required Open the meeting and choose Generate Notes to try again."
        )
    }

    // MARK: - Response routing

    func testTapOnNotesFailedNotificationDoesNothing() {
        // A tap on a notification body arrives as the default action. Routing on
        // the action alone treated that as "start transcribing".
        XCTAssertEqual(
            NotificationService.route(
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                requestIdentifier: "notes-failed-session_2026-01-01_10-00-00"
            ),
            .none
        )
    }

    func testTapOnBatchCompletedNotificationDoesNothing() {
        XCTAssertEqual(
            NotificationService.route(
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                requestIdentifier: "batch-completed-session_2026-01-01_10-00-00"
            ),
            .none
        )
    }

    func testDismissOfANonDetectionNotificationDoesNothing() {
        XCTAssertEqual(
            NotificationService.route(
                actionIdentifier: UNNotificationDismissActionIdentifier,
                requestIdentifier: "notes-failed-session_2026-01-01_10-00-00"
            ),
            .none
        )
    }

    func testTapOnDetectionNotificationAccepts() {
        XCTAssertEqual(
            NotificationService.route(
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                requestIdentifier: NotificationService.detectionRequestID
            ),
            .accept
        )
    }

    func testDetectionActionsRouteToTheirCallbacks() {
        let detection = NotificationService.detectionRequestID

        XCTAssertEqual(
            NotificationService.route(actionIdentifier: NotificationService.startAction, requestIdentifier: detection),
            .accept
        )
        XCTAssertEqual(
            NotificationService.route(actionIdentifier: NotificationService.notMeetingAction, requestIdentifier: detection),
            .notAMeeting
        )
        XCTAssertEqual(
            NotificationService.route(actionIdentifier: NotificationService.ignoreAppAction, requestIdentifier: detection),
            .ignoreApp
        )
        XCTAssertEqual(
            NotificationService.route(actionIdentifier: NotificationService.dismissAction, requestIdentifier: detection),
            .dismiss
        )
        XCTAssertEqual(
            NotificationService.route(
                actionIdentifier: UNNotificationDismissActionIdentifier,
                requestIdentifier: detection
            ),
            .dismiss
        )
    }
}
