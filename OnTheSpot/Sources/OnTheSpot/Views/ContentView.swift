import SwiftUI
import Combine

struct ContentView: View {
    @Bindable var settings: AppSettings
    @State private var transcriptStore = TranscriptStore()
    @State private var knowledgeBase = KnowledgeBase()
    @State private var transcriptionEngine: TranscriptionEngine?
    @State private var suggestionEngine: SuggestionEngine?
    @State private var sessionStore = SessionStore()
    @State private var overlayManager = OverlayManager()
    @State private var lastThemUtteranceCount = 0
    @State private var isTranscriptExpanded = false
    @State private var audioLevel: Float = 0

    var body: some View {
        VStack(spacing: 0) {
            // Compact header
            topBar

            Divider()

            // Main content: Suggestions
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("SUGGESTIONS")
                SuggestionsView(
                    suggestions: suggestionEngine?.suggestions ?? [],
                    currentSuggestion: suggestionEngine?.currentSuggestion ?? "",
                    isGenerating: suggestionEngine?.isGenerating ?? false
                )
            }

            Divider()

            // Collapsible transcript
            DisclosureGroup(isExpanded: $isTranscriptExpanded) {
                TranscriptView(
                    utterances: transcriptStore.utterances,
                    volatileYouText: transcriptStore.volatileYouText,
                    volatileThemText: transcriptStore.volatileThemText
                )
                .frame(height: 150)
            } label: {
                HStack(spacing: 6) {
                    Text("Transcript")
                        .font(.system(size: 12, weight: .medium))
                    if !transcriptStore.utterances.isEmpty {
                        Text("(\(transcriptStore.utterances.count))")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Bottom bar: live indicator + model
            ControlBar(
                isRunning: isRunning,
                audioLevel: audioLevel,
                selectedModel: settings.selectedModel,
                statusMessage: transcriptionEngine?.assetStatus,
                errorMessage: transcriptionEngine?.lastError,
                onToggle: isRunning ? stopSession : startSession
            )
        }
        .frame(minWidth: 280, maxWidth: 360, minHeight: 400)
        .background(.ultraThinMaterial)
        .onAppear {
            transcriptionEngine = TranscriptionEngine(transcriptStore: transcriptStore)
            suggestionEngine = SuggestionEngine(
                transcriptStore: transcriptStore,
                knowledgeBase: knowledgeBase,
                settings: settings
            )
            indexKBIfNeeded()
        }
        .onChange(of: settings.kbFolderPath) {
            indexKBIfNeeded()
        }
        .onChange(of: transcriptStore.utterances.count) {
            handleNewUtterance()
        }
        .onKeyPress(.escape) {
            overlayManager.hide()
            return .handled
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            if isRunning {
                audioLevel = transcriptionEngine?.audioLevel ?? 0
            } else if audioLevel != 0 {
                audioLevel = 0
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Text("On The Spot")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            // KB status
            if knowledgeBase.isIndexed {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text("\(knowledgeBase.fileCount) files")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
            }

            Button("KB Folder...") {
                chooseKBFolder()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Color.accentTeal)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var isRunning: Bool {
        transcriptionEngine?.isRunning ?? false
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.tertiary)
            .tracking(1.5)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    // MARK: - Actions

    private func startSession() {
        Task {
            await sessionStore.startSession()
            await transcriptionEngine?.start(
                locale: settings.locale,
                inputDeviceID: settings.inputDeviceID
            )
        }
    }

    private func stopSession() {
        transcriptionEngine?.stop()
        Task { await sessionStore.endSession() }
    }

    private func toggleOverlay() {
        let content = OverlayContent(
            suggestions: suggestionEngine?.suggestions ?? [],
            currentSuggestion: suggestionEngine?.currentSuggestion ?? "",
            isGenerating: suggestionEngine?.isGenerating ?? false,
            volatileThemText: transcriptStore.volatileThemText
        )
        overlayManager.toggle(content: content)
    }

    private func chooseKBFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose your knowledge base folder"

        if panel.runModal() == .OK, let url = panel.url {
            settings.kbFolderPath = url.path
        }
    }

    private func indexKBIfNeeded() {
        guard let url = settings.kbFolderURL else { return }
        Task {
            knowledgeBase.clear()
            await knowledgeBase.index(folderURL: url)
        }
    }

    private func handleNewUtterance() {
        let utterances = transcriptStore.utterances
        guard let last = utterances.last else { return }

        // Persist to session store
        Task {
            await sessionStore.appendRecord(SessionRecord(
                speaker: last.speaker,
                text: last.text,
                timestamp: last.timestamp,
                suggestions: nil,
                kbHits: nil
            ))
        }

        // Trigger suggestions on THEM utterance
        if last.speaker == .them {
            suggestionEngine?.onThemUtterance(last)
        }
    }
}
