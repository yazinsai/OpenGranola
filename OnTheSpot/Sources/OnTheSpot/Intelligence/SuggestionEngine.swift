import Foundation
import Observation

/// Generates LLM-powered suggestions based on conversation context and KB results.
@Observable
@MainActor
final class SuggestionEngine {
    private(set) var currentSuggestion: String = ""
    private(set) var suggestions: [Suggestion] = []
    private(set) var isGenerating = false

    private let client = OpenRouterClient()
    private var currentTask: Task<Void, Never>?
    private var lastProcessedUtteranceID: UUID?
    private var lastSuggestionTime: Date?

    /// Minimum seconds between suggestions to avoid overwhelming the user.
    private let cooldownSeconds: TimeInterval = 60
    /// Minimum top KB reranking score to trigger a suggestion (0–1 scale).
    private let minKBRelevanceScore: Double = 0.35

    private let transcriptStore: TranscriptStore
    private let knowledgeBase: KnowledgeBase
    private let settings: AppSettings

    init(transcriptStore: TranscriptStore, knowledgeBase: KnowledgeBase, settings: AppSettings) {
        self.transcriptStore = transcriptStore
        self.knowledgeBase = knowledgeBase
        self.settings = settings
    }

    /// Called when a new THEM utterance is finalized.
    func onThemUtterance(_ utterance: Utterance) {
        guard utterance.id != lastProcessedUtteranceID else { return }
        lastProcessedUtteranceID = utterance.id

        // Enforce cooldown — skip if a suggestion was shown recently
        if let last = lastSuggestionTime,
           Date.now.timeIntervalSince(last) < cooldownSeconds {
            return
        }

        // Cancel any in-flight request
        currentTask?.cancel()

        let apiKey = settings.openRouterApiKey
        guard !apiKey.isEmpty else { return }

        isGenerating = true
        currentSuggestion = ""

        currentTask = Task {
            do {
                // Search KB (async — uses Voyage AI embeddings + reranking)
                let kbResults = await knowledgeBase.search(query: utterance.text, topK: 5)
                guard !kbResults.isEmpty, !Task.isCancelled else {
                    isGenerating = false
                    return
                }

                // Only proceed if the top KB result is relevant enough
                let topScore = kbResults.first?.score ?? 0
                guard topScore >= minKBRelevanceScore, !Task.isCancelled else {
                    isGenerating = false
                    return
                }

                let messages = buildMessages(
                    recentUtterances: transcriptStore.recentUtterances,
                    currentQuery: utterance.text,
                    kbResults: kbResults
                )

                // Stream response
                var accumulated = ""
                for try await chunk in await client.streamCompletion(
                    apiKey: apiKey,
                    model: settings.selectedModel,
                    messages: messages
                ) {
                    guard !Task.isCancelled else { break }
                    accumulated += chunk
                    currentSuggestion = accumulated
                }

                if !Task.isCancelled {
                    let trimmed = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                    // LLM outputs "—" when nothing relevant
                    if !trimmed.isEmpty && trimmed != "—" {
                        let suggestion = Suggestion(
                            text: trimmed,
                            kbHits: kbResults
                        )
                        suggestions.insert(suggestion, at: 0)
                        lastSuggestionTime = .now
                    }
                    currentSuggestion = ""
                }
            } catch {
                if !Task.isCancelled {
                    print("Suggestion error: \(error)")
                }
            }

            isGenerating = false
        }
    }

    func clear() {
        currentTask?.cancel()
        suggestions.removeAll()
        currentSuggestion = ""
        isGenerating = false
        lastProcessedUtteranceID = nil
        lastSuggestionTime = nil
    }

    // MARK: - Private

    private func buildMessages(
        recentUtterances: [Utterance],
        currentQuery: String,
        kbResults: [KBResult]
    ) -> [OpenRouterClient.Message] {
        var messages: [OpenRouterClient.Message] = []

        // System prompt — KB-focused, high-signal only
        var systemPrompt = """
        You are a real-time meeting assistant. The user has a knowledge base (KB) with \
        notes, docs, and reference material. Your ONLY job is to surface specific, useful \
        information FROM the KB that is relevant to what was just said in the conversation.

        Rules:
        - ONLY output information grounded in the KB excerpts below. No generic advice.
        - Output 1-4 bullet points max. Each bullet has two parts:
          • Short headline (≤10 words, the key insight)
          > One-sentence detail or quote from KB
        - Types of bullets (pick what fits):
          - Key facts/numbers from KB relevant right now
          - Pointed questions to ask, based on KB knowledge
          - Specific advice or tips from KB to share
          - Gotchas or caveats mentioned in KB
        - If nothing in the KB is relevant to the current conversation, output only: —
        - No filler. No platitudes. No "consider exploring..." style fluff.
        - Be terse. The user is in a live conversation and glancing at these.

        KB excerpts:
        """

        for result in kbResults {
            systemPrompt += "\n[\(result.sourceFile)]:\n\(result.text)\n"
        }

        messages.append(.init(role: "system", content: systemPrompt))

        // Conversation context
        if !recentUtterances.isEmpty {
            var conversationContext = "Recent conversation:\n"
            for u in recentUtterances {
                let label = u.speaker == .you ? "You" : "Them"
                conversationContext += "\(label): \(u.text)\n"
            }
            messages.append(.init(role: "user", content: conversationContext))
        }

        // Current query
        messages.append(.init(
            role: "user",
            content: "They just said: \"\(currentQuery)\""
        ))

        return messages
    }
}
