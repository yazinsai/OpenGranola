import Foundation

/// Drop-or-display pacing for real-time suggestions.
/// Candidates either surface immediately, replace the current suggestion, or get dropped.
/// No delayed queue — stale candidates are discarded before they reach the throttle.
@MainActor
final class BurstDecayThrottle {
    private var lastSuggestionTime: Date?
    private var lastSuggestionScore: Double = 0

    /// Decide whether a candidate should surface, replace, or be dropped.
    func evaluate(
        candidateScore: Double,
        questionDensity: Double,
        kbRelevance: Double
    ) -> ThrottleDecision {
        let burstScore = (questionDensity * 0.4) + (kbRelevance * 0.6)

        let softMinSpacing: TimeInterval
        let replacementDelta: Double

        if burstScore > 0.7 {
            softMinSpacing = 0
            replacementDelta = 0.05
        } else if burstScore > 0.5 {
            softMinSpacing = 4
            replacementDelta = 0.10
        } else {
            softMinSpacing = 12
            replacementDelta = 0.20
        }

        let timeSinceLastSuggestion: TimeInterval
        if let last = lastSuggestionTime {
            timeSinceLastSuggestion = Date.now.timeIntervalSince(last)
        } else {
            timeSinceLastSuggestion = .infinity
        }

        if timeSinceLastSuggestion >= softMinSpacing {
            return .surface
        }

        if candidateScore >= lastSuggestionScore + replacementDelta {
            return .replace
        }

        return .drop(reason: "Throttled (spacing: \(String(format: "%.0f", softMinSpacing))s, delta needed: \(String(format: "%.2f", replacementDelta)))")
    }

    /// Call after a suggestion is actually shown to the user.
    func recordSurfaced(score: Double) {
        lastSuggestionTime = .now
        lastSuggestionScore = score
    }

    func clear() {
        lastSuggestionTime = nil
        lastSuggestionScore = 0
    }

    enum ThrottleDecision {
        case surface
        case replace
        case drop(reason: String)

        var shouldShow: Bool {
            switch self {
            case .surface, .replace: true
            case .drop: false
            }
        }
    }
}
