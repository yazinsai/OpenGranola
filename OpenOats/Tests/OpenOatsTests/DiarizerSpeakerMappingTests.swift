import XCTest
@testable import OpenOatsKit

final class DiarizerSpeakerMappingTests: XCTestCase {
    // The first cluster keeps reading "Them" so one-remote-voice sessions are
    // unchanged — that was the point of the old single-speaker fallback.
    func testFirstClusterMapsToThem() {
        XCTAssertEqual(DiarizationManager.speaker(forDiarizerIndex: 0), .them)
    }

    // "Them" is speaker 1, so numbering continues from 2.
    func testLaterClustersContinueTheNumbering() {
        XCTAssertEqual(DiarizationManager.speaker(forDiarizerIndex: 1), .remote(2))
        XCTAssertEqual(DiarizationManager.speaker(forDiarizerIndex: 2), .remote(3))
    }

    // The regression: the label a voice gets must not depend on how many other
    // voices the diarizer happens to have discovered by that point in the session.
    func testLabelDependsOnlyOnClusterIndex() {
        let earlyInSession = DiarizationManager.speaker(forDiarizerIndex: 0)
        let lateInSession = DiarizationManager.speaker(forDiarizerIndex: 0)

        XCTAssertEqual(earlyInSession, lateInSession)
        XCTAssertEqual(earlyInSession.storageKey, lateInSession.storageKey)
    }

    func testNegativeIndexIsTreatedAsTheFirstCluster() {
        XCTAssertEqual(DiarizationManager.speaker(forDiarizerIndex: -1), .them)
    }
}
