import Foundation

/// Derives per-session speaker display names from the bound calendar event.
///
/// `SessionIndex.speakerNames` has always supported real names — the transcript UI
/// lets you rename a speaker by hand — but nothing ever populated it, so every
/// session started life as "You" and "Them" even when the calendar knew exactly
/// who was invited.
///
/// Seeding is deliberately conservative. A wrong name attached to a transcript is
/// worse than a generic one, so names are only assigned when the mapping is
/// forced: one remote voice, one invitee besides the recorder. With two remote
/// voices and three invitees there is nothing in the calendar event that says
/// which diarizer cluster belongs to which person.
enum SpeakerNameSeeder {
    /// Returns names to store in `SessionIndex.speakerNames`, or an empty
    /// dictionary when the mapping would be a guess.
    ///
    /// - Parameters:
    ///   - remoteSpeakerKeys: `Speaker.storageKey` for every non-mic speaker that
    ///     actually appears in the transcript.
    ///   - participantNames: Display names invited to the calendar event.
    ///   - recorderName: The local user's name, excluded from the candidates
    ///     because they are recorded on the microphone as `.you`.
    static func seededNames(
        remoteSpeakerKeys: [String],
        participantNames: [String],
        recorderName: String?
    ) -> [String: String] {
        let speakers = orderedUnique(remoteSpeakerKeys)
        let recorder = normalized(recorderName)

        let candidates = orderedUnique(
            participantNames.compactMap { name in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                guard recorder == nil || normalized(trimmed) != recorder else { return nil }
                return trimmed
            }
        )

        guard speakers.count == 1, candidates.count == 1 else { return [:] }
        return [speakers[0]: candidates[0]]
    }

    /// Remote speaker keys present in a finished session, in first-heard order.
    static func remoteSpeakerKeys(in utterances: [Utterance]) -> [String] {
        orderedUnique(utterances.filter { $0.speaker.isRemote }.map { $0.speaker.storageKey })
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }
}
