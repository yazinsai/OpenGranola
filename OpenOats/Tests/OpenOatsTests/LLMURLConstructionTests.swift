import Testing
import Foundation
@testable import OpenOats

@Suite("LLM URL construction patterns")
struct LLMURLConstructionTests {

    /// Helper that mirrors the URL construction used in SuggestionEngine and NotesEngine.
    private func buildCompletionsURL(from baseURL: String) -> URL? {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/v1/chat/completions")
    }

    @Test("standard base URL produces correct completions endpoint")
    func standardURL() {
        let url = buildCompletionsURL(from: "http://localhost:4000")
        #expect(url?.absoluteString == "http://localhost:4000/v1/chat/completions")
    }

    @Test("trailing slash is stripped before appending path")
    func trailingSlash() {
        let url = buildCompletionsURL(from: "http://localhost:4000/")
        #expect(url?.absoluteString == "http://localhost:4000/v1/chat/completions")
    }

    @Test("multiple trailing slashes are stripped")
    func multipleTrailingSlashes() {
        let url = buildCompletionsURL(from: "http://localhost:4000///")
        #expect(url?.absoluteString == "http://localhost:4000/v1/chat/completions")
    }

    @Test("custom port works")
    func customPort() {
        let url = buildCompletionsURL(from: "http://192.168.1.100:8080")
        #expect(url?.absoluteString == "http://192.168.1.100:8080/v1/chat/completions")
    }

    @Test("HTTPS URL works")
    func httpsURL() {
        let url = buildCompletionsURL(from: "https://my-litellm.example.com")
        #expect(url?.absoluteString == "https://my-litellm.example.com/v1/chat/completions")
    }

    @Test("Ollama default URL produces correct endpoint")
    func ollamaDefaultURL() {
        let url = buildCompletionsURL(from: "http://localhost:11434")
        #expect(url?.absoluteString == "http://localhost:11434/v1/chat/completions")
    }
}
