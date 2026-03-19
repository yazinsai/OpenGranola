import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// REST client for Voyage AI embeddings and reranking APIs.
actor VoyageClient {
    private let baseURL = "https://api.voyageai.com/v1"

    enum VoyageError: Error, LocalizedError {
        case httpError(Int, String)
        case decodingError
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .httpError(let code, let msg): "Voyage AI error (HTTP \(code)): \(msg)"
            case .decodingError: "Failed to decode Voyage AI response"
            case .emptyResponse: "Empty response from Voyage AI"
            }
        }
    }

    // MARK: - Embeddings

    func embed(
        apiKey: String,
        texts: [String],
        inputType: String,
        model: String = "voyage-4-lite",
        dimensions: Int = 256
    ) async throws -> [[Float]] {
        let body = EmbedRequest(
            input: texts,
            model: model,
            input_type: inputType,
            output_dimension: dimensions
        )

        let data = try await post(
            path: "/embeddings",
            apiKey: apiKey,
            body: body
        )

        let response = try JSONDecoder().decode(EmbedResponse.self, from: data)
        guard !response.data.isEmpty else { throw VoyageError.emptyResponse }

        // Sort by index to maintain order
        return response.data
            .sorted { $0.index < $1.index }
            .map { $0.embedding }
    }

    // MARK: - Reranking

    func rerank(
        apiKey: String,
        query: String,
        documents: [String],
        topN: Int = 5,
        model: String = "rerank-2.5-lite"
    ) async throws -> [(index: Int, score: Double)] {
        let body = RerankRequest(
            query: query,
            documents: documents,
            model: model,
            top_k: topN
        )

        let data = try await post(
            path: "/rerank",
            apiKey: apiKey,
            body: body
        )

        let response = try JSONDecoder().decode(RerankResponse.self, from: data)
        return response.data.map { (index: $0.index, score: $0.relevance_score) }
    }

    // MARK: - HTTP

    private func post<T: Encodable>(
        path: String,
        apiKey: String,
        body: T,
        retryOn429: Bool = true
    ) async throws -> Data {
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw VoyageError.httpError(-1, "No HTTP response")
        }

        if http.statusCode == 429, retryOn429 {
            try await Task.sleep(for: .seconds(20))
            return try await post(path: path, apiKey: apiKey, body: body, retryOn429: false)
        }

        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw VoyageError.httpError(http.statusCode, msg)
        }

        return data
    }

    // MARK: - Request/Response Types

    private struct EmbedRequest: Encodable {
        let input: [String]
        let model: String
        let input_type: String
        let output_dimension: Int
    }

    private struct EmbedResponse: Decodable {
        let data: [EmbeddingData]

        struct EmbeddingData: Decodable {
            let index: Int
            let embedding: [Float]
        }
    }

    private struct RerankRequest: Encodable {
        let query: String
        let documents: [String]
        let model: String
        let top_k: Int
    }

    private struct RerankResponse: Decodable {
        let data: [RerankResult]

        struct RerankResult: Decodable {
            let index: Int
            let relevance_score: Double
        }
    }
}
