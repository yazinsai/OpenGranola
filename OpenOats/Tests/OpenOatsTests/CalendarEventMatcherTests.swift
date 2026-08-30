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

    // MARK: - Interval matching (finalize-time re-resolution)

    // The regression interval ranking exists for: a recording that starts in
    // the tail of the previous event binds to that event at start, because at
    // minute zero the previous event is the closer candidate. Once the real
    // interval is known, the meeting that actually spans the recording wins.
    func testIntervalMatchRebindsSessionThatStartedDuringThePreviousEvent() {
        let previous = makeEvent(
            id: "previous",
            title: "1:1",
            start: noon.addingTimeInterval(-15 * 60),
            durationMinutes: 15,
            isOnlineMeeting: true
        )
        let actual = makeEvent(
            id: "actual",
            title: "Quarterly Review",
            start: noon,
            durationMinutes: 60,
            participants: [Participant(name: "Ada", email: "ada@example.com")]
        )
        // Recording started ten minutes before the hour and ran to :55.
        let sessionStart = noon.addingTimeInterval(-10 * 60)
        let session = DateInterval(start: sessionStart, end: noon.addingTimeInterval(55 * 60))

        // At the instant the recording started, the previous event was the
        // closer candidate — this is the binding start-time matching gets wrong.
        XCTAssertEqual(
            CalendarEventMatcher.bestMatch(among: [previous, actual], at: sessionStart)?.id,
            "previous"
        )

        // Both orderings must produce the same winner.
        for candidates in [[previous, actual], [actual, previous]] {
            let best = CalendarEventMatcher.bestMatch(among: candidates, overlapping: session)
            XCTAssertEqual(best?.id, "actual")
        }
    }

    func testIntervalMatchPrefersEventCoveringTheSessionOverOneSharingItsStart() {
        let shortBlock = makeEvent(
            id: "short",
            title: "Standup",
            start: noon,
            durationMinutes: 15,
            isOnlineMeeting: true
        )
        let fullMeeting = makeEvent(
            id: "full",
            title: "Design Review",
            start: noon,
            durationMinutes: 50,
            isOnlineMeeting: true
        )
        let session = DateInterval(start: noon, end: noon.addingTimeInterval(50 * 60))

        for candidates in [[shortBlock, fullMeeting], [fullMeeting, shortBlock]] {
            let best = CalendarEventMatcher.bestMatch(among: candidates, overlapping: session)
            XCTAssertEqual(best?.id, "full")
        }
    }

    // Meeting-likeness stays the first key: a personal block that contains
    // more of the recording still loses to a real meeting that overlaps it
    // only partially.
    func testIntervalMatchKeepsMeetingLikenessAheadOfOverlap() {
        let personalBlock = makeEvent(
            id: "personal",
            title: "Focus time",
            start: noon,
            durationMinutes: 120
        )
        let meeting = makeEvent(
            id: "meeting",
            title: "Standup",
            start: noon.addingTimeInterval(30 * 60),
            durationMinutes: 30,
            isOnlineMeeting: true
        )
        let session = DateInterval(start: noon, end: noon.addingTimeInterval(90 * 60))

        for candidates in [[personalBlock, meeting], [meeting, personalBlock]] {
            let best = CalendarEventMatcher.bestMatch(among: candidates, overlapping: session)
            XCTAssertEqual(best?.id, "meeting")
        }
    }

    func testIntervalMatchFallsBackToStartProximityWhenOverlapsTie() {
        let outer = makeEvent(
            id: "outer",
            title: "Team block",
            start: noon,
            durationMinutes: 60,
            isOnlineMeeting: true
        )
        let inner = makeEvent(
            id: "inner",
            title: "Check-in",
            start: noon.addingTimeInterval(5 * 60),
            durationMinutes: 40,
            isOnlineMeeting: true
        )
        // Both events cover the whole recording, so overlaps tie and the
        // closer start wins.
        let session = DateInterval(
            start: noon.addingTimeInterval(10 * 60),
            end: noon.addingTimeInterval(40 * 60)
        )

        for candidates in [[outer, inner], [inner, outer]] {
            let best = CalendarEventMatcher.bestMatch(among: candidates, overlapping: session)
            XCTAssertEqual(best?.id, "inner")
        }
    }

    // Recording an in-person meeting nobody was invited to is still supported:
    // with no meeting-like candidate, the block that contains most of the
    // recording wins.
    func testIntervalMatchRanksPersonalBlocksByOverlapWhenNoCandidateLooksLikeAMeeting() {
        let errand = makeEvent(
            id: "errand",
            title: "Errand",
            start: noon.addingTimeInterval(-20 * 60),
            durationMinutes: 30
        )
        let block = makeEvent(
            id: "block",
            title: "Working session",
            start: noon,
            durationMinutes: 60
        )
        let session = DateInterval(
            start: noon.addingTimeInterval(-5 * 60),
            end: noon.addingTimeInterval(50 * 60)
        )

        for candidates in [[errand, block], [block, errand]] {
            let best = CalendarEventMatcher.bestMatch(among: candidates, overlapping: session)
            XCTAssertEqual(best?.id, "block")
        }
    }

    func testIntervalMatchReturnsNilWithoutCandidates() {
        XCTAssertNil(CalendarEventMatcher.bestMatch(
            among: [],
            overlapping: DateInterval(start: noon, duration: 30 * 60)
        ))
    }
}
