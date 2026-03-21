import Testing
import Foundation
@testable import OpenOats

/// Keys written by the OpenAI-compatible LLM settings under test.
private let testKeys = ["openAILLMBaseURL", "openAILLMModel", "llmProvider"]

/// Remove UserDefaults entries that tests may have written so each test
/// starts from a clean slate regardless of execution order.
private func cleanDefaults() {
    for key in testKeys {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

@Suite("AppSettings – OpenAI-compatible LLM provider", .serialized)
@MainActor
struct AppSettingsLLMTests {

    // MARK: - Defaults

    @Test("openAILLMBaseURL defaults to LiteLLM port")
    func defaultBaseURL() {
        cleanDefaults()
        let settings = AppSettings()
        #expect(settings.openAILLMBaseURL == "http://localhost:4000")
    }

    @Test("openAILLMApiKey defaults to empty string")
    func defaultApiKey() {
        let settings = AppSettings()
        #expect(settings.openAILLMApiKey == "")
    }

    @Test("openAILLMModel defaults to empty string")
    func defaultModel() {
        cleanDefaults()
        let settings = AppSettings()
        #expect(settings.openAILLMModel == "")
    }

    // MARK: - activeModelDisplay

    @Test("activeModelDisplay returns short name for OpenRouter model")
    func activeModelDisplayOpenRouter() {
        let settings = AppSettings()
        settings.llmProvider = .openRouter
        settings.selectedModel = "google/gemini-3-flash-preview"
        #expect(settings.activeModelDisplay == "gemini-3-flash-preview")
    }

    @Test("activeModelDisplay returns Ollama model as-is when no slash")
    func activeModelDisplayOllama() {
        let settings = AppSettings()
        settings.llmProvider = .ollama
        settings.ollamaLLMModel = "qwen3:8b"
        #expect(settings.activeModelDisplay == "qwen3:8b")
    }

    @Test("activeModelDisplay returns OpenAI Compatible model")
    func activeModelDisplayOpenAICompatible() {
        let settings = AppSettings()
        settings.llmProvider = .openAICompatible
        settings.openAILLMModel = "gpt-4o"
        #expect(settings.activeModelDisplay == "gpt-4o")
    }

    @Test("activeModelDisplay strips prefix for slashed OpenAI Compatible model")
    func activeModelDisplayOpenAICompatibleSlashed() {
        let settings = AppSettings()
        settings.llmProvider = .openAICompatible
        settings.openAILLMModel = "openai/gpt-4o"
        #expect(settings.activeModelDisplay == "gpt-4o")
    }

    // MARK: - Persistence via didSet

    @Test("setting openAILLMBaseURL persists to UserDefaults")
    func baseURLPersistence() {
        let settings = AppSettings()
        settings.openAILLMBaseURL = "http://myserver:8000"
        #expect(UserDefaults.standard.string(forKey: "openAILLMBaseURL") == "http://myserver:8000")
        cleanDefaults()
    }

    @Test("setting openAILLMModel persists to UserDefaults")
    func modelPersistence() {
        let settings = AppSettings()
        settings.openAILLMModel = "claude-3-haiku"
        #expect(UserDefaults.standard.string(forKey: "openAILLMModel") == "claude-3-haiku")
        cleanDefaults()
    }

    @Test("setting llmProvider to openAICompatible persists to UserDefaults")
    func providerPersistence() {
        let settings = AppSettings()
        settings.llmProvider = .openAICompatible
        #expect(UserDefaults.standard.string(forKey: "llmProvider") == "openAICompatible")
        cleanDefaults()
    }
}
