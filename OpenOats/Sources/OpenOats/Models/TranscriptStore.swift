import Foundation
import Observation

@Observable
@MainActor
final class TranscriptStore {
    private(set) var utterances: [Utterance] = []
    private(set) var conversationState: ConversationState = .empty
    var volatileYouText: String = ""
    var volatileThemText: String = ""

    /// Count of finalized them-utterances since last state update
    private var themUtterancesSinceStateUpdate: Int = 0

    func append(_ utterance: Utterance) {
        utterances.append(utterance)
        if utterance.speaker == .them {
            themUtterancesSinceStateUpdate += 1
        }
    }

    func clear() {
        utterances.removeAll()
        volatileYouText = ""
        volatileThemText = ""
        conversationState = .empty
        themUtterancesSinceStateUpdate = 0
    }

    func updateConversationState(_ state: ConversationState) {
        conversationState = state
        themUtterancesSinceStateUpdate = 0
    }

    /// Whether conversation state needs a refresh (every 2-3 finalized them-utterances)
    var needsStateUpdate: Bool {
        themUtterancesSinceStateUpdate >= 2
    }

    var lastThemUtterance: Utterance? {
        utterances.last(where: { $0.speaker == .them })
    }

    /// Last N utterances for prompt context
    var recentUtterances: [Utterance] {
        Array(utterances.suffix(10))
    }

    /// Recent 6 utterances for gate/generation prompts
    var recentExchange: [Utterance] {
        Array(utterances.suffix(6))
    }

    /// Recent them-only utterances for trigger analysis
    var recentThemUtterances: [Utterance] {
        utterances.suffix(10).filter { $0.speaker == .them }
    }
}
