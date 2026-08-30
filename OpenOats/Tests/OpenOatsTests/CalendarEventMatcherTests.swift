import XCTest
@testable import OpenOatsKit

final class CalendarEventMatcherTests: XCTestCase {
    private func makeEvent(
        id: String,
        title: String,
        start: Date,
        durationMinutes: Double,
        participants: [Participant] = [],
        isOnlineMeeting: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(durationMinutes * 60),
            calendarTitle: nil,
            organizer: nil,
            participants: participants,
            isOnlineMeeting: isOnlineMeeting,
            meetingURL: nil
        )
    }

    private let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // The regression this ranking exists for: a personal all-hands-free block and a
    // real meeting start on the same clock boundary, so start-distance ties and the
    // winner used to be whichever one EventKit listed first.
    func testPrefersInvitedMeetingWhenStartTimesTie() {
        let personalBlock = makeEvent(
            id: "personal",
            title: "Kids - Prep Group Class",
            start: noon,
            durationMinutes: 60
        )
        let realMeeting = makeEvent(
            id: "meeting",
            title: "Quarterly Review",
            start: noon,
            durationMinutes: 60,
            participants: [Participant(name: "Ada", email: "ada@example.com")]
        )

        // Both orderings must produce the same winner.
        for candidates in [[personalBlock, realMeeting], [realMeeting, personalBlock]] {
            let best = CalendarEventMatcher.bestMatch(
                among: candidates,
                at: noon.addingTimeInterval(103)
            )
            XCTAssertEqual(best?.id, "meeting")
        }
    }

    func testPrefersOnlineMeetingOverCloserPersonalBlock() {
        let personalBlock = makeEvent(
            id: "personal",
            title: "Focus time",
            start: noon,
            durationMinutes: 120
        )
        let onlineMeeting = makeEvent(
            id: "meeting",
            title: "Standup",
            start: noon.addingTimeInterval(10 * 60),
            durationMinutes: 15,
            isOnlineMeeting: true
        )

        let best = CalendarEventMatcher.bestMatch(among: [personalBlock, onlineMeeting], at: noon)

        XCTAssertEqual(best?.id, "meeting")
    }

    func testPrefersClosestStartAmongMeetings() {
        let earlier = makeEvent(
            id: "earlier",
            title: "Design Sync",
            start: noon.addingTimeInterval(-12 * 60),
            durationMinutes: 30,
            isOnlineMeeting: true
        )
        let closer = makeEvent(
            id: "closer",
            title: "1:1",
            start: noon.addingTimeInterval(-2 * 60),
            durationMinutes: 30,
            isOnlineMeeting: true
        )

        let best = CalendarEventMatcher.bestMatch(among: [earlier, closer], at: noon)

        XCTAssertEqual(best?.id, "closer")
    }

    func testPrefersShorterEventWhenMeetingsTieOnStart() {
        let long = makeEvent(
            id: "long",
            title: "Offsite",
            start: noon,
            durationMinutes: 240,
            isOnlineMeeting: true
        )
        let short = makeEvent(
            id: "short",
            title: "Kickoff",
            start: noon,
            durationMinutes: 30,
            isOnlineMeeting: true
        )

        let best = CalendarEventMatcher.bestMatch(among: [long, short], at: noon)

        XCTAssertEqual(best?.id, "short")
    }

    // Recording an in-person meeting that nobody was invited to is still supported:
    // with no meeting-like candidate, ranking falls back to closest start.
    func testFallsBackToClosestStartWhenNoCandidateLooksLikeAMeeting() {
        let far = makeEvent(id: "far", title: "Errand", start: noon.addingTimeInterval(-14 * 60), durationMinutes: 30)
        let near = makeEvent(id: "near", title: "Coffee", start: noon.addingTimeInterval(60), durationMinutes: 30)

        let best = CalendarEventMatcher.bestMatch(among: [far, near], at: noon)

        XCTAssertEqual(best?.id, "near")
    }

    func testReturnsNilWithoutCandidates() {
        XCTAssertNil(CalendarEventMatcher.bestMatch(among: [], at: noon))
    }

    func testIsLikelyMeetingRequiresInviteesOrOnlineHint() {
        let bare = makeEvent(id: "bare", title: "Block", start: noon, durationMinutes: 30)
        let invited = makeEvent(
            id: "invited",
            title: "Review",
            start: noon,
            durationMinutes: 30,
            participants: [Participant(name: nil, email: "ada@example.com")]
        )
        let online = makeEvent(id: "online", title: "Call", start: noon, durationMinutes: 30, isOnlineMeeting: true)

        XCTAssertFalse(CalendarEventMatcher.isLikelyMeeting(bare))
        XCTAssertTrue(CalendarEventMatcher.isLikelyMeeting(invited))
        XCTAssertTrue(CalendarEventMatcher.isLikelyMeeting(online))
    }
}
