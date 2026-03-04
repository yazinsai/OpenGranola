import SwiftUI

struct ControlBar: View {
    let isRunning: Bool
    let audioLevel: Float
    let selectedModel: String
    let statusMessage: String?
    let errorMessage: String?
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Error banner
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }

            // Status message (model loading, etc.)
            if let status = statusMessage, status != "Ready" {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }

            HStack(spacing: 10) {
                Button(action: onToggle) {
                    HStack(spacing: 6) {
                        // Pulsing dot when live, static when idle
                        Circle()
                            .fill(isRunning ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                            .scaleEffect(isRunning ? 1.0 + CGFloat(audioLevel) * 0.5 : 1.0)
                            .animation(.easeOut(duration: 0.1), value: audioLevel)

                        Text(isRunning ? "Live" : "Idle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isRunning ? .primary : .secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(isRunning ? Color.green.opacity(0.1) : Color.primary.opacity(0.04))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Audio level bars when running
                if isRunning {
                    AudioLevelView(level: audioLevel)
                        .frame(width: 40, height: 14)
                }

                Spacer()

                Text(modelDisplayName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var modelDisplayName: String {
        selectedModel.split(separator: "/").last.map(String.init) ?? selectedModel
    }
}

/// Mini audio level visualizer — a few bars that react to mic input.
struct AudioLevelView: View {
    let level: Float

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                let threshold = Float(i) / 5.0
                RoundedRectangle(cornerRadius: 1)
                    .fill(level > threshold ? Color.green.opacity(0.7) : Color.primary.opacity(0.08))
                    .frame(width: 3)
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
