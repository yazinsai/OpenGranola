import XCTest
@testable import OpenOatsKit

/// Covers expiry-date selection and sweep behavior for retained batch audio.
/// The reference date must come from the retained files themselves, never from
/// the session directory, whose modification date is bumped by unrelated
/// metadata writes (notes edits, speaker renames) and would reset the TTL.
final class RetainedBatchAudioSweepTests: XCTestCase {
    private var sessionsDir: URL!

    override func setUpWithError() throws {
        sessionsDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("RetainedBatchAudioSweepTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sessionsDir)
    }

    private func days(_ count: Double) -> TimeInterval { count * 24 * 3600 }

    @discardableResult
    private func makeSession(
        named name: String = "session_test",
        canonicalFiles: [String: Date] = [:],
        legacyFiles: [String: Date] = [:],
        directoryDate: Date? = nil
    ) throws -> URL {
        let fm = FileManager.default
        let sessionDir = sessionsDir.appendingPathComponent(name, isDirectory: true)
        let audioDir = sessionDir.appendingPathComponent("audio", isDirectory: true)
        try fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
        fm.createFile(atPath: sessionDir.appendingPathComponent("session.json").path, contents: Data("{}".utf8))

        for (fileName, date) in canonicalFiles {
            let url = audioDir.appendingPathComponent(fileName)
            fm.createFile(atPath: url.path, contents: Data("audio".utf8))
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        for (fileName, date) in legacyFiles {
            let url = sessionDir.appendingPathComponent(fileName)
            fm.createFile(atPath: url.path, contents: Data("audio".utf8))
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        if let directoryDate {
            try fm.setAttributes([.modificationDate: directoryDate], ofItemAtPath: sessionDir.path)
        }
        return sessionDir
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Reference date selection

    func testReferenceDateComesFromAudioFilesNotSessionDirectory() throws {
        let stemDate = Date(timeIntervalSinceNow: -days(10))
        let sessionDir = try makeSession(
            canonicalFiles: ["mic.caf": stemDate, "sys.caf": stemDate],
            directoryDate: Date()  // a metadata write just bumped the directory
        )

        let reference = SessionRepository.newestRetainedBatchAudioModificationDate(
            inSessionDirectory: sessionDir
        )

        let unwrapped = try XCTUnwrap(reference)
        XCTAssertEqual(unwrapped.timeIntervalSince1970, stemDate.timeIntervalSince1970, accuracy: 2)
    }

    func testReferenceDateIsTheNewestRetainedFile() throws {
        let oldDate = Date(timeIntervalSinceNow: -days(10))
        let newDate = Date(timeIntervalSinceNow: -days(1))
        let sessionDir = try makeSession(
            canonicalFiles: ["mic.caf": oldDate, "sys.caf": newDate, "batch-meta.json": oldDate]
        )

        let reference = SessionRepository.newestRetainedBatchAudioModificationDate(
            inSessionDirectory: sessionDir
        )

        let unwrapped = try XCTUnwrap(reference)
        XCTAssertEqual(unwrapped.timeIntervalSince1970, newDate.timeIntervalSince1970, accuracy: 2)
    }

    func testReferenceDateIsNilWithoutAudioStems() throws {
        let sessionDir = try makeSession(
            canonicalFiles: ["batch-meta.json": Date(timeIntervalSinceNow: -days(10))]
        )

        XCTAssertNil(
            SessionRepository.newestRetainedBatchAudioModificationDate(inSessionDirectory: sessionDir)
        )
    }

    // MARK: - Sweep

    func testSweepDeletesExpiredAudioEvenWhenSessionDirectoryIsFresh() throws {
        // Defect regression: session directory touched today, stems 8 days old.
        let stemDate = Date(timeIntervalSinceNow: -days(8))
        let sessionDir = try makeSession(
            canonicalFiles: ["mic.caf": stemDate, "sys.caf": stemDate, "batch-meta.json": stemDate],
            directoryDate: Date()
        )
        let audioDir = sessionDir.appendingPathComponent("audio", isDirectory: true)

        SessionRepository.cleanupExpiredRetainedBatchAudio(in: sessionsDir, olderThan: days(7))

        XCTAssertFalse(exists(audioDir.appendingPathComponent("mic.caf")))
        XCTAssertFalse(exists(audioDir.appendingPathComponent("sys.caf")))
        XCTAssertFalse(exists(audioDir.appendingPathComponent("batch-meta.json")))
        XCTAssertTrue(exists(sessionDir.appendingPathComponent("session.json")))
        XCTAssertTrue(exists(sessionDir))
    }

    func testSweepKeepsAudioInsideTheRetentionWindow() throws {
        // Inverse defect: a stale directory date must not expire fresh stems.
        let sessionDir = try makeSession(
            canonicalFiles: ["mic.caf": Date(timeIntervalSinceNow: -days(2))],
            directoryDate: Date(timeIntervalSinceNow: -days(30))
        )

        SessionRepository.cleanupExpiredRetainedBatchAudio(in: sessionsDir, olderThan: days(7))

        XCTAssertTrue(
            exists(sessionDir.appendingPathComponent("audio").appendingPathComponent("mic.caf"))
        )
    }

    func testSweepKeepsExpiredStemsWhenAnyRetainedFileIsFresh() throws {
        let sessionDir = try makeSession(
            canonicalFiles: [
                "mic.caf": Date(timeIntervalSinceNow: -days(10)),
                "sys.caf": Date(timeIntervalSinceNow: -days(1)),
            ]
        )

        SessionRepository.cleanupExpiredRetainedBatchAudio(in: sessionsDir, olderThan: days(7))

        let audioDir = sessionDir.appendingPathComponent("audio", isDirectory: true)
        XCTAssertTrue(exists(audioDir.appendingPathComponent("mic.caf")))
        XCTAssertTrue(exists(audioDir.appendingPathComponent("sys.caf")))
    }

    func testSweepKeepsEverythingWhenRetentionIsForever() throws {
        let sessionDir = try makeSession(
            canonicalFiles: ["mic.caf": Date(timeIntervalSinceNow: -days(30))]
        )

        SessionRepository.cleanupExpiredRetainedBatchAudio(in: sessionsDir, olderThan: nil)

        XCTAssertTrue(
            exists(sessionDir.appendingPathComponent("audio").appendingPathComponent("mic.caf"))
        )
    }

    func testSweepCleansLegacyLayout() throws {
        let stemDate = Date(timeIntervalSinceNow: -days(8))
        let sessionDir = try makeSession(
            legacyFiles: ["mic.caf": stemDate, "batch-meta.json": stemDate],
            directoryDate: Date()
        )

        SessionRepository.cleanupExpiredRetainedBatchAudio(in: sessionsDir, olderThan: days(7))

        XCTAssertFalse(exists(sessionDir.appendingPathComponent("mic.caf")))
        XCTAssertFalse(exists(sessionDir.appendingPathComponent("batch-meta.json")))
        XCTAssertTrue(exists(sessionDir.appendingPathComponent("session.json")))
    }

    func testSweepRemovesLoneExpiredBatchMeta() throws {
        // With no stems left, a lone batch-meta.json must not live forever;
        // its own modification date governs.
        let sessionDir = try makeSession(
            canonicalFiles: ["batch-meta.json": Date(timeIntervalSinceNow: -days(8))]
        )

        let removed = SessionRepository.cleanupExpiredRetainedBatchAudio(
            in: sessionsDir,
            olderThan: days(7)
        )

        XCTAssertEqual(removed, ["session_test"])
        XCTAssertFalse(
            exists(sessionDir.appendingPathComponent("audio").appendingPathComponent("batch-meta.json"))
        )
        XCTAssertTrue(exists(sessionDir.appendingPathComponent("session.json")))
    }

    func testSweepKeepsLoneFreshBatchMeta() throws {
        let sessionDir = try makeSession(
            canonicalFiles: ["batch-meta.json": Date(timeIntervalSinceNow: -days(1))]
        )

        SessionRepository.cleanupExpiredRetainedBatchAudio(in: sessionsDir, olderThan: days(7))

        XCTAssertTrue(
            exists(sessionDir.appendingPathComponent("audio").appendingPathComponent("batch-meta.json"))
        )
    }

    func testSweepSkipsSessionsWithActiveBatchAccess() throws {
        let sessionDir = try makeSession(
            named: "session_active",
            canonicalFiles: ["mic.caf": Date(timeIntervalSinceNow: -days(8))]
        )

        let removed = SessionRepository.cleanupExpiredRetainedBatchAudio(
            in: sessionsDir,
            olderThan: days(7),
            excluding: ["session_active"]
        )

        XCTAssertTrue(removed.isEmpty)
        XCTAssertTrue(
            exists(sessionDir.appendingPathComponent("audio").appendingPathComponent("mic.caf"))
        )
    }

    func testSweepDoesNotFollowSymlinkedSessionDirectories() throws {
        // resourceValues follows symlinks: a symlink named session_* must not
        // delete its target's stems.
        let target = try makeSession(
            named: "target_dir",
            canonicalFiles: ["mic.caf": Date(timeIntervalSinceNow: -days(8))]
        )
        let link = sessionsDir.appendingPathComponent("session_link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        SessionRepository.cleanupExpiredRetainedBatchAudio(in: sessionsDir, olderThan: days(7))

        XCTAssertTrue(
            exists(target.appendingPathComponent("audio").appendingPathComponent("mic.caf"))
        )
    }

    func testBatchAccessGuardBlocksSweepAndUserDeleteUntilEnded() async throws {
        let fm = FileManager.default
        let root = sessionsDir!

        // Construct the repository first so the init-time sweep runs on an
        // empty directory; then lay down the expired stems.
        let retention = days(7)
        let repo = SessionRepository(rootDirectory: root, batchAudioRetention: { retention })

        let sessionID = "session_guarded"
        let audioDir = root
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
        try fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let micURL = audioDir.appendingPathComponent("mic.caf")
        fm.createFile(atPath: micURL.path, contents: Data("audio".utf8))
        try fm.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -days(8))],
            ofItemAtPath: micURL.path
        )

        await repo.beginBatchAudioAccess(sessionID: sessionID)

        await repo.sweepExpiredRetainedBatchAudio()
        XCTAssertTrue(fm.fileExists(atPath: micURL.path), "sweep must skip an active batch session")

        let removedWhileActive = await repo.cleanupBatchAudio(sessionID: sessionID)
        XCTAssertFalse(removedWhileActive, "user delete must refuse while a batch run holds the stems")
        XCTAssertTrue(fm.fileExists(atPath: micURL.path))

        await repo.endBatchAudioAccess(sessionID: sessionID)
        await repo.sweepExpiredRetainedBatchAudio()
        XCTAssertFalse(fm.fileExists(atPath: micURL.path), "sweep must apply once the batch run ends")
    }

    func testSweepIgnoresNonSessionDirectories() throws {
        let stemDate = Date(timeIntervalSinceNow: -days(8))
        let sessionDir = try makeSession(
            named: "imported_thing",
            canonicalFiles: ["mic.caf": stemDate]
        )

        SessionRepository.cleanupExpiredRetainedBatchAudio(in: sessionsDir, olderThan: days(7))

        XCTAssertTrue(
            exists(sessionDir.appendingPathComponent("audio").appendingPathComponent("mic.caf"))
        )
    }
}
