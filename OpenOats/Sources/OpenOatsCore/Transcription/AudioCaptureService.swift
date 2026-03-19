import Foundation

/// Defines a cross-platform interface for capturing audio.
/// Implementations must provide audio as mono, 16kHz, Float32 arrays.
public protocol AudioCaptureService: Sendable {
    /// Current audio level (RMS or similar), typically in the range [0.0, 1.0].
    var audioLevel: Float { get }
    
    /// Returns an asynchronous stream of 16kHz Mono Float32 PCM audio buffers.
    func bufferStream() async throws -> AsyncStream<[Float]>
    
    /// Tells the underlying buffer to finish draining gracefully.
    func finishStream()
    
    /// Unconditionally stops the audio capture hardware.
    func stop() async
}

/// A specialized service for microphone capture that supports device selection.
public protocol MicCaptureService: AudioCaptureService {
    var isAuthorized: Bool { get async }
    func bufferStream(deviceID: UInt32) -> AsyncStream<[Float]>
}
