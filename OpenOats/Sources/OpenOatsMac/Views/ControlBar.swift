import SwiftUI
import Combine

struct ControlBar: View {
    let isRunning: Bool
    let audioLevel: Float
    let modelDisplayName: String
    let transcriptionPrompt: String
    let statusMessage: String?
    let errorMessage: String?
    let needsDownload: Bool
    let onToggle: () -> Void
    let onConfirmDownload: () -> Void
    let kbConnected: Bool
    let kbFileCount: Int
    let isLocalMode: Bool
    
    @State private var duration: Int = 0
    @State private var timerCancellable: AnyCancellable?
    
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

            // Download prompt
            if needsDownload && !isRunning {
                VStack(spacing: 6) {
                    Text(transcriptionPrompt)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Download Now") {
                        onConfirmDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
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

            HStack(spacing: 12) {
                // Main Record/Stop Button
                Button(action: onToggle) {
                    HStack(spacing: 6) {
                        if isRunning {
                            // Pulsing dot when live
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .scaleEffect(1.0 + CGFloat(audioLevel) * 0.5)
                                .animation(.easeOut(duration: 0.1), value: audioLevel)

                            Text("Stop")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.white)

                            Text("Record")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(isRunning ? Color.red.opacity(0.15) : Color.accentTeal)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isRunning ? Color.red : Color.clear, lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Recording Status Section
                if isRunning {
                    // Duration Timer
                    Text(formatDuration(duration))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(minWidth: 50)

                    // Audio Level Visualizer
                    AudioLevelView(level: audioLevel)
                        .frame(width: 40, height: 16)

                    // Live Badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .clipShape(Capsule())
                }

                Spacer()

                // Status Indicators
                HStack(spacing: 8) {
                    // KB Status
                    if kbConnected {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                            Text("KB\(kbFileCount > 0 ? " \(kbFileCount)" : "")")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(Color.accentTeal)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentTeal.opacity(0.1))
                        .clipShape(Capsule())
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 9))
                            Text("No KB")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(Capsule())
                    }

                    // Mode Indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isLocalMode ? Color.green : Color.blue)
                            .frame(width: 5, height: 5)
                        Text(isLocalMode ? "Local" : "Cloud")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(isLocalMode ? Color.green : Color.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((isLocalMode ? Color.green : Color.blue).opacity(0.1))
                    .clipShape(Capsule())

                    // Model Badge
                    Text(modelDisplayName)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onChange(of: isRunning) { _, newValue in
            if newValue {
                startTimer()
            } else {
                stopTimer()
                duration = 0
            }
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    private func startTimer() {
        duration = 0
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                duration += 1
            }
    }
    
    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let hrs = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60
        
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
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
                    .frame(width: 3, height: CGFloat(4 + i * 2))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
