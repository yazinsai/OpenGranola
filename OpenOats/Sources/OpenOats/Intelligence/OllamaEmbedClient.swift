import Foundation

/// Client for Ollama's OpenAI-compatible embeddings endpoint.
actor OllamaEmbedClient {
    enum OllamaEmbedError: Error, LocalizedError {
        case httpError(Int, String)
        case invalidURL
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .httpError(let code, let msg): "Ollama embed error (HTTP \(code)): \(msg)"
            case .invalidURL: "Invalid Ollama base URL"
            case .emptyResponse: "Empty response from Ollama embeddings"
            }
        }
    }

    func embed(texts: [String], baseURL: String, model: String) async throws -> [[Float]] {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/embeddings") else {
            throw OllamaEmbedError.invalidURL
        }

        let body = EmbedRequest(model: model, input: texts)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OllamaEmbedError.httpError(-1, "No HTTP response")
        }

        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OllamaEmbedError.httpError(http.statusCode, msg)
        }

        let decoded = try JSONDecoder().decode(EmbedResponse.self, from: data)
        guard !decoded.data.isEmpty else { throw OllamaEmbedError.emptyResponse }

        return decoded.data
            .sorted { $0.index < $1.index }
            .map { $0.embedding }
    }

    // MARK: - Request/Response Types

    private struct EmbedRequest: Encodable {
        let model: String
        let input: [String]
    }

    private struct EmbedResponse: Decodable {
        let data: [EmbeddingData]

        struct EmbeddingData: Decodable {
            let index: Int
            let embedding: [Float]
        }
    }
}
