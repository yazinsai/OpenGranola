import Foundation
import Observation

@Observable
@MainActor
final class NotesController {
    struct State: Sendable {
        var sessionSummaries: [SessionSummary] = []
        var selectedSessionID: String?
        var loadedSession: SessionDetail?
        var selectedTemplateForGeneration: MeetingTemplate?
        var notesGenerationInProgress = false
        var generatedMarkdown = ""
        var notesGenerationError: String?
        var transcriptCleanupInProgress = false
        var transcriptCleanupChunksCompleted = 0
        var transcriptCleanupTotalChunks = 0
        var transcriptCleanupError: String?
        var renamingSessionID: String?
        var renameText = ""
        var pendingDeleteSessionID: String?
    }

    @ObservationIgnored nonisolated(unsafe) private var _state = State()
    var state: State {
        get { access(keyPath: \.state); return _state }
        set { withMutation(keyPath: \.state) { _state = newValue } }
    }

    let settings: SettingsStore
    let repository: SessionRepository
    let templateStore: TemplateStore
    let notesEngine: NotesEngine
    let cleanupEngine: TranscriptCleanupEngine
    let navigationState: AppNavigationState

    var onRepositoryChanged: (@MainActor () async -> Void)?

    private var didActivate = false
    private var projectionTask: Task<Void, Never>?

    init(
        settings: SettingsStore,
        repository: SessionRepository,
        templateStore: TemplateStore,
        notesEngine: NotesEngine,
        cleanupEngine: TranscriptCleanupEngine,
        navigationState: AppNavigationState
    ) {
        self.settings = settings
        self.repository = repository
        self.templateStore = templateStore
        self.notesEngine = notesEngine
        self.cleanupEngine = cleanupEngine
        self.navigationState = navigationState
    }

    func activateIfNeeded() async {
        guard !didActivate else { return }
        didActivate = true

        await refreshSessions()
        if let requested = navigationState.consumeRequestedSessionSelection() {
            await selectSession(requested)
        } else if let first = state.sessionSummaries.first {
            await selectSession(first.id)
        }

        startProjectionTask()
    }

    func refreshSessions() async {
        state.sessionSummaries = await repository.listSessions()
        if state.selectedSessionID == nil {
            state.selectedSessionID = state.sessionSummaries.first?.id
        }
    }

    func selectSession(_ sessionID: String?) async {
        state.selectedSessionID = sessionID
        guard let sessionID else {
            state.loadedSession = nil
            return
        }

        let session = await repository.loadSession(id: sessionID)
        state.loadedSession = session

        if let templateID = session.summary.templateSnapshot?.id {
            state.selectedTemplateForGeneration = templateStore.template(for: templateID)
        } else {
            state.selectedTemplateForGeneration = templateStore.template(for: TemplateStore.genericID)
                ?? TemplateStore.builtInTemplates.first
        }
    }

    func beginRename(sessionID: String, existingTitle: String?) {
        state.renamingSessionID = sessionID
        state.renameText = existingTitle ?? ""
    }

    func cancelRename() {
        state.renamingSessionID = nil
        state.renameText = ""
    }

    func commitRename() {
        guard let sessionID = state.renamingSessionID else { return }
        let newTitle = state.renameText
        state.renamingSessionID = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.repository.renameSession(sessionID: sessionID, title: newTitle)
            await self.refreshSessions()
            await self.selectSession(self.state.selectedSessionID)
            await self.onRepositoryChanged?()
        }
    }

    func requestDelete(sessionID: String) {
        state.pendingDeleteSessionID = sessionID
    }

    func clearDeleteRequest() {
        state.pendingDeleteSessionID = nil
    }

    func deleteRequestedSession() {
        guard let sessionID = state.pendingDeleteSessionID else { return }
        state.pendingDeleteSessionID = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.repository.deleteSession(sessionID: sessionID)
            if self.state.selectedSessionID == sessionID {
                self.state.selectedSessionID = nil
                self.state.loadedSession = nil
            }
            await self.refreshSessions()
            if self.state.selectedSessionID == nil {
                await self.selectSession(self.state.sessionSummaries.first?.id)
            }
            await self.onRepositoryChanged?()
        }
    }

    func regenerateNotes(with template: MeetingTemplate? = nil) {
        if let template {
            state.selectedTemplateForGeneration = template
        }
        generateNotes()
    }

    func generateNotes() {
        guard let session = state.loadedSession else { return }

        let template = state.selectedTemplateForGeneration
            ?? templateStore.template(for: TemplateStore.genericID)
            ?? TemplateStore.builtInTemplates.first!

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.notesEngine.generate(
                transcript: session.transcript,
                template: template,
                settings: self.settings
            )

            guard !self.notesEngine.generatedMarkdown.isEmpty else { return }

            let notes = EnhancedNotes(
                template: self.templateStore.snapshot(of: template),
                generatedAt: .now,
                markdown: self.notesEngine.generatedMarkdown
            )

            await self.repository.saveNotes(sessionID: session.summary.id, notes: notes)
            await self.selectSession(session.summary.id)
            await self.refreshSessions()
            await self.exportMarkdownForSelectedSession()
            await self.onRepositoryChanged?()
        }
    }

    func cleanUpTranscript() {
        guard let session = state.loadedSession else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let cleanedRecords = await self.cleanupEngine.cleanup(
                records: session.liveTranscript,
                settings: self.settings
            )

            let utterances = cleanedRecords.map { record in
                Utterance(
                    text: record.text,
                    speaker: record.speaker,
                    timestamp: record.timestamp,
                    refinedText: record.refinedText
                )
            }

            await self.repository.backfillRefinedText(sessionID: session.summary.id, from: utterances)
            await self.selectSession(session.summary.id)
            await self.exportMarkdownForSelectedSession()
            await self.onRepositoryChanged?()
        }
    }

    private func startProjectionTask() {
        projectionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.refreshEngineProjection()
                if let requested = self.navigationState.consumeRequestedSessionSelection() {
                    await self.selectSession(requested)
                }

                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.notesEngine.isGenerating
                        _ = self.notesEngine.generatedMarkdown
                        _ = self.notesEngine.error
                        _ = self.cleanupEngine.isCleaningUp
                        _ = self.cleanupEngine.chunksCompleted
                        _ = self.cleanupEngine.totalChunks
                        _ = self.cleanupEngine.error
                        _ = self.templateStore.templates
                        _ = self.navigationState.requestedSessionSelectionID
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func refreshEngineProjection() {
        state.notesGenerationInProgress = notesEngine.isGenerating
        state.generatedMarkdown = notesEngine.generatedMarkdown
        state.notesGenerationError = notesEngine.error
        state.transcriptCleanupInProgress = cleanupEngine.isCleaningUp
        state.transcriptCleanupChunksCompleted = cleanupEngine.chunksCompleted
        state.transcriptCleanupTotalChunks = cleanupEngine.totalChunks
        state.transcriptCleanupError = cleanupEngine.error
    }

    private func exportMarkdownForSelectedSession() async {
        guard let sessionID = state.selectedSessionID else { return }
        let session = await repository.loadSession(id: sessionID)
        _ = MarkdownMeetingWriter.export(
            session: session,
            outputDirectory: URL(fileURLWithPath: settings.notesFolderPath)
        )
    }
}
