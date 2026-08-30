import XCTest
@testable import OpenOatsKit

final class MarkdownMeetingWriterSpeakerNameTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_774_000_000)

    private func makeMetadata(speakerNames: [String: String]?) -> MarkdownMeetingWriter.Metadata {
        var index = SessionIndex(
            id: "session_test",
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            utteranceCount: 2,
            hasNotes: false,
            engine: "parakeetV2"
        )
        index.speakerNames = speakerNames
        return MarkdownMeetingWriter.Metadata(from: index)
    }

    private var records: [SessionRecord] {
        [
            SessionRecord(speaker: .you, text: "Hello", timestamp: start),
            SessionRecord(speaker: .them, text: "Hi there", timestamp: start.addingTimeInterval(30)),
        ]
    }

    func testTranscriptLinesUseSpeakerNames() {
        let lines = MarkdownMeetingWriter.formatTranscriptLines(
            records: records,
            startedAt: start,
            speakerNames: ["them": "Ada Lovelace"]
        )

        XCTAssertTrue(lines.contains("**Ada Lovelace:** Hi there"), lines)
        XCTAssertFalse(lines.contains("**Them:**"), lines)
    }

    func testTranscriptLinesFallBackToDefaultLabels() {
        let lines = MarkdownMeetingWriter.formatTranscriptLines(
            records: records,
            startedAt: start,
            speakerNames: nil
        )

        XCTAssertTrue(lines.contains("**Them:** Hi there"), lines)
    }

    func testFrontMatterParticipantsUseSpeakerNames() {
        let markdown = MarkdownMeetingWriter.buildFrontmatter(
            metadata: makeMetadata(speakerNames: ["them": "Ada Lovelace"]),
            records: records,
            title: "Sync"
        )

        XCTAssertTrue(markdown.contains("  - Ada Lovelace"), markdown)
        XCTAssertFalse(markdown.contains("  - Them"), markdown)
    }

    func testFrontMatterParticipantsFallBackToDefaultLabels() {
        let markdown = MarkdownMeetingWriter.buildFrontmatter(
            metadata: makeMetadata(speakerNames: nil),
            records: records,
            title: "Sync"
        )

        XCTAssertTrue(markdown.contains("  - Them"), markdown)
    }
}
