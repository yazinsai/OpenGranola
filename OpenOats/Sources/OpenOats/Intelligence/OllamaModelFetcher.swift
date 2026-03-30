import Foundation

/// Fetches the list of locally available models from an Ollama instance.
enum OllamaModelFetcher {
    struct ModelInfo: Decodable {
        let name: String
    }

    private struct TagsResponse: Decodable {
        let models: [ModelInfo]
    }

    enum FetchError: Error, Equatable, Sendable {
        case invalidURL
        case networkError(String)
        case decodingError
    }

    /// Returns model names sorted alphabetically, or an error explaining the failure.
    static func fetchModels(baseURL: String) async -> Result<[String], FetchError> {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed + "/api/tags") else {
            return .failure(.invalidURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return .failure(.networkError("Ollama not reachable at \(trimmed)"))
        }

        guard let decoded = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
            return .failure(.decodingError)
        }

        return .success(decoded.models.map(\.name).sorted())
    }

    /// Legacy shim: returns model names or empty array on failure.
    /// Existing callers can migrate incrementally.
    static func fetchModelsLegacy(baseURL: String) async -> [String] {
        switch await fetchModels(baseURL: baseURL) {
        case .success(let models):
            return models
        case .failure:
            return []
        }
    }
}
