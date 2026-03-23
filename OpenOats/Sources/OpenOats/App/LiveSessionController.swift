import Foundation
import Observation
import CoreAudio
import AppKit

/// Published state for the live session, projected by ContentView.
struct LiveSessionState {
    var isRunning: Bool = false
    var sessionPhase: MeetingState = .idle
    var audioLevel: Float = 0
    var liveTranscript: [Utterance] = []
    var volatileYouText: String = ""
    var volatileThemText: String = ""
    var suggestions: [Suggestion] = []
    var isGeneratingSuggestions: Bool = false
    var batchStatus: BatchTranscriptionEngine.Status = .idle
    var lastEndedSession: SessionIndex? = nil
    var lastSessionHasNotes: Bool = false
    var kbIndexingProgress: String = ""
    var statusMessage: String? = nil
    var errorMessage: String? = nil
    var needsDownload: Bool = false
    var transcriptionPrompt: String = ""
    var modelDisplayName: String = ""
    var showLiveTranscript: Bool = true
}

/// Owns all live session side effects: polling, utterance ingestion,
/// settings change tracking, session start/stop, and finalization.
/// ContentView becomes a pure projection of this controller's state.
@Observable
@MainActor
final class LiveSessionController {
    private(set) var state = LiveSessionState()

    private let coordinator: AppCoordinator
    private let container: AppContainer

    // Tracked-change sentinels
    private var observedUtteranceCount = 0
    private var observedIsRunning = false
    private var observedKBFolderPath = ""
    private var observedNotesFolderPath = ""
    private var observedVoyageApiKey = ""
    private var observedTranscriptionModel: TranscriptionModel = .parakeetV2
    private var observedInputDeviceID: AudioDeviceID = 0
    private var observedPendingExternalCommandID: UUID?
    private var previousBatchStatus: BatchTranscriptionEngine.Status = .idle

    init(coordinator: AppCoordinator, container: AppContainer) {
        self.coordinator = coordinator
        self.container = container
    }

    // MARK: - Initialization

    /// One-time setup tasks called when the view first appears.
    func performInitialSetup() async {
        await coordinator.sessionStore.purgeRecentlyDeleted()
    }

    // MARK: - Polling Loop

    /// Call from a `.task` modifier to start the 100ms polling loop.
    func runPollingLoop(settings: AppSettings) async {
        refreshState(settings: settings)
        synchronizeDerivedState(settings: settings)

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))

            // Poll batch engine status (actor-isolated)
            if let engine = coordinator.batchEngine {
                let status = await engine.status
                if status != .idle || coordinator.batchStatus != .idle {
                    let prev = coordinator.batchStatus
                    coordinator.batchStatus = status

                    if case .completed(let sid) = status, prev != status {
                        if !NSApp.isActive, let notifService = container.notificationService {
                            await notifService.postBatchCompleted(sessionID: sid)
                        }
                        await coordinator.loadHistory()

                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(3))
                            if case .completed = coordinator.batchStatus {
                                coordinator.batchStatus = .idle
                            }
                        }
                    }
                }
            }

            refreshState(settings: settings)
            synchronizeDerivedState(settings: settings)
        }
    }

    // MARK: - Session Actions

    func startSession(settings: AppSettings) {
        coordinator.suggestionEngine?.clear()
        coordinator.handle(.userStarted(.manual()), settings: settings)
    }

    func stopSession(settings: AppSettings) {
        coordinator.handle(.userStopped, settings: settings)
    }

    func confirmDownloadAndStart(settings: AppSettings) {
        coordinator.transcriptionEngine?.downloadConfirmed = true
        startSession(settings: settings)
    }

    // MARK: - KB Indexing

    func indexKBIfNeeded(settings: AppSettings) {
        guard let url = settings.kbFolderURL, let kb = coordinator.knowledgeBase else { return }
        Task {
            kb.clear()
            await kb.index(folderURL: url)
        }
    }

    // MARK: - External Commands

    func handlePendingExternalCommandIfPossible(settings: AppSettings, openNotesWindow: (() -> Void)?) {
        guard let request = coordinator.pendingExternalCommand else { return }
        let handled: Bool

        switch request.command {
        case .startSession:
            guard coordinator.transcriptionEngine != nil,
                  coordinator.suggestionEngine != nil,
                  coordinator.transcriptLogger != nil else { return }
            if !state.isRunning {
                startSession(settings: settings)
            }
            handled = true
        case .stopSession:
            guard state.isRunning else { return }
            stopSession(settings: settings)
            handled = true
        case .openNotes(let sessionID):
            coordinator.queueSessionSelection(sessionID)
            openNotesWindow?()
            handled = true
        }

        if handled {
            coordinator.completeExternalCommand(request.id)
        }
    }

    // MARK: - Utterance Ingestion (migrated from ContentView)

    private func handleNewUtterance(_ last: Utterance, settings: AppSettings) {
        container.detectionController?.noteUtterance()

        Task {
            await coordinator.transcriptLogger?.append(
                speaker: last.speaker.displayLabel,
                text: last.text,
                timestamp: last.timestamp
            )
        }

        if settings.enableTranscriptRefinement, let engine = coordinator.refinementEngine {
            Task {
                await engine.refine(last)
            }
        }

        if last.speaker.isRemote {
            coordinator.suggestionEngine?.onThemUtterance(last)

            let baseRecord = SessionRecord(
                speaker: last.speaker,
                text: last.text,
                timestamp: last.timestamp
            )
            Task {
                await coordinator.sessionStore.appendRecordDelayed(
                    baseRecord: baseRecord,
                    utteranceID: last.id,
                    suggestionEngine: coordinator.suggestionEngine,
                    transcriptStore: coordinator.transcriptStore
                )
            }
        } else {
            Task {
                await coordinator.sessionStore.appendRecord(SessionRecord(
                    speaker: last.speaker,
                    text: last.text,
                    timestamp: last.timestamp
                ))
            }
        }
    }

    private func handleNewUtterances(startingAt startIndex: Int, settings: AppSettings) {
        let utterances = coordinator.transcriptStore.utterances
        guard startIndex < utterances.count else { return }

        for utterance in utterances[startIndex...] {
            handleNewUtterance(utterance, settings: settings)
        }
    }

    // MARK: - Transcription Lifecycle (migrated from AppCoordinator)

    func startTranscription(metadata: MeetingMetadata, settings: AppSettings?) async {
        if let batchEngine = coordinator.batchEngine {
            await batchEngine.cancel()
        }

        coordinator.lastEndedSession = nil
        coordinator.lastStorageError = nil
        coordinator.transcriptStore.clear()

        await coordinator.sessionStore.setWriteErrorHandler { [weak coordinator] message in
            Task { @MainActor [weak coordinator] in
                coordinator?.lastStorageError = message
            }
        }

        // Freeze template choice at start time
        if let template = coordinator.selectedTemplate {
            coordinator.sessionTemplateSnapshot = coordinator.templateStore.snapshot(of: template)
        } else if let generic = coordinator.templateStore.template(for: TemplateStore.genericID) {
            coordinator.sessionTemplateSnapshot = coordinator.templateStore.snapshot(of: generic)
        } else {
            coordinator.sessionTemplateSnapshot = nil
        }

        let templateID = coordinator.selectedTemplate?.id
        await coordinator.sessionStore.startSession(templateID: templateID)
        await coordinator.transcriptLogger?.startSession()

        if let settings {
            if settings.saveAudioRecording || settings.enableBatchRefinement {
                coordinator.audioRecorder?.startSession()
                coordinator.transcriptionEngine?.audioRecorder = coordinator.audioRecorder
            } else {
                coordinator.transcriptionEngine?.audioRecorder = nil
            }

            await coordinator.transcriptionEngine?.start(
                locale: settings.locale,
                inputDeviceID: settings.inputDeviceID,
                transcriptionModel: settings.transcriptionModel
            )
        }
    }

    func finalizeCurrentSession(settings: AppSettings?) async {
        // 1. Drain audio buffers
        await coordinator.transcriptionEngine?.finalize()

        // 1b. Drain pending refinements
        if let settings, settings.enableTranscriptRefinement {
            await coordinator.refinementEngine?.drain(timeout: .seconds(5))
        }

        // 2. Drain delayed JSONL writes
        await coordinator.sessionStore.awaitPendingWrites()

        // 2b. Backfill refined text
        let utterancesSnapshot = coordinator.transcriptStore.utterances
        await coordinator.sessionStore.backfillRefinedText(from: utterancesSnapshot)

        // 3. Build sidecar
        let sessionID = await coordinator.sessionStore.currentSessionID ?? "unknown"
        let utteranceCount = coordinator.transcriptStore.utterances.count
        let title = coordinator.transcriptStore.conversationState.currentTopic.isEmpty
            ? nil : coordinator.transcriptStore.conversationState.currentTopic

        let meetingAppName: String?
        if case .ending(let metadata) = coordinator.state {
            meetingAppName = metadata.detectionContext?.meetingApp?.name
        } else {
            meetingAppName = nil
        }

        let engineName = settings?.transcriptionModel.rawValue

        let index = SessionIndex(
            id: sessionID,
            startedAt: coordinator.transcriptStore.utterances.first?.timestamp ?? Date(),
            endedAt: Date(),
            templateSnapshot: coordinator.sessionTemplateSnapshot,
            title: title,
            utteranceCount: utteranceCount,
            hasNotes: false,
            meetingApp: meetingAppName,
            engine: engineName
        )
        let sidecar = SessionSidecar(index: index, notes: nil)

        // 4. Write sidecar
        await coordinator.sessionStore.writeSidecar(sidecar)

        // 4b. Generate structured Markdown
        let jsonlRecords = await coordinator.sessionStore.loadTranscript(sessionID: sessionID)
        if !jsonlRecords.isEmpty, let settings {
            let outputDir = URL(fileURLWithPath: settings.notesFolderPath)
            MarkdownMeetingWriter.write(
                metadata: .init(from: index),
                records: jsonlRecords,
                outputDirectory: outputDir
            )
        }

        // 5. Close JSONL file
        await coordinator.sessionStore.endSession()

        // 6. Close plain-text archive
        await coordinator.transcriptLogger?.endSession()

        // 6b. Merge and encode audio recording
        if let settings, let recorder = coordinator.audioRecorder {
            let wantsBatch = settings.enableBatchRefinement
            let wantsExport = settings.saveAudioRecording

            if wantsBatch && wantsExport {
                let tempURLs = recorder.tempFileURLs()
                let anchorsData = recorder.timingAnchors()
                let fm = FileManager.default

                let copiedMic: URL?
                if let micSrc = tempURLs.mic, fm.fileExists(atPath: micSrc.path) {
                    let dst = URL(fileURLWithPath: NSTemporaryDirectory())
                        .appendingPathComponent("batch_mic_\(sessionID).caf")
                    try? fm.copyItem(at: micSrc, to: dst)
                    copiedMic = dst
                } else {
                    copiedMic = nil
                }

                let copiedSys: URL?
                if let sysSrc = tempURLs.sys, fm.fileExists(atPath: sysSrc.path) {
                    let dst = URL(fileURLWithPath: NSTemporaryDirectory())
                        .appendingPathComponent("batch_sys_\(sessionID).caf")
                    try? fm.copyItem(at: sysSrc, to: dst)
                    copiedSys = dst
                } else {
                    copiedSys = nil
                }

                await coordinator.sessionStore.stashAudioForBatch(
                    sessionID: sessionID,
                    micURL: copiedMic,
                    sysURL: copiedSys,
                    anchors: BatchAnchors(
                        micStartDate: anchorsData.micStartDate,
                        sysStartDate: anchorsData.sysStartDate,
                        micAnchors: anchorsData.micAnchors,
                        sysAnchors: anchorsData.sysAnchors
                    )
                )

                await recorder.finalizeRecording()
            } else if wantsBatch {
                let sealed = recorder.sealForBatch()
                await coordinator.sessionStore.stashAudioForBatch(
                    sessionID: sessionID,
                    micURL: sealed.mic,
                    sysURL: sealed.sys,
                    anchors: BatchAnchors(
                        micStartDate: sealed.micStartDate,
                        sysStartDate: sealed.sysStartDate,
                        micAnchors: sealed.micAnchors,
                        sysAnchors: sealed.sysAnchors
                    )
                )
            } else if wantsExport {
                await recorder.finalizeRecording()
            }
        }

        // 7. Update UI state + refresh history
        coordinator.lastEndedSession = index
        coordinator.sessionTemplateSnapshot = nil
        await coordinator.loadHistory()

        // 8. Kick off batch transcription if enabled
        if let settings, settings.enableBatchRefinement, let batchEngine = coordinator.batchEngine {
            let batchSessionID = sessionID
            let batchModel = settings.batchTranscriptionModel
            let batchLocale = settings.locale
            let notesDir = URL(fileURLWithPath: settings.notesFolderPath)
            let store = coordinator.sessionStore
            let diarize = settings.enableDiarization
            let diarizeVariant = settings.diarizationVariant
            Task.detached { [batchEngine] in
                await batchEngine.process(
                    sessionID: batchSessionID,
                    model: batchModel,
                    locale: batchLocale,
                    sessionStore: store,
                    notesDirectory: notesDir,
                    enableDiarization: diarize,
                    diarizationVariant: diarizeVariant
                )
            }
        }
    }

    func discardSession() {
        coordinator.transcriptionEngine?.stop()
        coordinator.audioRecorder?.discardRecording()
        coordinator.transcriptStore.clear()
        Task {
            await coordinator.transcriptLogger?.endSession()
            await coordinator.sessionStore.endSession()
        }
    }

    // MARK: - State Refresh

    @MainActor
    private func refreshState(settings: AppSettings) {
        let lastEndedSession = coordinator.lastEndedSession
        let lastSessionHasNotes = lastEndedSession.flatMap { lastSession in
            coordinator.sessionHistory.first { $0.id == lastSession.id }?.hasNotes
        } ?? false

        let activeModelRaw = switch settings.llmProvider {
        case .openRouter: settings.selectedModel
        case .ollama: settings.ollamaLLMModel
        case .mlx: settings.mlxModel
        case .openAICompatible: settings.openAILLMModel
        }

        var next = LiveSessionState()
        next.isRunning = coordinator.transcriptionEngine?.isRunning ?? false
        next.sessionPhase = coordinator.state
        next.audioLevel = next.isRunning ? (coordinator.transcriptionEngine?.audioLevel ?? 0) : 0
        next.liveTranscript = coordinator.transcriptStore.utterances
        next.volatileYouText = coordinator.transcriptStore.volatileYouText
        next.volatileThemText = coordinator.transcriptStore.volatileThemText
        next.suggestions = coordinator.suggestionEngine?.suggestions ?? []
        next.isGeneratingSuggestions = coordinator.suggestionEngine?.isGenerating ?? false
        next.batchStatus = coordinator.batchStatus
        next.lastEndedSession = lastEndedSession
        next.lastSessionHasNotes = lastSessionHasNotes
        next.kbIndexingProgress = coordinator.knowledgeBase?.indexingProgress ?? ""
        next.statusMessage = coordinator.transcriptionEngine?.assetStatus
        next.errorMessage = coordinator.transcriptionEngine?.lastError
        next.needsDownload = coordinator.transcriptionEngine?.needsModelDownload ?? false
        next.transcriptionPrompt = settings.transcriptionModel.downloadPrompt
        next.modelDisplayName = activeModelRaw.split(separator: "/").last.map(String.init) ?? activeModelRaw
        next.showLiveTranscript = settings.showLiveTranscript

        state = next
    }

    // MARK: - Derived State Synchronization

    /// Callback for MiniBar show/hide — set by the view.
    var onRunningStateChanged: ((_ isRunning: Bool) -> Void)?
    /// Called every 100ms when recording and minibar is visible, to refresh minibar content.
    var onMiniBarContentUpdate: (() -> Void)?

    /// Callback for opening the notes window — set by the view.
    var openNotesWindow: (() -> Void)?

    @MainActor
    private func synchronizeDerivedState(settings: AppSettings) {
        let currentState = state

        if settings.kbFolderPath != observedKBFolderPath {
            observedKBFolderPath = settings.kbFolderPath
            if settings.kbFolderPath.isEmpty {
                coordinator.knowledgeBase?.clear()
            } else {
                indexKBIfNeeded(settings: settings)
            }
        }

        if settings.notesFolderPath != observedNotesFolderPath {
            observedNotesFolderPath = settings.notesFolderPath
            let url = URL(fileURLWithPath: settings.notesFolderPath)
            Task {
                await coordinator.transcriptLogger?.updateDirectory(url)
            }
            coordinator.audioRecorder?.updateDirectory(url)
        }

        if settings.voyageApiKey != observedVoyageApiKey {
            observedVoyageApiKey = settings.voyageApiKey
            indexKBIfNeeded(settings: settings)
        }

        if settings.transcriptionModel != observedTranscriptionModel {
            observedTranscriptionModel = settings.transcriptionModel
            coordinator.transcriptionEngine?.refreshModelAvailability()
        }

        if settings.inputDeviceID != observedInputDeviceID {
            observedInputDeviceID = settings.inputDeviceID
            if currentState.isRunning {
                Task {
                    coordinator.transcriptionEngine?.restartMic(inputDeviceID: settings.inputDeviceID)
                }
            }
        }

        let utteranceCount = currentState.liveTranscript.count
        if utteranceCount > observedUtteranceCount {
            handleNewUtterances(startingAt: observedUtteranceCount, settings: settings)
        }
        observedUtteranceCount = utteranceCount

        if currentState.isRunning != observedIsRunning {
            observedIsRunning = currentState.isRunning
            onRunningStateChanged?(currentState.isRunning)
        }

        // Refresh minibar content every polling cycle while recording
        if currentState.isRunning {
            onMiniBarContentUpdate?()
        }

        let pendingExternalCommandID = coordinator.pendingExternalCommand?.id
        if pendingExternalCommandID != observedPendingExternalCommandID {
            observedPendingExternalCommandID = pendingExternalCommandID
            handlePendingExternalCommandIfPossible(settings: settings, openNotesWindow: openNotesWindow)
        }
    }
}
