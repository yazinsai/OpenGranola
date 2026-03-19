import SwiftUI
import CoreAudio
import Sparkle

struct SettingsView: View {
    private enum Tab: String, CaseIterable {
        case general = "General"
        case ai = "AI Providers"
        case advanced = "Advanced"
    }
    
    private enum TemplateField: Hashable {
        case name
    }

    @Bindable var settings: AppSettings
    var updater: SPUUpdater
    @Environment(AppCoordinator.self) private var coordinator
    @State private var inputDevices: [(id: AudioDeviceID, name: String)] = []
    @State private var isAddingTemplate = false
    @State private var newTemplateName = ""
    @State private var newTemplateIcon = "doc.text"
    @State private var newTemplatePrompt = ""
    @FocusState private var focusedTemplateField: TemplateField?
    @State private var selectedTab: Tab = .general
    @State private var kbFileCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundStyle(selectedTab == tab ? Color.accentTeal : .secondary)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(selectedTab == tab ? Color.accentTeal.opacity(0.1) : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
            }
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Tab content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch selectedTab {
                    case .general:
                        generalTab
                    case .ai:
                        aiTab
                    case .advanced:
                        advancedTab
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 600)
        .onAppear {
            inputDevices = MicCapture.availableInputDevices()
            countKBFiles()
        }
        .onChange(of: settings.kbFolderPath) {
            countKBFiles()
        }
    }
    
    // MARK: - General Tab
    
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Meeting Notes Section
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Meeting Notes")
                
                Text("Where transcripts and generated notes are saved.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                HStack {
                    Text(settings.notesFolderPath)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    Button("Choose...") {
                        chooseNotesFolder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            Divider()
            
            // Knowledge Base Section
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Knowledge Base")
                
                Text("Optional folder of notes for smart suggestions. OpenOats searches these files during calls to surface relevant talking points.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                HStack {
                    Text(settings.kbFolderPath.isEmpty ? "Not set" : settings.kbFolderPath)
                        .font(.system(size: 12))
                        .foregroundStyle(settings.kbFolderPath.isEmpty ? .tertiary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    if !settings.kbFolderPath.isEmpty {
                        Button("Clear") {
                            settings.kbFolderPath = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Button("Choose...") {
                        chooseKBFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                
                // KB Status badge
                if !settings.kbFolderPath.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentTeal)
                        Text("KB Connected\(kbFileCount > 0 ? " · \(kbFileCount) files" : "")")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentTeal)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentTeal.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            
            Divider()
            
            // Privacy Section
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Privacy")
                
                Toggle("Hide from screen sharing", isOn: $settings.hideFromScreenShare)
                    .font(.system(size: 12))
                
                Text("When enabled, the app is invisible during screen recordings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // Updates Section
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Updates")
                
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                .font(.system(size: 12))
            }
        }
    }
    
    // MARK: - AI Providers Tab
    
    private var aiTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Mode Selection
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("AI Mode")
                
                Text("Choose how OpenOats processes your data.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                // Local Mode Card
                ModeCard(
                    icon: "lock.fill",
                    title: "Local Mode",
                    description: "Everything runs on your machine. Requires Ollama running locally. Maximum privacy, no data leaves your device.",
                    isSelected: isLocalMode,
                    action: {
                        settings.llmProvider = .ollama
                        settings.embeddingProvider = .ollama
                    }
                )
                
                // Cloud Mode Card
                ModeCard(
                    icon: "cloud.fill",
                    title: "Cloud Mode",
                    description: "Uses cloud providers for best quality. Requires API keys. Transcription stays local, only text snippets are sent to cloud.",
                    isSelected: !isLocalMode,
                    action: {
                        settings.llmProvider = .openRouter
                        settings.embeddingProvider = .voyageAI
                    }
                )
            }
            
            Divider()
            
            // LLM Provider Section
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Language Model")
                
                if settings.llmProvider == .openRouter {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("OpenRouter API Key", text: $settings.openRouterApiKey)
                            .font(.system(size: 12, design: .monospaced))
                        
                        TextField("Model", text: $settings.selectedModel, prompt: Text("e.g. google/gemini-2.5-flash-preview"))
                            .font(.system(size: 12, design: .monospaced))
                        
                        Text("Popular: google/gemini-2.5-flash, anthropic/claude-3.5-sonnet, openai/gpt-4o")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                } else if settings.llmProvider == .ollama {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Ollama Base URL", text: $settings.ollamaBaseURL, prompt: Text("http://127.0.0.1:11434"))
                            .font(.system(size: 12, design: .monospaced))
                        
                        TextField("Model", text: $settings.ollamaLLMModel, prompt: Text("e.g. qwen3:8b, llama3.2:3b"))
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
            }
            
            Divider()
            
            // Embedding Provider Section
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Embeddings")
                
                Text("Used for knowledge base search.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                if settings.embeddingProvider == .voyageAI {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("Voyage AI API Key", text: $settings.voyageApiKey)
                            .font(.system(size: 12, design: .monospaced))
                        
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                            Text("Uses voyage-3-lite model")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                } else if settings.embeddingProvider == .ollama {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Ollama Base URL", text: $settings.ollamaBaseURL, prompt: Text("http://127.0.0.1:11434"))
                            .font(.system(size: 12, design: .monospaced))
                        
                        TextField("Embedding Model", text: $settings.ollamaEmbedModel, prompt: Text("e.g. nomic-embed-text"))
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
            }
        }
    }
    
    // MARK: - Advanced Tab
    
    private var advancedTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Transcription Section
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Transcription")
                
                Picker("Model", selection: $settings.transcriptionModel) {
                    ForEach(TranscriptionModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .font(.system(size: 12))
                
                if settings.transcriptionModel.supportsExplicitLanguageHint {
                    TextField("Language / Locale (e.g. en-US)", text: $settings.transcriptionLocale)
                        .font(.system(size: 12, design: .monospaced))
                    
                    Text("BCP-47 format. Leave empty for auto-detection.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // Audio Input Section
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Audio Input")
                
                Picker("Microphone", selection: $settings.inputDeviceID) {
                    Text("System Default").tag(AudioDeviceID(0))
                    ForEach(inputDevices, id: \\1.0) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .font(.system(size: 12))
            }
            
            Divider()
            
            // Meeting Templates Section
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Meeting Templates")
                
                ForEach(coordinator.templateStore.templates) { template in
                    HStack {
                        Image(systemName: template.icon)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        Text(template.name)
                            .font(.system(size: 12))
                        Spacer()
                        if template.isBuiltIn {
                            Image(systemName: "lock")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Button("Reset") {
                                coordinator.templateStore.resetBuiltIn(id: template.id)
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        } else {
                            Button {
                                coordinator.templateStore.delete(id: template.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                if isAddingTemplate {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Name")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField("e.g. Sprint Planning", text: $newTemplateName)
                                .font(.system(size: 12))
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedTemplateField, equals: .name)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Icon")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            IconPickerGrid(selected: $newTemplateIcon)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Notes Prompt")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("Instructions for how the AI should format notes.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            TextEditor(text: $newTemplatePrompt)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(height: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(.quaternary)
                                )
                        }
                        
                        HStack {
                            Button("Cancel") {
                                resetNewTemplateForm()
                            }
                            .buttonStyle(.plain)
                            
                            Button("Save") {
                                let template = MeetingTemplate(
                                    id: UUID(),
                                    name: trimmedTemplateName,
                                    icon: newTemplateIcon,
                                    systemPrompt: trimmedTemplatePrompt,
                                    isBuiltIn: false
                                )
                                coordinator.templateStore.add(template)
                                resetNewTemplateForm()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canSaveNewTemplate)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button("New Template") {
                        isAddingTemplate = true
                        Task { @MainActor in
                            focusedTemplateField = .name
                        }
                    }
                    .font(.system(size: 12))
                }
            }
            
            Divider()
            
            // Reset Section
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Reset")
                
                Button("Reset to Defaults") {
                    // Reset logic
                }
                .font(.system(size: 12))
                .foregroundStyle(.red)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var isLocalMode: Bool {
        settings.llmProvider == .ollama && settings.embeddingProvider == .ollama
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .default))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1)
    }
    
    private func countKBFiles() {
        guard !settings.kbFolderPath.isEmpty else {
            kbFileCount = 0
            return
        }
        // Count files in KB folder
        let url = URL(fileURLWithPath: settings.kbFolderPath)
        if let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            kbFileCount = files.filter { $0.pathExtension == "md" || $0.pathExtension == "txt" }.count
        }
    }

    private func chooseKBFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder containing your knowledge base documents (.md, .txt)"

        if panel.runModal() == .OK, let url = panel.url {
            settings.kbFolderPath = url.path
        }
    }

    private func chooseNotesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to save meeting transcripts"

        if panel.runModal() == .OK, let url = panel.url {
            settings.notesFolderPath = url.path
        }
    }

    private var trimmedTemplateName: String {
        newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTemplatePrompt: String {
        newTemplatePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveNewTemplate: Bool {
        !trimmedTemplateName.isEmpty && !trimmedTemplatePrompt.isEmpty
    }

    private func resetNewTemplateForm() {
        isAddingTemplate = false
        newTemplateName = ""
        newTemplateIcon = "doc.text"
        newTemplatePrompt = ""
        focusedTemplateField = nil
    }
}

// MARK: - Mode Card Component

private struct ModeCard: View {
    let icon: String
    let title: String
    let description: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentTeal : .secondary)
                    .frame(width: 32, height: 32)
                    .background(isSelected ? Color.accentTeal.opacity(0.1) : Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentTeal)
                }
            }
            .padding(12)
            .background(isSelected ? Color.accentTeal.opacity(0.05) : Color.primary.opacity(0.02))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentTeal : .quaternary, lineWidth: isSelected ? 1.5 : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Icon Picker

private struct IconPickerGrid: View {
    @Binding var selected: String

    private static let icons = [
        "doc.text", "person.2", "person.3", "person.badge.plus",
        "calendar", "clock", "arrow.up.circle", "magnifyingglass",
        "lightbulb", "star", "flag", "bolt",
        "bubble.left.and.bubble.right", "phone", "video",
        "briefcase", "chart.bar", "list.bullet",
        "checkmark.circle", "gear", "globe", "book",
        "pencil", "megaphone",
    ]

    private let columns = Array(repeating: GridItem(.fixed(28), spacing: 4), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Self.icons, id: \\.self) { icon in
                Button {
                    selected = icon
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selected == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(selected == icon ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected == icon ? .primary : .secondary)
            }
        }
    }
}