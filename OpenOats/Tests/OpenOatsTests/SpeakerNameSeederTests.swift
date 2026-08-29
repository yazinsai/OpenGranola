import XCTest
@testable import OpenOatsKit

final class SpeakerNameSeederTests: XCTestCase {
    func testSeedsTheOnlyRemoteSpeakerFromTheOnlyOtherInvitee() {
        let names = SpeakerNameSeeder.seededNames(
            remoteSpeakerKeys: ["them"],
            participantNames: ["Ada Lovelace", "Grace Hopper"],
            recorderName: "Grace Hopper"
        )

        XCTAssertEqual(names, ["them": "Ada Lovelace"])
    }

    func testRecorderMatchIsCaseAndWhitespaceInsensitive() {
        let names = SpeakerNameSeeder.seededNames(
            remoteSpeakerKeys: ["remote_2"],
            participantNames: ["Ada Lovelace", "  grace hopper "],
            recorderName: "Grace Hopper"
        )

        XCTAssertEqual(names, ["remote_2": "Ada Lovelace"])
    }

    // Two voices and two candidates is exactly the case where the calendar event
    // cannot say which cluster is which person. No name beats a wrong name.
    func testDoesNotGuessWhenSeveralSpeakersCouldMatchSeveralInvitees() {
        let names = SpeakerNameSeeder.seededNames(
            remoteSpeakerKeys: ["them", "remote_2"],
            participantNames: ["Ada Lovelace", "Alan Turing", "Grace Hopper"],
            recorderName: "Grace Hopper"
        )

        XCTAssertTrue(names.isEmpty)
    }

    func testDoesNotSeedWhenOneVoiceHasSeveralCandidateInvitees() {
        let names = SpeakerNameSeeder.seededNames(
            remoteSpeakerKeys: ["them"],
            participantNames: ["Ada Lovelace", "Alan Turing", "Grace Hopper"],
            recorderName: "Grace Hopper"
        )

        XCTAssertTrue(names.isEmpty)
    }

    func testDoesNotSeedWithoutInvitees() {
        XCTAssertTrue(
            SpeakerNameSeeder.seededNames(
                remoteSpeakerKeys: ["them"],
                participantNames: [],
                recorderName: "Grace Hopper"
            ).isEmpty
        )
    }

    func testIgnoresBlankParticipantNames() {
        let names = SpeakerNameSeeder.seededNames(
            remoteSpeakerKeys: ["them"],
            participantNames: ["   ", "Ada Lovelace"],
            recorderName: nil
        )

        XCTAssertEqual(names, ["them": "Ada Lovelace"])
    }

    func testRemoteSpeakerKeysExcludeTheMicrophoneAndDeduplicate() {
        let utterances = [
            Utterance(text: "hi", speaker: .you),
            Utterance(text: "hello", speaker: .them),
            Utterance(text: "again", speaker: .them),
            Utterance(text: "third voice", speaker: .remote(2)),
        ]

        XCTAssertEqual(
            SpeakerNameSeeder.remoteSpeakerKeys(in: utterances),
            ["them", "remote_2"]
        )
    }
}
