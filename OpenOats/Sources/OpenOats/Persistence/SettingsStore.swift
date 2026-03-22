import CoreAudio
import Foundation

typealias SettingsStore = AppSettings

struct AISettings: Sendable {
    let llmProvider: LLMProvider
    let model: String
    let embeddingProvider: EmbeddingProvider
    let knowledgeBaseFolderPath: String
}

struct CaptureSettings: Sendable {
    let inputDeviceID: AudioDeviceID
    let transcriptionModel: TranscriptionModel
    let locale: Locale
    let saveAudioRecording: Bool
    let enableBatchRefinement: Bool
    let enableTranscriptRefinement: Bool
}

struct DetectionSettings: Sendable {
    let isEnabled: Bool
    let customMeetingAppBundleIDs: [String]
    let silenceTimeoutMinutes: Int
    let logEnabled: Bool
}

struct PrivacySettings: Sendable {
    let hasAcknowledgedRecordingConsent: Bool
    let hideFromScreenShare: Bool
}

struct UISettings: Sendable {
    let showLiveTranscript: Bool
    let notesFolderPath: String
}

extension AppSettings {
    var aiSettings: AISettings {
        let model = switch llmProvider {
        case .openRouter: selectedModel
        case .ollama: ollamaLLMModel
        case .mlx: mlxModel
        case .openAICompatible: openAILLMModel
        }

        return AISettings(
            llmProvider: llmProvider,
            model: model,
            embeddingProvider: embeddingProvider,
            knowledgeBaseFolderPath: kbFolderPath
        )
    }

    var captureSettings: CaptureSettings {
        CaptureSettings(
            inputDeviceID: inputDeviceID,
            transcriptionModel: transcriptionModel,
            locale: locale,
            saveAudioRecording: saveAudioRecording,
            enableBatchRefinement: enableBatchRefinement,
            enableTranscriptRefinement: enableTranscriptRefinement
        )
    }

    var detectionSettings: DetectionSettings {
        DetectionSettings(
            isEnabled: meetingAutoDetectEnabled,
            customMeetingAppBundleIDs: customMeetingAppBundleIDs,
            silenceTimeoutMinutes: silenceTimeoutMinutes,
            logEnabled: detectionLogEnabled
        )
    }

    var privacySettings: PrivacySettings {
        PrivacySettings(
            hasAcknowledgedRecordingConsent: hasAcknowledgedRecordingConsent,
            hideFromScreenShare: hideFromScreenShare
        )
    }

    var uiSettings: UISettings {
        UISettings(
            showLiveTranscript: showLiveTranscript,
            notesFolderPath: notesFolderPath
        )
    }
}
