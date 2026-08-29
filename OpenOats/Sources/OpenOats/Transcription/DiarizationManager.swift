import FluidAudio
import Foundation

/// Manages LS-EEND speaker diarization for system audio.
/// Wraps the FluidAudio LSEENDDiarizer and provides speaker attribution
/// for transcribed segments by querying the diarizer timeline.
actor DiarizationManager {
    private nonisolated(unsafe) let diarizer = LSEENDDiarizer()
    private var isInitialized = false

    /// Load the LS-EEND model for the given variant. Must be called before feedAudio/dominantSpeaker.
    func load(variant: LSEENDVariant = .dihard3) async throws {
        Log.diarization.info("Loading LS-EEND model (variant: \(variant.rawValue, privacy: .public))")
        try await diarizer.initialize(variant: variant)
        isInitialized = true
        Log.diarization.info("LS-EEND model loaded")
    }

    /// Feed audio samples to the diarizer. Samples should be at 16kHz mono Float32.
    /// Uses addAudio + process for streaming (does not reset state between calls).
    func feedAudio(_ samples: [Float]) throws {
        guard isInitialized else { return }
        try diarizer.addAudio(samples, sourceSampleRate: 16000)
        _ = try diarizer.process()
    }

    /// Returns the dominant speaker for a given time range in seconds.
    /// Queries the DiarizerTimeline and finds which speaker has the most
    /// speech frames overlapping [startTime, endTime].
    func dominantSpeaker(from startTime: TimeInterval, to endTime: TimeInterval) -> Speaker {
        let timeline = diarizer.timeline
        let speakers = timeline.speakers

        guard !speakers.isEmpty else { return .them }

        var bestSpeaker: Int = 0
        var bestOverlap: Float = 0

        let queryStart = Float(startTime)
        let queryEnd = Float(endTime)

        for (index, speaker) in speakers {
            let allSegments = speaker.finalizedSegments + speaker.tentativeSegments
            var overlap: Float = 0

            for segment in allSegments {
                let overlapStart = max(segment.startTime, queryStart)
                let overlapEnd = min(segment.endTime, queryEnd)
                if overlapEnd > overlapStart {
                    overlap += overlapEnd - overlapStart
                }
            }

            if overlap > bestOverlap {
                bestOverlap = overlap
                bestSpeaker = index
            }
        }

        guard bestOverlap > 0 else { return .them }

        return Self.speaker(forDiarizerIndex: bestSpeaker)
    }

    /// Maps a diarizer cluster index to a stable `Speaker` label.
    ///
    /// The first cluster stays `.them`, so a session with one remote voice still
    /// reads "Them" rather than "Speaker 1". Later clusters continue that numbering
    /// — "Them" is speaker 1, so cluster 1 is "Speaker 2".
    ///
    /// The mapping deliberately depends only on the index, never on how many
    /// clusters exist *so far*. `dominantSpeaker` runs live, once per utterance,
    /// while the diarizer is still discovering speakers, so a "only one speaker
    /// known yet, call it .them" rule labels one voice `.them` early and
    /// `.remote(1)` from the moment a second voice appears. Nothing revisits the
    /// earlier utterances, so a single participant ends up split across two labels.
    nonisolated static func speaker(forDiarizerIndex index: Int) -> Speaker {
        index <= 0 ? .them : .remote(index + 1)
    }

    /// Returns diarized speaker runs overlapping the given range.
    /// These runs can be used to split a longer speech segment into
    /// smaller speaker-consistent chunks.
    func speakerRuns(from startTime: TimeInterval, to endTime: TimeInterval) -> [BatchTranscriptionSegmentLayout.SpeakerRun] {
        let timeline = diarizer.timeline
        let speakers = timeline.speakers

        guard !speakers.isEmpty else { return [] }

        let queryStart = Float(startTime)
        let queryEnd = Float(endTime)
        let activeSpeakers = speakers.filter { $0.value.hasSegments }

        // One voice owns the whole range; label it the same way dominantSpeaker would.
        if activeSpeakers.count <= 1 {
            return [
                BatchTranscriptionSegmentLayout.SpeakerRun(
                    startTime: startTime,
                    endTime: endTime,
                    speaker: Self.speaker(forDiarizerIndex: activeSpeakers.first?.key ?? 0)
                )
            ]
        }

        var runs: [BatchTranscriptionSegmentLayout.SpeakerRun] = []

        for (index, speaker) in speakers {
            let mappedSpeaker = Self.speaker(forDiarizerIndex: index)
            let allSegments = speaker.finalizedSegments + speaker.tentativeSegments
            for segment in allSegments {
                let overlapStart = max(segment.startTime, queryStart)
                let overlapEnd = min(segment.endTime, queryEnd)
                guard overlapEnd > overlapStart else { continue }
                runs.append(
                    BatchTranscriptionSegmentLayout.SpeakerRun(
                        startTime: TimeInterval(overlapStart),
                        endTime: TimeInterval(overlapEnd),
                        speaker: mappedSpeaker
                    )
                )
            }
        }

        return runs
    }

    /// Finalize the diarization session (flush tentative segments).
    func finalize() {
        guard isInitialized else { return }
        do {
            try diarizer.finalizeSession()
        } catch {
            Log.diarization.error("Failed to finalize LS-EEND session: \(error, privacy: .public)")
        }
    }

    /// Reset the diarizer state for a new session.
    func reset() {
        guard isInitialized else { return }
        diarizer.reset()
    }
}
