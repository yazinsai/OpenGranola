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
            NotificationService.notesFailedBody,
            "Meeting notes could not be generated. Open the meeting and choose Generate Notes to try again."
        )
    }
}
