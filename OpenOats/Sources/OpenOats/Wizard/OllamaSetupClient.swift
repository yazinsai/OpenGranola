import Foundation

/// Manages Ollama status checks and model pulls for the setup wizard.
enum OllamaSetupClient {
    /// Pull progress update.
    struct PullProgress: Sendable {
        let status: String
        let fraction: Double?
        let totalBytes: Int64?
        let completedBytes: Int64?
    }

    enum PullError: Error, Sendable {
        case networkError(String)
        case ollamaError(String)
    }

    /// Check Ollama status relative to the required model set.
    static func checkStatus(
        baseURL: String = "http://localhost:11434",
        requiredModels: [String]
    ) async -> OllamaStatus {
        let result = await OllamaModelFetcher.fetchModels(baseURL: baseURL)
        switch result {
        case .failure:
            return .notReachable
        case .success(let available):
            let availableSet = Set(available.map { $0.lowercased() })
            let missing = requiredModels.filter { model in
                let lower = model.lowercased()
                let prefix = lower.split(separator: ":").first.map(String.init) ?? lower
                return !availableSet.contains(lower) && !availableSet.contains(where: { $0.hasPrefix(prefix) })
            }
            return missing.isEmpty ? .readyWithModels : .missingModels(missing: missing)
        }
    }

    /// Pull a model from Ollama via `POST /api/pull`, streaming NDJSON progress.
    static func pullModel(
        _ modelName: String,
        baseURL: String = "http://localhost:11434",
        onProgress: @escaping @Sendable (PullProgress) -> Void
    ) async throws(PullError) {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: trimmed + "/api/pull") else {
            throw .networkError("Invalid Ollama URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3600
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": modelName])

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw .networkError("Failed to connect to Ollama: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw .ollamaError("Ollama returned an error pulling \(modelName)")
        }

        var buffer = Data()
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if byte == UInt8(ascii: "\n") {
                    if let line = try? JSONSerialization.jsonObject(with: buffer) as? [String: Any] {
                        let status = line["status"] as? String ?? ""
                        let total = (line["total"] as? NSNumber)?.int64Value
                        let completed = (line["completed"] as? NSNumber)?.int64Value
                        let fraction: Double?
                        if let total, let completed, total > 0 {
                            fraction = Double(completed) / Double(total)
                        } else {
                            fraction = nil
                        }

                        onProgress(
                            PullProgress(
                                status: status,
                                fraction: fraction,
                                totalBytes: total,
                                completedBytes: completed
                            )
                        )

                        if let errorMessage = line["error"] as? String {
                            throw PullError.ollamaError(errorMessage)
                        }
                    }
                    buffer.removeAll(keepingCapacity: true)
                }
            }
        } catch let error as PullError {
            throw error
        } catch {
            throw .networkError(error.localizedDescription)
        }
    }
}
