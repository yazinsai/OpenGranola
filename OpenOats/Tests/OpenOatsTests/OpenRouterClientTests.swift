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
            XCTAssertTrue(description.contains("only reasoning output"), "Unhelpful description: \(description)")
            XCTAssertTrue(description.contains("Thinking mode"), "Unhelpful description: \(description)")
            XCTAssertTrue(description.contains("token budget"), "Unhelpful description: \(description)")
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

    func testCompletionTextThrowsForWhitespaceOnlyContentWithReasoning() {
        // Untrimmed emptiness checks let a "\n" content field pass as an answer.
        let data = completionData(
            message: #"{"role": "assistant", "content": "\n", "reasoning": "Okay, the user wants..."}"#
        )

        XCTAssertThrowsError(try OpenRouterClient.completionText(from: data)) { error in
            guard case OpenRouterClient.OpenRouterError.reasoningOnlyResponse = error else {
                return XCTFail("Expected reasoningOnlyResponse, got \(error)")
            }
        }
    }

    func testCompletionTextReturnsContentUntrimmedWhenItIsNotBlank() throws {
        let data = completionData(message: #"{"role": "assistant", "content": "  Meeting notes\n"}"#)

        XCTAssertEqual(try OpenRouterClient.completionText(from: data), "  Meeting notes\n")
    }

    func testCompletionTextThrowsEmptyResponseForNullContentWithoutReasoning() {
        let data = completionData(message: #"{"role": "assistant", "content": null}"#)

        XCTAssertThrowsError(try OpenRouterClient.completionText(from: data)) { error in
            guard case OpenRouterClient.OpenRouterError.emptyResponse = error else {
                return XCTFail("Expected emptyResponse, got \(error)")
            }
            let description = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(description.contains("Empty response"), "Unhelpful description: \(description)")
        }
    }

    func testCompletionTextThrowsEmptyResponseWhenThereAreNoChoices() {
        let data = Data(#"{"choices": []}"#.utf8)

        XCTAssertThrowsError(try OpenRouterClient.completionText(from: data)) { error in
            guard case OpenRouterClient.OpenRouterError.emptyResponse = error else {
                return XCTFail("Expected emptyResponse, got \(error)")
            }
        }
    }

    // MARK: - Streaming completion outcome

    func testStreamOutcomeFlagsReasoningOnlyStream() {
        var outcome = OpenRouterClient.StreamOutcome()
        outcome.record(content: nil, reasoning: "Okay, the user wants")
        outcome.record(content: "", reasoning: " a summary...")

        XCTAssertTrue(outcome.isReasoningOnly)
    }

    func testStreamOutcomeIsNotReasoningOnlyWhenContentArrives() {
        var outcome = OpenRouterClient.StreamOutcome()
        outcome.record(content: nil, reasoning: "Okay, the user wants")
        outcome.record(content: "## Summary", reasoning: nil)

        XCTAssertFalse(outcome.isReasoningOnly)
    }

    func testStreamOutcomeIsNotReasoningOnlyForAnOrdinaryStream() {
        var outcome = OpenRouterClient.StreamOutcome()
        outcome.record(content: "## Summary", reasoning: nil)
        outcome.record(content: "\n- point", reasoning: nil)

        XCTAssertFalse(outcome.isReasoningOnly)
        XCTAssertTrue(outcome.sawContent)
        XCTAssertFalse(outcome.sawReasoning)
    }

    func testStreamOutcomeIgnoresEmptyDeltas() {
        var outcome = OpenRouterClient.StreamOutcome()
        outcome.record(content: "", reasoning: "")

        XCTAssertFalse(outcome.isReasoningOnly)
        XCTAssertFalse(outcome.sawContent)
        XCTAssertFalse(outcome.sawReasoning)
    }
}
