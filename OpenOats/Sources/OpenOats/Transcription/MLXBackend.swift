import Foundation
import MLX
import MLXAudioSTT

/// Transcription backend for Qwen3 ASR 1.7B via MLX (on-device, Apple Silicon).
/// @unchecked Sendable: model is written once in prepare() before any transcribe() calls.
final class MLXBackend: TranscriptionBackend, @unchecked Sendable {
    let displayName = "MLX Qwen3 ASR 1.7B"
    private var model: Qwen3ASRModel?

    private static let hubModelID = "mlx-community/Qwen3-ASR-1.7B-8bit"

    func checkStatus() -> BackendStatus {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
        let modelDir = cacheDir.appendingPathComponent(
            "models--\(Self.hubModelID.replacingOccurrences(of: "/", with: "--"))"
        )
        let exists = FileManager.default.fileExists(atPath: modelDir.path)
        return exists ? .ready : .needsDownload(
            prompt: "MLX Qwen3 ASR 1.7B requires a one-time model download (~1.7 GB)."
        )
    }

    func clearModelCache() {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
        let modelDir = cacheDir.appendingPathComponent(
            "models--\(Self.hubModelID.replacingOccurrences(of: "/", with: "--"))"
        )
        try? FileManager.default.removeItem(at: modelDir)
    }

    func prepare(onStatus: @Sendable (String) -> Void) async throws {
        onStatus("Downloading \(displayName)...")
        let loaded = try await Qwen3ASRModel.fromPretrained(Self.hubModelID)
        self.model = loaded
        onStatus("\(displayName) ready")
    }

    func transcribe(_ samples: [Float], locale: Locale) async throws -> String {
        guard let model else {
            throw TranscriptionBackendError.notPrepared
        }

        let audioArray = MLXArray(samples)
        let language = Self.languageName(for: locale)
        let output = model.generate(audio: audioArray, language: language)
        return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Map a Locale to the English language name expected by Qwen3 ASR.
    private static func languageName(for locale: Locale) -> String {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        guard let code = identifier.split(separator: "-").first.map({ String($0).lowercased() }) else {
            return "English"
        }
        let mapping: [String: String] = [
            "en": "English", "zh": "Chinese", "ja": "Japanese",
            "ko": "Korean", "fr": "French", "de": "German",
            "es": "Spanish", "pt": "Portuguese", "it": "Italian",
            "ru": "Russian", "ar": "Arabic", "hi": "Hindi",
            "th": "Thai", "vi": "Vietnamese", "tr": "Turkish",
            "nl": "Dutch", "pl": "Polish", "sv": "Swedish",
            "da": "Danish", "fi": "Finnish", "cs": "Czech",
            "el": "Greek", "hu": "Hungarian", "ro": "Romanian",
            "id": "Indonesian", "ms": "Malay", "fa": "Persian",
        ]
        return mapping[code] ?? "English"
    }
}
