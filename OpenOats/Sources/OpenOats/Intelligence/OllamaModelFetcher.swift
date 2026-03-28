import Foundation

/// Fetches the list of locally available models from an Ollama instance.
enum OllamaModelFetcher {
    struct ModelInfo: Decodable {
        let name: String
    }

    private struct TagsResponse: Decodable {
        let models: [ModelInfo]
    }

    /// Returns model names sorted alphabetically, or an empty array on failure.
    static func fetchModels(baseURL: String) async -> [String] {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed + "/api/tags") else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return []
        }

        guard let decoded = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
            return []
        }

        return decoded.models.map(\.name).sorted()
    }
}
