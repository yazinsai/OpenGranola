import Foundation

// MARK: - Meeting App Detection

/// A running application that may host meetings.
struct MeetingApp: Sendable, Hashable, Codable {
    let bundleID: String
    let name: String
}

/// A single entry in the list of known meeting apps.
struct MeetingAppEntry: Sendable, Hashable, Codable {
    let bundleID: String
    let displayName: String
}

// MARK: - Detection Signal

/// Describes why the system believes a meeting started or ended.
enum DetectionSignal: Sendable, Hashable, Codable {
    /// User pressed Start manually.
    case manual
    /// A known meeting app was detected running.
    case appLaunched(MeetingApp)
    /// A calendar event started.
    case calendarEvent(CalendarEvent)
    /// Audio activity was detected from a meeting source.
    case audioActivity
    /// A camera was activated, suggesting a video call.
    case cameraActivated
}

// MARK: - Detection Context

/// Aggregated context about an active or pending meeting.
struct DetectionContext: Sendable, Equatable, Codable {
    let signal: DetectionSignal
    let detectedAt: Date
    let meetingApp: MeetingApp?
    let calendarEvent: CalendarEvent?
}

// MARK: - Calendar Integration

/// Minimal representation of a calendar event relevant to meeting detection.
struct CalendarEvent: Sendable, Hashable, Codable, Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let externalIdentifier: String?
    let calendarID: String?
    let calendarTitle: String?
    let calendarColorHex: String?
    let organizer: String?
    let participants: [Participant]
    let isOnlineMeeting: Bool
    let meetingURL: URL?

    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        externalIdentifier: String? = nil,
        calendarID: String? = nil,
        calendarTitle: String? = nil,
        calendarColorHex: String? = nil,
        organizer: String?,
        participants: [Participant],
        isOnlineMeeting: Bool,
        meetingURL: URL?
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.externalIdentifier = externalIdentifier
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.calendarColorHex = calendarColorHex
        self.organizer = organizer
        self.participants = participants
        self.isOnlineMeeting = isOnlineMeeting
        self.meetingURL = meetingURL
    }
}

/// A meeting participant from a calendar event.
struct Participant: Sendable, Hashable, Codable {
    let name: String?
    let email: String?
}

extension Participant {
    var displayName: String? {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty {
            return trimmedName
        }

        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedEmail, !trimmedEmail.isEmpty {
            return trimmedEmail
        }

        return nil
    }
}

extension CalendarEvent {
    var invitedParticipantDisplayNames: [String] {
        var results: [String] = []
        var seen: Set<String> = []

        for participant in participants {
            guard let displayName = participant.displayName else { continue }
            let key = participant.email?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? displayName.lowercased()
            if seen.insert(key).inserted {
                results.append(displayName)
            }
        }

        return results
    }
}

enum MeetingHistoryResolver {
    static func historyKey(for event: CalendarEvent) -> String {
        normalizedTitle(event.title)
    }

    static func preferredHistoryKey(for event: CalendarEvent) -> String {
        seriesHistoryKey(for: event) ?? historyKey(for: event)
    }

    static func historyKeys(for event: CalendarEvent) -> [String] {
        historyKeys(title: event.title, meetingFamilyKey: seriesHistoryKey(for: event))
    }

    static func historyKey(for title: String) -> String {
        normalizedTitle(title)
    }

    static func matchingSessions(for event: CalendarEvent, sessionHistory: [SessionIndex]) -> [SessionIndex] {
        matchingSessions(for: event, sessionHistory: sessionHistory, aliases: [:])
    }

    static func matchingSessions(
        for event: CalendarEvent,
        sessionHistory: [SessionIndex],
        aliases: [String: String]
    ) -> [SessionIndex] {
        let eventKeys = Set(historyKeys(for: event).map { canonicalHistoryKey(for: $0, aliases: aliases) })
            .filter { !$0.isEmpty }
        guard !eventKeys.isEmpty else { return [] }

        return sessionHistory
            .filter { session in
                historyKeys(title: session.title, meetingFamilyKey: session.meetingFamilyKey)
                    .map { canonicalHistoryKey(for: $0, aliases: aliases) }
                    .contains { eventKeys.contains($0) }
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    static func matchingSessions(forHistoryKey historyKey: String, sessionHistory: [SessionIndex]) -> [SessionIndex] {
        matchingSessions(forHistoryKey: historyKey, sessionHistory: sessionHistory, aliases: [:])
    }

    static func matchingSessions(
        forHistoryKey historyKey: String,
        sessionHistory: [SessionIndex],
        aliases: [String: String]
    ) -> [SessionIndex] {
        guard !historyKey.isEmpty else { return [] }
        let canonicalKey = canonicalHistoryKey(for: historyKey, aliases: aliases)
        return sessionHistory
            .filter { session in
                historyKeys(title: session.title, meetingFamilyKey: session.meetingFamilyKey)
                    .map { canonicalHistoryKey(for: $0, aliases: aliases) }
                    .contains(canonicalKey)
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    static func seriesHistoryKey(for event: CalendarEvent) -> String? {
        seriesHistoryKey(forExternalIdentifier: event.externalIdentifier)
    }

    static func seriesHistoryKey(forExternalIdentifier externalIdentifier: String?) -> String? {
        let trimmed = externalIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard !trimmed.isEmpty else { return nil }
        return "series:\(trimmed)"
    }

    static func canonicalHistoryKey(for historyKey: String, aliases: [String: String]) -> String {
        let normalizedKey = historyKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedKey.isEmpty else { return "" }

        var current = normalizedKey
        var seen: Set<String> = [normalizedKey]
        while let next = aliases[current], !next.isEmpty, !seen.contains(next) {
            current = next
            seen.insert(next)
        }
        return current
    }

    static func relationScore(from sourceHistoryKey: String, to candidateHistoryKey: String) -> Double? {
        let sourceTokens = tokenSet(forHistoryKey: sourceHistoryKey)
        let candidateTokens = tokenSet(forHistoryKey: candidateHistoryKey)
        if let singleTokenScore = singleTokenRelationScore(
            sourceTokens: sourceTokens,
            candidateTokens: candidateTokens
        ) {
            return singleTokenScore
        }

        guard sourceTokens.count >= 2, candidateTokens.count >= 2 else { return nil }

        let overlap = sourceTokens.intersection(candidateTokens)
        guard overlap.count >= 2 else { return nil }

        let minimumCount = min(sourceTokens.count, candidateTokens.count)
        guard minimumCount > 0 else { return nil }

        let overlapRatio = Double(overlap.count) / Double(minimumCount)
        if sourceTokens.isSubset(of: candidateTokens) || candidateTokens.isSubset(of: sourceTokens) {
            return 1.0 + overlapRatio
        }

        guard overlapRatio >= 0.75 else { return nil }
        return overlapRatio
    }

    static func normalizedTitle(_ title: String) -> String {
        let folded = title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(folded)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private static func tokenSet(forHistoryKey historyKey: String) -> Set<String> {
        Set(historyKey.split(separator: " ").map(String.init))
    }

    private static func historyKeys(title: String?, meetingFamilyKey: String?) -> [String] {
        var keys: [String] = []

        if let meetingFamilyKey,
           !meetingFamilyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            keys.append(meetingFamilyKey)
        }

        let titleKey = normalizedTitle(title ?? "")
        if !titleKey.isEmpty, !keys.contains(titleKey) {
            keys.append(titleKey)
        }

        return keys
    }

    private static func singleTokenRelationScore(
        sourceTokens: Set<String>,
        candidateTokens: Set<String>
    ) -> Double? {
        let overlap = sourceTokens.intersection(candidateTokens)
        guard overlap.count == 1 else { return nil }

        let minimumCount = min(sourceTokens.count, candidateTokens.count)
        guard minimumCount == 1 else { return nil }
        guard let token = overlap.first, token.count >= 4 else { return nil }

        return 0.9
    }
}

// MARK: - Meeting Metadata

/// Metadata assembled during a meeting session (detection context + calendar info).
struct MeetingMetadata: Sendable, Equatable, Codable {
    let detectionContext: DetectionContext?
    let calendarEvent: CalendarEvent?
    /// True when the user explicitly picked `calendarEvent` for this session.
    /// Finalization re-resolves automatic bindings against the session's real
    /// interval, but never second-guesses an explicit choice.
    var calendarEventIsUserChosen: Bool = false
    let title: String?
    let startedAt: Date
    var endedAt: Date?

    static func manual(
        calendarEvent: CalendarEvent? = nil,
        calendarEventIsUserChosen: Bool = false
    ) -> MeetingMetadata {
        let now = Date()
        return MeetingMetadata(
            detectionContext: DetectionContext(
                signal: calendarEvent.map { .calendarEvent($0) } ?? .manual,
                detectedAt: now,
                meetingApp: nil,
                calendarEvent: calendarEvent
            ),
            calendarEvent: calendarEvent,
            calendarEventIsUserChosen: calendarEventIsUserChosen,
            title: calendarEvent?.title,
            startedAt: now, endedAt: nil
        )
    }
}

extension MeetingMetadata {
    private enum CodingKeys: String, CodingKey {
        case detectionContext
        case calendarEvent
        case calendarEventIsUserChosen
        case title
        case startedAt
        case endedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            detectionContext: try container.decodeIfPresent(DetectionContext.self, forKey: .detectionContext),
            calendarEvent: try container.decodeIfPresent(CalendarEvent.self, forKey: .calendarEvent),
            // Payloads written before this field existed decode as false.
            calendarEventIsUserChosen: try container.decodeIfPresent(Bool.self, forKey: .calendarEventIsUserChosen) ?? false,
            title: try container.decodeIfPresent(String.self, forKey: .title),
            startedAt: try container.decode(Date.self, forKey: .startedAt),
            endedAt: try container.decodeIfPresent(Date.self, forKey: .endedAt)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(detectionContext, forKey: .detectionContext)
        try container.encodeIfPresent(calendarEvent, forKey: .calendarEvent)
        try container.encode(calendarEventIsUserChosen, forKey: .calendarEventIsUserChosen)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
    }
}
