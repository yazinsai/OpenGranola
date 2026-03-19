import Foundation
#if canImport(os)
import os
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(whisper)
import whisper
#endif

/// Simple energy-based VAD to replace FluidAudio Silero VAD for cross-platform support.
class SimpleVAD {
    var isSpeaking = false
    let threshold: Float = 0.0001
    
    func processStreamingChunk(_ chunk: [Float]) -> Bool {
        let energy = chunk.map { $0 * $0 }.reduce(0, +) / Float(chunk.count)
        let speakingNow = energy > threshold
        return speakingNow
    }
}

/// Simple wrapper around whisper.cpp C-API
public final class WhisperManager: @unchecked Sendable {
    private var ctx: OpaquePointer?
    
    public init(modelPath: String) throws {
        #if canImport(whisper)
        self.ctx = whisper_init_from_file(modelPath)
        guard self.ctx != nil else {
            throw NSError(domain: "Whisper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize context"])
        }
        #else
        // Dummy init if whisper isn't available
        #endif
    }
    
    deinit {
        #if canImport(whisper)
        if let ctx = ctx {
            whisper_free(ctx)
        }
        #endif
    }
    
    public func transcribe(samples: [Float]) -> String {
        #if canImport(whisper)
        guard let ctx = ctx else { return "" }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.single_segment = true
        params.language = "en".withCString { $0 }
        
        // Disable whisper output to stdout directly
        // whisper_print_system_info(ctx)
        
        let ret = samples.withUnsafeBufferPointer { ptr in
            whisper_full(ctx, params, ptr.baseAddress, Int32(samples.count))
        }
        
        if ret != 0 { return "" }
        
        let n_segments = whisper_full_n_segments(ctx)
        var result = ""
        for i in 0..<n_segments {
            if let text = whisper_full_get_segment_text(ctx, i) {
                result += String(cString: text)
            }
        }
        return result
        #else
        return "Whisper library not compiled"
        #endif
    }
}

/// Consumes an audio buffer stream, detects speech via Simple VAD,
/// and transcribes completed speech segments via Whisper.cpp.
public final class StreamingTranscriber: @unchecked Sendable {

    private let asrManager: WhisperManager
    private let vadManager: SimpleVAD
    private let speaker: Speaker
    private let onPartial: @Sendable (String) -> Void
    private let onFinal: @Sendable (String) -> Void
    #if canImport(os)
    private let log = Logger(subsystem: "com.openoats", category: "StreamingTranscriber")
    #endif

    init(
        asrManager: WhisperManager,
        speaker: Speaker,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void
    ) {
        self.asrManager = asrManager
        self.vadManager = SimpleVAD()
        self.speaker = speaker
        self.onPartial = onPartial
        self.onFinal = onFinal
    }

    private static let vadChunkSize = 4096
    private static let minimumSpeechSamples = 8000
    private static let prerollChunkCount = 2
    private static let flushInterval = 48_000

    /// Consumes a stream of mono 16kHz Float32 PCM buffers, runs VAD, and transcribes speech segments.
    func run(stream: AsyncStream<[Float]>) async {
        var speechSamples: [Float] = []
        var vadBuffer: [Float] = []
        var recentChunks: [[Float]] = []
        var isSpeaking = false

        for await bufferArray in stream {
            vadBuffer.append(contentsOf: bufferArray)

            while vadBuffer.count >= Self.vadChunkSize {
                let chunk = Array(vadBuffer.prefix(Self.vadChunkSize))
                vadBuffer.removeFirst(Self.vadChunkSize)
                let wasSpeaking = isSpeaking

                var startedSpeech = false
                var endedSpeech = false

                let speakingNow = vadManager.processStreamingChunk(chunk)

                if speakingNow && !wasSpeaking {
                    isSpeaking = true
                    startedSpeech = true
                    speechSamples = recentChunks.suffix(Self.prerollChunkCount).flatMap { $0 }
                } else if !speakingNow && wasSpeaking {
                    endedSpeech = true
                }

                if wasSpeaking || startedSpeech || endedSpeech {
                    speechSamples.append(contentsOf: chunk)
                    recentChunks.removeAll(keepingCapacity: true)
                } else {
                    recentChunks.append(chunk)
                    if recentChunks.count > Self.prerollChunkCount {
                        recentChunks.removeFirst(recentChunks.count - Self.prerollChunkCount)
                    }
                }

                if endedSpeech {
                    isSpeaking = false
                    if speechSamples.count > Self.minimumSpeechSamples {
                        let segment = speechSamples
                        speechSamples.removeAll(keepingCapacity: true)
                        await transcribeSegment(segment)
                    } else {
                        speechSamples.removeAll(keepingCapacity: true)
                    }
                } else if isSpeaking {
                    if speechSamples.count >= Self.flushInterval {
                        let segment = speechSamples
                        speechSamples.removeAll(keepingCapacity: true)
                        await transcribeSegment(segment)
                    }
                }
            }
        }

        if speechSamples.count > Self.minimumSpeechSamples {
            await transcribeSegment(speechSamples)
        }
    }

    private func transcribeSegment(_ samples: [Float]) async {
        let text = asrManager.transcribe(samples: samples).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        #if canImport(os)
        log.info("[\(self.speaker.rawValue)] transcribed: \(text.prefix(80))")
        #else
        print("[StreamingTranscriber][\(self.speaker.rawValue)] transcribed: \(text.prefix(80))")
        #endif
        onFinal(text)
    }
}
