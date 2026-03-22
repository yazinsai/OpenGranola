import SwiftUI

struct TranscriptWindowView: View {
    @Environment(LiveSessionController.self) private var liveSessionController

    var body: some View {
        let state = liveSessionController.state

        VStack(spacing: 0) {
            HStack {
                Text("Live Transcript")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !state.liveTranscript.isEmpty {
                    Button {
                        copyTranscript(state.liveTranscript)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Copy transcript to clipboard")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            TranscriptView(
                utterances: state.liveTranscript,
                volatileYouText: state.volatileYouText,
                volatileThemText: state.volatileThemText,
                showSearch: true
            )
        }
        .frame(minWidth: 400, minHeight: 500)
    }

    private func copyTranscript(_ utterances: [Utterance]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let lines = utterances.map { utterance in
            "[\(formatter.string(from: utterance.timestamp))] \(utterance.speaker.displayLabel): \(utterance.displayText)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
