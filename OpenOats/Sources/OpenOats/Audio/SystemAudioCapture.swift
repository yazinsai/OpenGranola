@preconcurrency import ScreenCaptureKit
@preconcurrency import AVFoundation
import CoreMedia
import os

/// Captures system audio and microphone via a single ScreenCaptureKit stream.
final class SystemAudioCapture: NSObject, @unchecked Sendable, SCStreamDelegate, SCStreamOutput {
    private let _stream = OSAllocatedUnfairLock<SCStream?>(uncheckedState: nil)
    private let _sysContinuation = OSAllocatedUnfairLock<AsyncStream<AVAudioPCMBuffer>.Continuation?>(uncheckedState: nil)
    private let _micContinuation = OSAllocatedUnfairLock<AsyncStream<AVAudioPCMBuffer>.Continuation?>(uncheckedState: nil)
    private let _audioLevel = AudioLevel()

    var audioLevel: Float { _audioLevel.value }

    struct CaptureStreams {
        let systemAudio: AsyncStream<AVAudioPCMBuffer>
    }

    func bufferStream() async throws -> CaptureStreams {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.channelCount = 1
        config.sampleRate = 48000

        // Enable microphone capture via ScreenCaptureKit is no longer needed
        // since we use MicCapture for robust microphone audio.

        // Minimal video — we only want audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let scStream = SCStream(filter: filter, configuration: config, delegate: self)
        try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))

        let sysStream = AsyncStream<AVAudioPCMBuffer> { cont in
            self._sysContinuation.withLock { $0 = cont }
        }

        _stream.withLock { $0 = scStream }
        try await scStream.startCapture()

        return CaptureStreams(systemAudio: sysStream)
    }

    /// Finish the async stream so consumers exit their for-await loop.
    /// Call this before stop() when you need a graceful drain.
    func finishStream() {
        _sysContinuation.withLock { $0?.finish(); $0 = nil }
    }

    func stop() async {
        try? await _stream.withLock { $0 }?.stopCapture()
        _stream.withLock { $0 = nil }
        _sysContinuation.withLock { $0?.finish(); $0 = nil }
        _audioLevel.value = 0
    }

    // MARK: - SCStreamOutput

    private let _sampleCount = OSAllocatedUnfairLock<Int>(uncheckedState: 0)

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let formatDesc = sampleBuffer.formatDescription,
              var asbd = formatDesc.audioStreamBasicDescription else { return }

        guard let format = AVAudioFormat(streamDescription: &asbd) else { return }

        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frameCount > 0 else { return }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )
        guard status == noErr else { return }

        // Diagnostic: log raw system audio levels periodically
        let count = _sampleCount.withLock { val -> Int in val += 1; return val }
        if count <= 5 || count % 200 == 0 {
            let rms = Self.normalizedRMS(from: pcmBuffer)
            diagLog("[SYS-RAW] #\(count) frames=\(frameCount) sr=\(asbd.mSampleRate) ch=\(asbd.mChannelsPerFrame) rms=\(rms)")
        }

        _ = _sysContinuation.withLock { $0?.yield(pcmBuffer) }
    }

    // MARK: - SCStreamDelegate

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        print("SystemAudioCapture: stream stopped with error: \(error)")
        _sysContinuation.withLock { $0?.finish(); $0 = nil }
    }

    private static func normalizedRMS(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameLength {
            let s = channelData[0][i]
            sum += s * s
        }
        return sqrt(sum / Float(frameLength))
    }

    enum CaptureError: Error {
        case noDisplay
    }
}
