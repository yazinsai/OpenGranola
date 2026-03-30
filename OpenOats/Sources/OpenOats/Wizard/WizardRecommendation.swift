import Foundation

/// Resolved configuration from the recommendation engine.
/// Contains exact model and provider values ready to write to `SettingsStore`.
struct WizardRecommendation: Sendable, Equatable {
    // MARK: - Profile

    let profile: WizardProfile

    // MARK: - Transcription

    let transcriptionModel: TranscriptionModel
    let transcriptionLocale: String

    // MARK: - LLM

    let llmProvider: LLMProvider?
    let selectedModel: String?
    let realtimeModel: String?
    let ollamaBaseURL: String?
    let ollamaLLMModel: String?
    let ollamaEmbedModel: String?

    // MARK: - Embedding

    let embeddingProvider: EmbeddingProvider?
    let suggestionPanelEnabled: Bool

    // MARK: - Defaults

    let suggestionVerbosity: SuggestionVerbosity
    let sidebarMode: SidebarMode
    let sidecastIntensity: SidecastIntensity

    // MARK: - Ollama Requirements

    /// Model names that must be present in Ollama for this profile.
    let requiredOllamaModels: [String]

    // MARK: - Display

    /// Human-readable one-line summary.
    let summaryLine: String

    /// Per-component detail lines for the confirmation disclosure.
    let detailLines: [String]

    /// Estimated total download size in bytes for all required models.
    let estimatedDownloadBytes: Int64
}
