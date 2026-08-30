import AppKit
import EventKit
import Foundation

/// Wraps EKEventStore to look up calendar events overlapping the current time.
/// All access is gated behind the `calendarIntegrationEnabled` setting — the app
/// only requests calendar permission when the user explicitly enables the feature.
@MainActor
@Observable
final class CalendarManager {
    @ObservationIgnored private let store = EKEventStore()

    enum AccessState {
        case notDetermined
        case authorized
        case denied
    }

    struct AvailableCalendar: Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        let sourceTitle: String?
        let colorHex: String?
    }

    /// Current authorization status, observed at init and after requesting access.
    private(set) var accessState: AccessState

    init() {
        self.accessState = Self.currentAccessState()
    }

    // MARK: - Authorization

    /// Re-reads the current TCC authorization status and updates `accessState` if it has drifted.
    /// Safe to call at any time — never shows a system dialog.
    func refreshFromSystem() {
        let current = Self.currentAccessState()
        if current != accessState {
            accessState = current
        }
    }

    /// Request calendar access. Returns true if authorized.
    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            accessState = granted ? .authorized : .denied
            return granted
        } catch {
            accessState = .denied
            return false
        }
    }

    // MARK: - Event Lookup

    /// Find the calendar event the given date (typically now) most likely belongs to.
    /// Real meetings are preferred over personal blocks — see `CalendarEventMatcher`.
    /// Returns nil if no event is found or access is not authorized.
    func currentEvent(
        at date: Date = Date(),
        excludingCalendarIDs: [String] = []
    ) -> CalendarEvent? {
        guard accessState == .authorized else { return nil }
        let calendars = eventCalendars(excludingCalendarIDs: Set(excludingCalendarIDs))
        guard !calendars.isEmpty else { return nil }

        // Look for events in a window: started up to 15 min ago through 15 min from now
        let windowStart = date.addingTimeInterval(-15 * 60)
        let windowEnd = date.addingTimeInterval(15 * 60)

        let predicate = store.predicateForEvents(
            withStart: windowStart,
            end: windowEnd,
            calendars: calendars
        )
        let candidates = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { CalendarEvent(from: $0) }

        return CalendarEventMatcher.bestMatch(among: candidates, at: date)
    }

    /// All non-all-day calendar events overlapping the given interval, for
    /// finalize-time re-resolution of a finished recording's binding. The
    /// ranking itself lives in `CalendarEventMatcher.finalBinding` so it can
    /// be tested without an `EKEventStore`.
    /// Returns an empty array if access is not authorized.
    func events(
        overlapping interval: DateInterval,
        excludingCalendarIDs: [String] = []
    ) -> [CalendarEvent] {
        guard accessState == .authorized else { return [] }
        let calendars = eventCalendars(excludingCalendarIDs: Set(excludingCalendarIDs))
        guard !calendars.isEmpty else { return [] }

        let predicate = store.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: calendars
        )
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { CalendarEvent(from: $0) }
    }

    /// Upcoming calendar events starting within the given time window, ordered by start date.
    /// Returns an empty array if access is not authorized.
    func upcomingEvents(
        from date: Date = Date(),
        within window: TimeInterval = 12 * 60 * 60,
        limit: Int = 5,
        excludingCalendarIDs: [String] = []
    ) -> [CalendarEvent] {
        guard accessState == .authorized else { return [] }
        let calendars = eventCalendars(excludingCalendarIDs: Set(excludingCalendarIDs))
        guard !calendars.isEmpty else { return [] }

        let windowEnd = date.addingTimeInterval(window)
        let predicate = store.predicateForEvents(
            withStart: date,
            end: windowEnd,
            calendars: calendars
        )
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate >= date }
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)

        return events.map { CalendarEvent(from: $0) }
    }

    /// Calendar events occurring on the same local day as the given date, ordered by start date.
    /// Returns an empty array if access is not authorized.
    func events(
        onSameDayAs date: Date = Date(),
        excludingCalendarIDs: [String] = []
    ) -> [CalendarEvent] {
        guard accessState == .authorized else { return [] }
        let calendars = eventCalendars(excludingCalendarIDs: Set(excludingCalendarIDs))
        guard !calendars.isEmpty else { return [] }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        let predicate = store.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: calendars
        )
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        return events.map { CalendarEvent(from: $0) }
    }

    // MARK: - Helpers

    func availableCalendars() -> [AvailableCalendar] {
        guard accessState == .authorized else { return [] }
        return eventCalendars()
            .map { calendar in
                AvailableCalendar(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source.title.nilIfBlank,
                    colorHex: CalendarColorCodec.hexString(from: calendar.cgColor)
                )
            }
            .sorted { lhs, rhs in
                let lhsSource = lhs.sourceTitle ?? ""
                let rhsSource = rhs.sourceTitle ?? ""
                let sourceComparison = lhsSource.localizedCaseInsensitiveCompare(rhsSource)
                if sourceComparison != .orderedSame {
                    return sourceComparison == .orderedAscending
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private func eventCalendars(excludingCalendarIDs: Set<String> = []) -> [EKCalendar] {
        store.calendars(for: .event)
            .filter { !excludingCalendarIDs.contains($0.calendarIdentifier) }
    }

    private static func currentAccessState() -> AccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return .authorized
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - EKEvent → CalendarEvent

extension CalendarEvent {
    init(from event: EKEvent) {
        let meetingURL = CalendarMeetingLinkResolver.meetingURL(
            rawURL: event.url,
            notes: event.notes,
            location: event.location
        )
        self.init(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Untitled Event",
            startDate: event.startDate,
            endDate: event.endDate,
            externalIdentifier: event.calendarItemExternalIdentifier,
            calendarID: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            calendarColorHex: CalendarColorCodec.hexString(from: event.calendar.cgColor),
            organizer: event.organizer?.name,
            participants: (event.attendees ?? []).map { Participant(from: $0) },
            isOnlineMeeting: CalendarMeetingLinkResolver.isOnlineMeeting(
                rawURL: event.url,
                notes: event.notes,
                location: event.location
            ),
            meetingURL: meetingURL
        )
    }
}

extension Participant {
    init(from attendee: EKParticipant) {
        self.init(
            name: attendee.name,
            email: attendee.url.absoluteString
                .replacingOccurrences(of: "mailto:", with: "")
        )
    }
}

// MARK: - Candidate Ranking

/// Picks which of several overlapping calendar events a recording belongs to.
///
/// Start-time proximity alone is not enough. Personal blocks — family events,
/// focus time, reminders — routinely start on the same clock boundary as a real
/// meeting, and when the distances tie the winner is whatever order EventKit
/// happened to return. Events that carry invitees or a conference link are
/// ranked ahead of those that carry neither, so a genuine meeting always beats a
/// solo block that merely overlaps it.
enum CalendarEventMatcher {
    /// True when the event looks like something worth recording: it has invitees,
    /// or a join link / online-meeting hint.
    static func isLikelyMeeting(_ event: CalendarEvent) -> Bool {
        event.isOnlineMeeting || !event.participants.isEmpty
    }

    /// Returns the best match for `date`, or nil when there are no candidates.
    static func bestMatch(among events: [CalendarEvent], at date: Date) -> CalendarEvent? {
        events.min { lhs, rhs in
            sortKey(for: lhs, at: date) < sortKey(for: rhs, at: date)
        }
    }

    /// Returns the best match for a finished recording spanning `interval`, or
    /// nil when there are no candidates. Unlike `bestMatch(among:at:)`, which
    /// ranks by proximity to a single instant, this ranks by how much of each
    /// event the recording covers, so the meeting the session actually spans
    /// outranks one it only clipped.
    static func bestMatch(
        among events: [CalendarEvent],
        overlapping interval: DateInterval
    ) -> CalendarEvent? {
        events.min { lhs, rhs in
            sortKey(for: lhs, overlapping: interval) < sortKey(for: rhs, overlapping: interval)
        }
    }

    /// The calendar event a finished recording should be bound to, given the
    /// binding made at session start and the events overlapping the
    /// recording's real interval.
    ///
    /// The start-time binding competes with the challengers under the same
    /// ranking, so a meeting-like incumbent can never lose to a personal
    /// block that merely overlaps more of the recording. An event the user
    /// picked explicitly is never replaced. Candidates that do not actually
    /// overlap the interval are dropped (EventKit's predicate bounds are
    /// inclusive, so a back-to-back neighbour can slip in with zero overlap)
    /// — but never the incumbent, which competes regardless. A recording with
    /// no start-time binding only gains one when the winner looks like a real
    /// meeting: an ad-hoc recording must not be relocated or re-titled by the
    /// personal block that happens to contain it.
    static func finalBinding(
        startBinding: CalendarEvent?,
        isUserChosen: Bool,
        candidates: [CalendarEvent],
        interval: DateInterval
    ) -> CalendarEvent? {
        if isUserChosen { return startBinding }

        var pool = candidates.filter { overlapDuration(of: $0, with: interval) > 0 }
        if let startBinding, !pool.contains(where: { $0.id == startBinding.id }) {
            pool.append(startBinding)
        }

        guard let winner = bestMatch(among: pool, overlapping: interval) else {
            return startBinding
        }
        if startBinding == nil, !isLikelyMeeting(winner) {
            return nil
        }
        return winner
    }

    /// Lexicographic ranking key, lowest wins: real meetings first, then the
    /// closest start, then the shorter event. `startDate` keeps ties deterministic
    /// rather than dependent on EventKit's ordering.
    private static func sortKey(
        for event: CalendarEvent,
        at date: Date
    ) -> (Int, TimeInterval, TimeInterval, Date) {
        (
            isLikelyMeeting(event) ? 0 : 1,
            abs(event.startDate.timeIntervalSince(date)),
            event.endDate.timeIntervalSince(event.startDate),
            event.startDate
        )
    }

    /// Lexicographic ranking key for interval matching, lowest wins: real
    /// meetings first, then the event most fully covered by the recording,
    /// then the closest start, then the shorter event. `startDate` keeps ties
    /// deterministic rather than dependent on EventKit's ordering.
    private static func sortKey(
        for event: CalendarEvent,
        overlapping interval: DateInterval
    ) -> (Int, Int, TimeInterval, TimeInterval, Date) {
        (
            isLikelyMeeting(event) ? 0 : 1,
            -coverageBucket(of: event, within: interval),
            abs(event.startDate.timeIntervalSince(interval.start)),
            event.endDate.timeIntervalSince(event.startDate),
            event.startDate
        )
    }

    /// How much of the event the recording covers, as a fraction of the
    /// event's own duration, quantized to five buckets (0...4). The fraction
    /// keeps a fully-covered 30-minute meeting ahead of a three-hour block
    /// the recording merely dips into (raw overlap seconds would prefer the
    /// block), and the quantization stops one extra second of overlap from
    /// flipping the winner — near-ties fall through to start proximity.
    private static func coverageBucket(
        of event: CalendarEvent,
        within interval: DateInterval
    ) -> Int {
        let duration = event.endDate.timeIntervalSince(event.startDate)
        guard duration > 0 else { return 0 }
        let fraction = overlapDuration(of: event, with: interval) / duration
        return Int((fraction * 4).rounded())
    }

    private static func overlapDuration(
        of event: CalendarEvent,
        with interval: DateInterval
    ) -> TimeInterval {
        guard event.endDate > event.startDate else { return 0 }
        let eventInterval = DateInterval(start: event.startDate, end: event.endDate)
        return interval.intersection(with: eventInterval)?.duration ?? 0
    }
}

enum CalendarMeetingLinkResolver {
    private static let hostHints = [
        "zoom.us",
        "teams.microsoft",
        "teams.live",
        "meet.google",
        "webex",
        "whereby.com",
        "around.co",
        "jitsi",
        "chime.aws",
        "gotomeeting",
        "bluejeans",
        "facetime",
    ]

    private static let textHints = [
        "zoom",
        "teams",
        "meet",
        "webex",
        "facetime",
        "join",
    ]

    static func meetingURL(rawURL: URL?, notes: String?, location: String?) -> URL? {
        if let rawURL {
            return rawURL
        }

        let candidates = detectedURLs(in: notes) + detectedURLs(in: location)

        if let preferred = candidates.first(where: isLikelyMeetingURL) {
            return preferred
        }

        return nil
    }

    static func isOnlineMeeting(rawURL: URL?, notes: String?, location: String?) -> Bool {
        if meetingURL(rawURL: rawURL, notes: notes, location: location) != nil {
            return true
        }

        let haystack = "\(notes ?? "")\n\(location ?? "")".lowercased()
        return textHints.contains { haystack.contains($0) }
    }

    private static func detectedURLs(in text: String?) -> [URL] {
        guard let text, !text.isEmpty else { return [] }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: nsRange).compactMap { match in
            guard let url = match.url else { return nil }
            guard let scheme = url.scheme?.lowercased() else { return nil }
            guard scheme == "http" || scheme == "https" || scheme == "facetime" else {
                return nil
            }
            return url
        }
    }

    private static func isLikelyMeetingURL(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "facetime" {
            return true
        }

        let host = url.host?.lowercased() ?? ""
        if hostHints.contains(where: host.contains) {
            return true
        }

        let absolute = url.absoluteString.lowercased()
        return textHints.contains(where: absolute.contains)
    }
}

enum CalendarColorCodec {
    static func hexString(from cgColor: CGColor?) -> String? {
        guard let cgColor,
              let nsColor = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else { return nil }

        let red = Int(round(nsColor.redComponent * 255))
        let green = Int(round(nsColor.greenComponent * 255))
        let blue = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
