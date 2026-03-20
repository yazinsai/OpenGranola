import Testing
@testable import OpenOats

@Suite("TranscriptionModel enum")
struct TranscriptionModelTests {
    @Test("has four cases")
    func allCases() {
        #expect(TranscriptionModel.allCases.count == 4)
        #expect(TranscriptionModel.allCases.contains(.parakeetV2))
        #expect(TranscriptionModel.allCases.contains(.parakeetV3))
        #expect(TranscriptionModel.allCases.contains(.qwen3ASR06B))
        #expect(TranscriptionModel.allCases.contains(.qwen3ASR17B))
    }

    @Test("raw values are stable for UserDefaults persistence")
    func rawValues() {
        #expect(TranscriptionModel.parakeetV2.rawValue == "parakeetV2")
        #expect(TranscriptionModel.parakeetV3.rawValue == "parakeetV3")
        #expect(TranscriptionModel.qwen3ASR06B.rawValue == "qwen3ASR06B")
        #expect(TranscriptionModel.qwen3ASR17B.rawValue == "qwen3ASR17B")
    }

    @Test("display names are user-facing strings")
    func displayNames() {
        #expect(TranscriptionModel.parakeetV2.displayName == "Parakeet TDT v2")
        #expect(TranscriptionModel.parakeetV3.displayName == "Parakeet TDT v3")
        #expect(TranscriptionModel.qwen3ASR06B.displayName == "Qwen3 ASR 0.6B")
        #expect(TranscriptionModel.qwen3ASR17B.displayName == "Qwen3 ASR 1.7B (MLX)")
    }

    @Test("round-trips through raw value")
    func roundTrip() {
        for model in TranscriptionModel.allCases {
            #expect(TranscriptionModel(rawValue: model.rawValue) == model)
        }
    }

    @Test("invalid raw value returns nil")
    func invalidRawValue() {
        #expect(TranscriptionModel(rawValue: "nonexistent") == nil)
    }

    @Test("qwen3ASR17B supports language hint")
    func qwen3ASR17BSupportsLanguageHint() {
        #expect(TranscriptionModel.qwen3ASR17B.supportsExplicitLanguageHint == true)
    }

    @Test("qwen3ASR17B download prompt mentions size")
    func qwen3ASR17BDownloadPrompt() {
        let prompt = TranscriptionModel.qwen3ASR17B.downloadPrompt
        #expect(prompt.contains("2.5 GB"))
    }

    @Test("all cases have non-empty computed properties")
    func nonEmptyProperties() {
        for model in TranscriptionModel.allCases {
            #expect(!model.displayName.isEmpty)
            #expect(!model.downloadPrompt.isEmpty)
            #expect(!model.localeFieldTitle.isEmpty)
            #expect(!model.localeHelpText.isEmpty)
        }
    }
}

@Suite("TranscriptionEngineError")
struct TranscriptionEngineErrorTests {
    @Test("provides localized description for each model")
    func localizedDescriptions() {
        for model in TranscriptionModel.allCases {
            let error = TranscriptionEngineError.transcriberNotInitialized(model)
            let desc = error.localizedDescription
            #expect(desc.contains(model.displayName))
            #expect(desc.contains("not initialized"))
        }
    }
}
