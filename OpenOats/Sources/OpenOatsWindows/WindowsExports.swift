import OpenOatsCore

// Keep a global reference to the core engine so we don't drop it.
private nonisolated(unsafe) var globalEngine: TranscriptionEngine?

@_cdecl("OpenOats_Initialize")
public func OpenOats_Initialize() -> Int32 {
    // This is where we'd initialize the Engine.
    // However TranscriptionEngine requires a TranscriptStore, AppSettings, MicCaptureService, SystemAudioCaptureService.
    // The C# side will feed audio into these capture services via C-bindings!
    return 0
}

@_cdecl("OpenOats_Start")
public func OpenOats_Start() -> Int32 {
    // Starts the engine processing
    return 0
}

@_cdecl("OpenOats_Stop")
public func OpenOats_Stop() {
    // Stops the engine
}

// Memory sharing function for C# to push PCM float chunks to the Swift core
@_cdecl("OpenOats_PushMicAudio")
public func OpenOats_PushMicAudio(buffer: UnsafePointer<Float>, length: Int32) {
    // C# passes float32 16kHz audio here
}

@_cdecl("OpenOats_PushSystemAudio")
public func OpenOats_PushSystemAudio(buffer: UnsafePointer<Float>, length: Int32) {
    // C# passes float32 16kHz audio here
}
