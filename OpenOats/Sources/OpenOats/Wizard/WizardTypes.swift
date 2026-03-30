import Foundation

// MARK: - User Answers

/// What the user wants OpenOats to do.
enum WizardIntent: String, CaseIterable, Sendable {
    /// Transcription only, no AI processing.
    case transcribe
    /// Transcription plus AI-generated meeting notes.
    case notes
    /// Full copilot with real-time suggestions from the knowledge base.
    case fullCopilot
}

/// Language preference for meetings.
enum WizardLanguage: String, CaseIterable, Sendable {
    /// English only.
    case english
    /// Multilingual, with or without English.
    case multilingual
}

/// Where AI processing happens.
enum WizardPrivacy: String, CaseIterable, Sendable {
    /// Everything stays on-device via Ollama.
    case local
    /// Use cloud APIs.
    case cloud
}

// MARK: - Detection Results

/// RAM tier derived from physical memory.
enum RAMTier: String, Sendable {
    /// Under 12 GB. No 8B+ LLM, no Whisper Large.
    case low
    /// 12 GB or more. Full local stack viable.
    case high

    init(physicalMemoryBytes: UInt64) {
        let twelveGB: UInt64 = 12 * 1024 * 1024 * 1024
        self = physicalMemoryBytes >= twelveGB ? .high : .low
    }
}

/// State of Ollama readiness relative to a required model set.
enum OllamaStatus: Equatable, Sendable {
    /// Running and all required models are present.
    case readyWithModels
    /// Running but missing one or more required models.
    case missingModels(missing: [String])
    /// Ollama could not be reached.
    case notReachable
}

/// Microphone authorization state, mirroring AVAuthorizationStatus.
enum MicPermissionStatus: String, Sendable {
    case authorized
    case notDetermined
    case denied
    case restricted
}

// MARK: - Wizard Navigation

/// Steps in the wizard flow.
enum WizardStep: Int, CaseIterable, Comparable, Sendable {
    case intent = 0
    case languagePrivacy = 1
    case providerSetup = 2
    case confirmation = 3

    static func < (lhs: WizardStep, rhs: WizardStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Profile Identifiers

/// Internal profile names. Never shown to users.
enum WizardProfile: String, CaseIterable, Sendable {
    case transcriptEN = "transcript-en"
    case transcriptMulti = "transcript-multi"
    case cloudEN = "cloud-en"
    case cloudMulti = "cloud-multi"
    case localENLight = "local-en-light"
    case localENFull = "local-en-full"
    case localMultiLight = "local-multi-light"
    case localMultiFull = "local-multi-full"

    var isCloud: Bool {
        switch self {
        case .cloudEN, .cloudMulti:
            true
        default:
            false
        }
    }

    var isLocal: Bool {
        switch self {
        case .localENLight, .localENFull, .localMultiLight, .localMultiFull:
            true
        default:
            false
        }
    }

    var isTranscriptOnly: Bool {
        switch self {
        case .transcriptEN, .transcriptMulti:
            true
        default:
            false
        }
    }

    var needsOpenRouterKey: Bool { isCloud }
    var needsOllama: Bool { isLocal }
}
