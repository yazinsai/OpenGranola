import XCTest
@testable import OpenOatsKit

final class OpenRouterClientTests: XCTestCase {
    func testPreflightErrorRequiresAPIKeyForOpenRouterHost() throws {
        let url = try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/chat/completions"))

        let error = OpenRouterClient.preflightError(for: url, apiKey: nil)

        guard case .missingAPIKey(let host)? = error else {
            return XCTFail("Expected missing API key error for OpenRouter host")
        }
        XCTAssertEqual(host, "openrouter.ai")
        XCTAssertEqual(error?.errorDescription, "OpenRouter API key required")
    }

    func testPreflightErrorAllowsOpenRouterHostWhenAPIKeyExists() throws {
        let url = try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/chat/completions"))

        let error = OpenRouterClient.preflightError(for: url, apiKey: "sk-or-v1-test")

        XCTAssertNil(error)
    }

    func testPreflightErrorDoesNotRequireAPIKeyForLocalOpenAICompatibleHost() throws {
        let url = try XCTUnwrap(URL(string: "http://localhost:11434/v1/chat/completions"))

        let error = OpenRouterClient.preflightError(for: url, apiKey: nil)

        XCTAssertNil(error)
    }

    func testPreflightErrorDoesNotRequireAPIKeyForRemoteCustomHost() throws {
        let url = try XCTUnwrap(URL(string: "https://api.example.com/v1/chat/completions"))

        let error = OpenRouterClient.preflightError(for: url, apiKey: nil)

        XCTAssertNil(error)
    }

    func testAnthropicMessagesURLNormalizesBaseURL() {
        XCTAssertEqual(
            OpenRouterClient.anthropicMessagesURL(from: "https://api.anthropic.com")?.absoluteString,
            "https://api.anthropic.com/v1/messages"
        )
        XCTAssertEqual(
            OpenRouterClient.anthropicMessagesURL(from: "https://api.anthropic.com/v1")?.absoluteString,
            "https://api.anthropic.com/v1/messages"
        )
        XCTAssertEqual(
            OpenRouterClient.anthropicMessagesURL(from: "https://proxy.example.com/anthropic/v1/messages")?.absoluteString,
            "https://proxy.example.com/anthropic/v1/messages"
        )
    }

    func testAnthropicMessagesURLRejectsInvalidBaseURL() {
        XCTAssertNil(OpenRouterClient.anthropicMessagesURL(from: "not a url"))
    }

    // MARK: - Non-streaming completion decoding

    private func completionData(message: String) -> Data {
        Data(#"{"choices": [{"message": \#(message)}]}"#.utf8)
    }

    func testCompletionTextReturnsContentForNormalResponse() throws {
        let data = completionData(message: #"{"role": "assistant", "content": "Meeting notes"}"#)

        XCTAssertEqual(try OpenRouterClient.completionText(from: data), "Meeting notes")
    }

    func testCompletionTextPrefersContentWhenReasoningAlsoPresent() throws {
        let data = completionData(
            message: #"{"role": "assistant", "content": "Final notes", "reasoning": "thinking..."}"#
        )

        XCTAssertEqual(try OpenRouterClient.completionText(from: data), "Final notes")
    }

    func testCompletionTextThrowsForNullContentWithReasoning() {
        // mlx_lm.server + Qwen3 with thinking enabled: content is null and the
        // whole response lands in `reasoning`. This used to fail JSON decoding.
        let data = completionData(
            message: #"{"role": "assistant", "content": null, "reasoning": "Okay, the user wants..."}"#
        )

        XCTAssertThrowsError(try OpenRouterClient.completionText(from: data)) { error in
            guard case OpenRouterClient.OpenRouterError.reasoningOnlyResponse = error else {
                return XCTFail("Expected reasoningOnlyResponse, got \(error)")
            }
            let description = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(description.contains("reasoning-only"), "Unhelpful description: \(description)")
        }
    }

    func testCompletionTextThrowsForEmptyContentWithReasoning() {
        let data = completionData(
            message: #"{"role": "assistant", "content": "", "reasoning": "Okay, the user wants..."}"#
        )

        XCTAssertThrowsError(try OpenRouterClient.completionText(from: data)) { error in
            guard case OpenRouterClient.OpenRouterError.reasoningOnlyResponse = error else {
                return XCTFail("Expected reasoningOnlyResponse, got \(error)")
            }
        }
    }

    func testCompletionTextReturnsEmptyStringForNullContentWithoutReasoning() throws {
        let data = completionData(message: #"{"role": "assistant", "content": null}"#)

        XCTAssertEqual(try OpenRouterClient.completionText(from: data), "")
    }
}
