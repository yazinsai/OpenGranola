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

    // Back-to-back meetings with the session spanning both: both events are
    // fully covered, so their coverage buckets tie, start proximity decides,
    // and the meeting the user pressed record for — the first — is kept. Raw
    // overlap seconds would have flipped this to the longer second meeting.
    func testIntervalMatchKeepsFirstOfBackToBackMeetingsWhenSessionSpansBoth() {
        let first = makeEvent(
            id: "first",
            title: "Standup",
            start: noon,
            durationMinutes: 30,
            isOnlineMeeting: true
        )
        let second = makeEvent(
            id: "second",
            title: "Planning",
            start: noon.addingTimeInterval(30 * 60),
            durationMinutes: 60,
            isOnlineMeeting: true
        )
        let session = DateInterval(start: noon, end: noon.addingTimeInterval(90 * 60))

        for candidates in [[first, second], [second, first]] {
            let best = CalendarEventMatcher.bestMatch(among: candidates, overlapping: session)
            XCTAssertEqual(best?.id, "first")
        }
    }

    // A 30-minute meeting the recording fully covers must not lose to a
    // three-hour meeting-like workshop the moment the session overruns by
    // five minutes: coverage is a fraction of each event's own duration
    // (meeting 1800/1800 → bucket 4, workshop 2100/10800 → bucket 1), not raw
    // overlap seconds (2100 > 1800 would pick the workshop).
    func testIntervalMatchPrefersContainedMeetingOverLongWorkshopOnOverrun() {
        let workshop = makeEvent(
            id: "workshop",
            title: "All-hands workshop",
            start: noon,
            durationMinutes: 180,
            isOnlineMeeting: true
        )
        let meeting = makeEvent(
            id: "meeting",
            title: "Weekly sync",
            start: noon,
            durationMinutes: 30,
            participants: [Participant(name: "Ada", email: "ada@example.com")]
        )
        let session = DateInterval(start: noon, end: noon.addingTimeInterval(35 * 60))

        for candidates in [[workshop, meeting], [meeting, workshop]] {
            let best = CalendarEventMatcher.bestMatch(among: candidates, overlapping: session)
            XCTAssertEqual(best?.id, "meeting")
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

    // Recording an in-person meeting nobody was invited to is still supported:
    // with no meeting-like candidate, the block the recording covers most
    // fully wins.
    func testIntervalMatchRanksPersonalBlocksByCoverageWhenNoCandidateLooksLikeAMeeting() {
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

    // MARK: - Final binding (finalize-time decision)

    func testFinalBindingRespectsUserChosenEvent() {
        let chosen = makeEvent(
            id: "chosen",
            title: "1:1",
            start: noon,
            durationMinutes: 15,
            isOnlineMeeting: true
        )
        let better = makeEvent(
            id: "better",
            title: "Quarterly Review",
            start: noon,
            durationMinutes: 60,
            participants: [Participant(name: "Ada", email: "ada@example.com")]
        )
        let session = DateInterval(start: noon, end: noon.addingTimeInterval(60 * 60))

        let result = CalendarEventMatcher.finalBinding(
            startBinding: chosen,
            isUserChosen: true,
            candidates: [better],
            interval: session
        )

        XCTAssertEqual(result?.id, "chosen")
    }

    // The incumbent competes under the same ranking instead of being replaced
    // by any challenger: a session recorded just before its standup overlaps
    // only a personal block, and the meeting-like binding from start must win.
    func testFinalBindingKeepsMeetingIncumbentOverNonMeetingChallenger() {
        let standup = makeEvent(
            id: "standup",
            title: "Standup",
            start: noon,
            durationMinutes: 15,
            isOnlineMeeting: true
        )
        let focus = makeEvent(
            id: "focus",
            title: "Focus time",
            start: noon.addingTimeInterval(-60 * 60),
            durationMinutes: 60
        )
        // Recorded from ten to two minutes before the hour: zero overlap with
        // the standup, full overlap with the personal block.
        let session = DateInterval(
            start: noon.addingTimeInterval(-10 * 60),
            end: noon.addingTimeInterval(-2 * 60)
        )

        let result = CalendarEventMatcher.finalBinding(
            startBinding: standup,
            isUserChosen: false,
            candidates: [focus],
            interval: session
        )

        XCTAssertEqual(result?.id, "standup")
    }

    func testFinalBindingRebindsToBetterOverlappingMeeting() {
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
        let session = DateInterval(
            start: noon.addingTimeInterval(-10 * 60),
            end: noon.addingTimeInterval(55 * 60)
        )

        let result = CalendarEventMatcher.finalBinding(
            startBinding: previous,
            isUserChosen: false,
            candidates: [previous, actual],
            interval: session
        )

        XCTAssertEqual(result?.id, "actual")
    }

    // A binding must not be lost to a meeting-like neighbour that only
    // touches the recording at its boundary — EventKit's inclusive predicate
    // bounds can admit zero-overlap events.
    func testFinalBindingIgnoresZeroOverlapChallengers() {
        let block = makeEvent(
            id: "block",
            title: "Working session",
            start: noon,
            durationMinutes: 60
        )
        let previous = makeEvent(
            id: "previous",
            title: "1:1",
            start: noon.addingTimeInterval(-15 * 60),
            durationMinutes: 15,
            isOnlineMeeting: true
        )
        let session = DateInterval(start: noon, end: noon.addingTimeInterval(40 * 60))

        let result = CalendarEventMatcher.finalBinding(
            startBinding: block,
            isUserChosen: false,
            candidates: [previous, block],
            interval: session
        )

        XCTAssertEqual(result?.id, "block")
    }

    func testFinalBindingDoesNotAttachNonMeetingEventToAdHocRecording() {
        let lunch = makeEvent(
            id: "lunch",
            title: "Lunch",
            start: noon,
            durationMinutes: 60
        )
        let session = DateInterval(start: noon, end: noon.addingTimeInterval(30 * 60))

        let result = CalendarEventMatcher.finalBinding(
            startBinding: nil,
            isUserChosen: false,
            candidates: [lunch],
            interval: session
        )

        XCTAssertNil(result)
    }

    func testFinalBindingAttachesMeetingEventToAdHocRecording() {
        let meeting = makeEvent(
            id: "meeting",
            title: "Standup",
            start: noon,
            durationMinutes: 30,
            isOnlineMeeting: true
        )
        let session = DateInterval(start: noon, end: noon.addingTimeInterval(30 * 60))

        let result = CalendarEventMatcher.finalBinding(
            startBinding: nil,
            isUserChosen: false,
            candidates: [meeting],
            interval: session
        )

        XCTAssertEqual(result?.id, "meeting")
    }

    func testFinalBindingKeepsIncumbentWhenNothingOverlaps() {
        let standup = makeEvent(
            id: "standup",
            title: "Standup",
            start: noon,
            durationMinutes: 15,
            isOnlineMeeting: true
        )
        let session = DateInterval(
            start: noon.addingTimeInterval(-10 * 60),
            end: noon.addingTimeInterval(-2 * 60)
        )

        let result = CalendarEventMatcher.finalBinding(
            startBinding: standup,
            isUserChosen: false,
            candidates: [],
            interval: session
        )

        XCTAssertEqual(result?.id, "standup")
    }
}
