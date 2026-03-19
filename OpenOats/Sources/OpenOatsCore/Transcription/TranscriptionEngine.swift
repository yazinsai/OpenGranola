#if canImport(Observation)
import Observation
#endif
#if canImport(os)
import os
#endif
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Simple file logger for diagnostics — writes to /tmp/openoats.log
public func diagLog(_ msg: String) {
    let line = "\(Date()): \(msg)\n"
    let path = "/tmp/openoats.log"
    if let fh = FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

/// Orchestrates dual StreamingTranscriber instances for mic (you) and system audio (them).
#if canImport(Observation)
@Observable
#endif
@MainActor
public final class TranscriptionEngine {
    public private(set) var isRunning = false
    public private(set) var assetStatus: String = "Ready"
    public private(set) var lastError: String?
    public private(set) var needsModelDownload = false

    /// Whether the user has confirmed they want to download models.
    public var downloadConfirmed = false

    private let systemCapture: any AudioCaptureService
    private let micCapture: any MicCaptureService
    private let transcriptStore: TranscriptStore
    private let settings: AppSettings

    /// Audio level from mic for the UI meter.
    public var audioLevel: Float { micCapture.audioLevel }

    private var micTask: Task<Void, Never>?
    private var sysTask: Task<Void, Never>?
    private var micKeepAliveTask: Task<Void, Never>?

    private var micWhisperManager: WhisperManager?
    private var systemWhisperManager: WhisperManager?
    private var currentTranscriptionModel: TranscriptionModel?

    private var currentMicDeviceID: UInt32 = 0
    private var userSelectedDeviceID: UInt32 = 0

    private var defaultDeviceListenerBlock: Any? 
    private var micRestartTask: Task<Void, Never>?
    private var pendingMicDeviceID: UInt32?

    init(
        transcriptStore: TranscriptStore,
        settings: AppSettings,
        micCapture: any MicCaptureService,
        systemCapture: any AudioCaptureService
    ) {
        self.transcriptStore = transcriptStore
        self.settings = settings
        self.micCapture = micCapture
        self.systemCapture = systemCapture
        self.needsModelDownload = Self.modelNeedsDownload(settings.transcriptionModel)
    }

    public func refreshModelAvailability() {
        needsModelDownload = Self.modelNeedsDownload(settings.transcriptionModel)
    }

    private static func modelPath() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("ggml-base.en.bin")
    }

    private static func modelNeedsDownload(_ model: TranscriptionModel) -> Bool {
        return !FileManager.default.fileExists(atPath: modelPath().path)
    }

    private func downloadModel() async throws {
        let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let destination = Self.modelPath()
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    func start(
        locale: Locale,
        inputDeviceID: UInt32 = 0,
        transcriptionModel: TranscriptionModel
    ) async {
        diagLog("[ENGINE-0] start() called, isRunning=\(isRunning)")
        guard !isRunning else { return }
        lastError = nil
        refreshModelAvailability()

        if needsModelDownload && !downloadConfirmed {
            return
        }

        guard await ensureMicrophonePermission() else { return }

        isRunning = true

        assetStatus = needsModelDownload
            ? "Downloading \(transcriptionModel.displayName)..."
            : "Loading \(transcriptionModel.displayName)..."
            
        do {
            if needsModelDownload {
                try await downloadModel()
                needsModelDownload = false
                downloadConfirmed = false
            }

            self.micWhisperManager = try WhisperManager(modelPath: Self.modelPath().path)
            self.systemWhisperManager = try WhisperManager(modelPath: Self.modelPath().path)

            currentTranscriptionModel = transcriptionModel
            assetStatus = "Models ready"
        } catch {
            let msg = "Failed to load models: \(error.localizedDescription)"
            diagLog("[ENGINE-2-FAIL] \(msg)")
            lastError = msg
            assetStatus = "Ready"
            isRunning = false
            return
        }

        userSelectedDeviceID = inputDeviceID
        guard let targetMicID = resolvedMicDeviceID(for: inputDeviceID) else {
            let msg = unavailableMicMessage(for: inputDeviceID)
            lastError = msg
            assetStatus = "Ready"
            isRunning = false
            return
        }
        currentMicDeviceID = targetMicID
        
        startMicStream(
            locale: locale,
            transcriptionModel: currentTranscriptionModel ?? transcriptionModel,
            deviceID: targetMicID
        )

        let sysStream: AsyncStream<[Float]>?
        do {
            sysStream = try await systemCapture.bufferStream()
        } catch {
            lastError = "Failed to start system audio: \(error.localizedDescription)"
            sysStream = nil
        }

        let store = transcriptStore

        if let sysStream {
            let sysTranscriber = makeTranscriber(
                locale: locale,
                speaker: .them,
                onPartial: { text in
                    Task { @MainActor in store.volatileThemText = text }
                },
                onFinal: { text in
                    Task { @MainActor in
                        store.volatileThemText = ""
                        store.append(Utterance(text: text, speaker: .them))
                    }
                }
            )
            sysTask = Task.detached {
                await sysTranscriber.run(stream: sysStream)
            }
        }

        assetStatus = "Transcribing (\(transcriptionModel.displayName))"
    }

    func restartMic(inputDeviceID: UInt32) {
        guard isRunning else { return }
        pendingMicDeviceID = inputDeviceID

        if micRestartTask != nil { return }

        micRestartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.micRestartTask = nil }

            while self.isRunning, let requestedDeviceID = self.pendingMicDeviceID {
                self.pendingMicDeviceID = nil
                await self.performMicRestart(inputDeviceID: requestedDeviceID)
            }
        }
    }

    private func ensureMicrophonePermission() async -> Bool {
        let authorized = await micCapture.isAuthorized
        if !authorized {
            lastError = "Microphone access denied or disabled."
            assetStatus = "Ready"
        }
        return authorized
    }

    public func finalize() async {
        micRestartTask?.cancel()
        micRestartTask = nil
        pendingMicDeviceID = nil
        micKeepAliveTask?.cancel()

        micCapture.finishStream()
        systemCapture.finishStream()

        await micTask?.value
        await sysTask?.value

        await micCapture.stop()
        await systemCapture.stop()

        micTask = nil
        sysTask = nil
        pendingMicDeviceID = nil
        micKeepAliveTask = nil
        currentMicDeviceID = 0
        currentTranscriptionModel = nil
        isRunning = false
        assetStatus = "Ready"
    }

    public func stop() {
        micRestartTask?.cancel()
        micRestartTask = nil
        pendingMicDeviceID = nil
        micTask?.cancel()
        sysTask?.cancel()
        micKeepAliveTask?.cancel()
        micTask = nil
        sysTask = nil
        micKeepAliveTask = nil
        Task { await systemCapture.stop() }
        Task { await micCapture.stop() }
        currentMicDeviceID = 0
        currentTranscriptionModel = nil
        isRunning = false
        assetStatus = "Ready"
    }

    private func performMicRestart(inputDeviceID: UInt32) async {
        guard isRunning else { return }

        userSelectedDeviceID = inputDeviceID
        guard let targetMicID = resolvedMicDeviceID(for: inputDeviceID) else {
            return
        }

        guard targetMicID != currentMicDeviceID else { return }

        micCapture.finishStream()
        await micTask?.value

        if Task.isCancelled || !isRunning { return }

        micTask = nil
        await micCapture.stop()
        startMicStream(
            locale: settings.locale,
            transcriptionModel: currentTranscriptionModel ?? settings.transcriptionModel,
            deviceID: targetMicID
        )
        currentMicDeviceID = targetMicID
    }

    private func startMicStream(
        locale: Locale,
        transcriptionModel: TranscriptionModel,
        deviceID: UInt32
    ) {
        let micStream = micCapture.bufferStream(deviceID: deviceID)
        let store = transcriptStore
        let micTranscriber = makeTranscriber(
            locale: locale,
            speaker: .you,
            onPartial: { text in
                Task { @MainActor in store.volatileYouText = text }
            },
            onFinal: { text in
                Task { @MainActor in
                    store.volatileYouText = ""
                    store.append(Utterance(text: text, speaker: .you))
                }
            }
        )
        micTask = Task.detached {
            await micTranscriber.run(stream: micStream)
        }
    }

    private func makeTranscriber(
        locale: Locale,
        speaker: Speaker,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void
    ) -> StreamingTranscriber {
        let manager = speaker == .you ? micWhisperManager : systemWhisperManager
        guard let manager else {
            fatalError("Whisper transcription requested without an initialized manager")
        }
        return StreamingTranscriber(
            asrManager: manager,
            speaker: speaker,
            onPartial: onPartial,
            onFinal: onFinal
        )
    }

    private func resolvedMicDeviceID(for inputDeviceID: UInt32) -> UInt32? {
        return inputDeviceID
    }

    private func unavailableMicMessage(for inputDeviceID: UInt32) -> String {
        return inputDeviceID > 0 ? "The selected microphone is no longer available." : "No default microphone is currently available."
    }
}
