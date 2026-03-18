import Foundation

enum Speaker: String, Codable, Sendable {
    case you
    case them
}

struct Utterance: Identifiable, Codable, Sendable {
    let id: UUID
    let text: String
    let speaker: Speaker
    let timestamp: Date

    init(text: String, speaker: Speaker, timestamp: Date = .now) {
        self.id = UUID()
        self.text = text
        self.speaker = speaker
        self.timestamp = timestamp
    }
}

// MARK: - Conversation State

struct ConversationState: Sendable, Codable {
    var currentTopic: String
    var shortSummary: String
    var openQuestions: [String]
    var activeTensions: [String]
    var recentDecisions: [String]
    var themGoals: [String]
    var suggestedAnglesRecentlyShown: [String]
    var lastUpdatedAt: Date

    static let empty = ConversationState(
        currentTopic: "",
        shortSummary: "",
        openQuestions: [],
        activeTensions: [],
        recentDecisions: [],
        themGoals: [],
        suggestedAnglesRecentlyShown: [],
        lastUpdatedAt: .distantPast
    )
}

// MARK: - Suggestion Trigger

enum SuggestionTriggerKind: String, Codable, Sendable {
    case explicitQuestion
    case decisionPoint
    case disagreement
    case assumption
    case prioritization
    case customerProblem
    case distributionGoToMarket
    case productScope
    case unclear
}

struct SuggestionTrigger: Sendable, Codable {
    var kind: SuggestionTriggerKind
    var utteranceID: UUID
    var excerpt: String
    var confidence: Double
}

// MARK: - Suggestion Evidence

struct SuggestionEvidence: Sendable, Codable {
    var sourceFile: String
    var headerContext: String
    var text: String
    var score: Double
}

// MARK: - Suggestion Decision (Surfacing Gate)

struct SuggestionDecision: Sendable, Codable {
    var shouldSurface: Bool
    var confidence: Double
    var relevanceScore: Double
    var helpfulnessScore: Double
    var timingScore: Double
    var noveltyScore: Double
    var reason: String
    var trigger: SuggestionTrigger?
}

// MARK: - Suggestion Feedback

enum SuggestionFeedback: String, Codable, Sendable {
    case helpful
    case notHelpful
    case dismissed
}

// MARK: - KB Result

struct KBResult: Identifiable, Sendable, Codable {
    let id: UUID
    let text: String
    let sourceFile: String
    let headerContext: String
    let score: Double

    init(text: String, sourceFile: String, headerContext: String = "", score: Double) {
        self.id = UUID()
        self.text = text
        self.sourceFile = sourceFile
        self.headerContext = headerContext
        self.score = score
    }
}

// MARK: - Suggestion

struct Suggestion: Identifiable, Sendable, Codable {
    let id: UUID
    let text: String
    let timestamp: Date
    let kbHits: [KBResult]
    let decision: SuggestionDecision?
    let trigger: SuggestionTrigger?
    let summarySnapshot: String?
    let feedback: SuggestionFeedback?

    init(
        text: String,
        timestamp: Date = .now,
        kbHits: [KBResult] = [],
        decision: SuggestionDecision? = nil,
        trigger: SuggestionTrigger? = nil,
        summarySnapshot: String? = nil,
        feedback: SuggestionFeedback? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
        self.kbHits = kbHits
        self.decision = decision
        self.trigger = trigger
        self.summarySnapshot = summarySnapshot
        self.feedback = feedback
    }
}

// MARK: - Session Record

/// Codable record for JSONL session persistence
struct SessionRecord: Codable {
    let speaker: Speaker
    let text: String
    let timestamp: Date
    let suggestions: [String]?
    let kbHits: [String]?
    let suggestionDecision: SuggestionDecision?
    let surfacedSuggestionText: String?
    let conversationStateSummary: String?

    init(
        speaker: Speaker,
        text: String,
        timestamp: Date,
        suggestions: [String]? = nil,
        kbHits: [String]? = nil,
        suggestionDecision: SuggestionDecision? = nil,
        surfacedSuggestionText: String? = nil,
        conversationStateSummary: String? = nil
    ) {
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
        self.suggestions = suggestions
        self.kbHits = kbHits
        self.suggestionDecision = suggestionDecision
        self.surfacedSuggestionText = surfacedSuggestionText
        self.conversationStateSummary = conversationStateSummary
    }
}

// MARK: - Meeting Templates & Enhanced Notes

struct MeetingTemplate: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var icon: String
    var systemPrompt: String
    var isBuiltIn: Bool
}

struct TemplateSnapshot: Codable, Sendable {
    let id: UUID
    let name: String
    let icon: String
    let systemPrompt: String
}

struct EnhancedNotes: Codable, Sendable {
    let template: TemplateSnapshot
    let generatedAt: Date
    let markdown: String
}

struct SessionIndex: Identifiable, Codable, Sendable {
    let id: String
    let startedAt: Date
    var endedAt: Date?
    var templateSnapshot: TemplateSnapshot?
    var title: String?
    var utteranceCount: Int
    var hasNotes: Bool
}

struct SessionSidecar: Codable, Sendable {
    let index: SessionIndex
    var notes: EnhancedNotes?
}
