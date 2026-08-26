import AppKit
import SwiftUI

struct TranscriptView: View {
    let utterances: [Utterance]
    var emptyStateMessage: String? = nil
    let volatileYouText: String
    let volatileThemText: String
    var showSearch: Bool = false

    @State private var searchText = ""
    @State private var autoScrollEnabled = true

    private var filteredUtterances: [Utterance] {
        guard !searchText.isEmpty else { return utterances }
        return utterances.filter {
            $0.displayText.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var isSearching: Bool {
        showSearch && !searchText.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if showSearch {
                searchBar
                Divider()
            }
            transcriptScrollView
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("Search transcript…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }

            Divider()
                .frame(height: 14)

            Button {
                autoScrollEnabled.toggle()
            } label: {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 11))
                    .foregroundStyle(autoScrollEnabled ? Color.secondary : Color.red)
            }
            .buttonStyle(.plain)
            .help(autoScrollEnabled ? "Pause auto-scroll" : "Resume auto-scroll")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private var transcriptScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                let visible = filteredUtterances
                if visible.isEmpty && isSearching {
                    Text("No matches")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else if visible.isEmpty,
                          !isSearching,
                          volatileYouText.isEmpty,
                          volatileThemText.isEmpty,
                          let emptyStateMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 18))
                            .foregroundStyle(.tertiary)
                        Text(emptyStateMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                    }
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .padding(16)
                } else {
                    let speakerColumnWidth = TranscriptFlow.speakerColumnWidth(
                        forLabels: visible.map(\.speaker.displayLabel)
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        if !visible.isEmpty {
                            SelectableTextFlow(attributedText: transcriptFlowText(for: visible))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !isSearching {
                            if !volatileYouText.isEmpty {
                                VolatileIndicator(
                                    text: volatileYouText,
                                    speaker: .you,
                                    speakerColumnWidth: speakerColumnWidth
                                )
                            }

                            if !volatileThemText.isEmpty {
                                VolatileIndicator(
                                    text: volatileThemText,
                                    speaker: .them,
                                    speakerColumnWidth: speakerColumnWidth
                                )
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("transcript-bottom")
                    }
                    .padding(16)
                }
            }
            .onChange(of: utterances.count) {
                guard !isSearching, autoScrollEnabled else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("transcript-bottom", anchor: .bottom)
                }
            }
            .onChange(of: volatileYouText) {
                guard !isSearching, autoScrollEnabled else { return }
                proxy.scrollTo("transcript-bottom", anchor: .bottom)
            }
            .onChange(of: volatileThemText) {
                guard !isSearching, autoScrollEnabled else { return }
                proxy.scrollTo("transcript-bottom", anchor: .bottom)
            }
            .onChange(of: searchText) {
                if searchText.isEmpty, autoScrollEnabled {
                    proxy.scrollTo("transcript-bottom", anchor: .bottom)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !autoScrollEnabled {
                    Button {
                        autoScrollEnabled = true
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("transcript-bottom", anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white, Color.accentTeal)
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help("Resume auto-scroll")
                    .padding(12)
                    .transition(.opacity.combined(with: .scale))
                }
            }
        }
    }

    private func shouldShowTimestamp(at index: Int, in visible: [Utterance]) -> Bool {
        guard index > 0 else { return true }
        let current = Calendar.current.dateComponents([.hour, .minute], from: visible[index].timestamp)
        let previous = Calendar.current.dateComponents([.hour, .minute], from: visible[index - 1].timestamp)
        return current.hour != previous.hour || current.minute != previous.minute
    }

    private func transcriptFlowText(for visible: [Utterance]) -> NSAttributedString {
        let lines = visible.enumerated().map { index, utterance in
            TranscriptFlow.Line(
                timestamp: shouldShowTimestamp(at: index, in: visible)
                    ? timestampFormatter.string(from: utterance.timestamp)
                    : nil,
                speakerLabel: utterance.speaker.displayLabel,
                speakerColor: NSColor(utterance.speaker.color),
                renameKey: nil,
                text: utterance.displayText
            )
        }
        return TranscriptFlow.attributed(lines: lines, showsTimestampColumn: true)
    }
}

// MARK: - Timestamp Formatter

private let timestampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()

private struct VolatileIndicator: View {
    let text: String
    let speaker: Speaker
    var speakerColumnWidth: CGFloat = 36

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Spacer()
                .frame(width: 34)

            Text(speaker.displayLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(speaker.color)
                .frame(width: max(36, speakerColumnWidth), alignment: .trailing)

            HStack(spacing: 4) {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Circle()
                    .fill(speaker.color)
                    .frame(width: 4, height: 4)
                    .opacity(0.6)
            }
        }
        .opacity(0.6)
    }
}

// MARK: - Colors

extension Color {
    static let youColor = Color(red: 0.35, green: 0.55, blue: 0.75)    // muted blue
    static let themColor = Color(red: 0.82, green: 0.6, blue: 0.3)     // warm amber
    static let accentTeal = Color(red: 0.15, green: 0.55, blue: 0.55)  // deep teal
}
