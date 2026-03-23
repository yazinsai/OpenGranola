import XCTest
@testable import OpenOatsKit

@MainActor
final class AppCoordinatorIntegrationTests: XCTestCase {

    func testUserStoppedFinalizesSessionAndRefreshesHistory() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("OpenOatsCoordinatorTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)

        let suiteName = "com.openoats.tests.coordinator.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(notesDirectory.path, forKey: "notesFolderPath")
        defaults.set(true, forKey: "hasAcknowledgedRecordingConsent")

        let storage = AppSettingsStorage(
            defaults: defaults,
            secretStore: .ephemeral,
            defaultNotesDirectory: notesDirectory,
            runMigrations: false
        )
        let settings = AppSettings(storage: storage)
        let transcriptStore = TranscriptStore()
        let sessionStore = SessionStore(rootDirectory: root)
        let coordinator = AppCoordinator(
            sessionStore: sessionStore,
            templateStore: TemplateStore(rootDirectory: root),
            notesEngine: NotesEngine(mode: .scripted(markdown: "Unused")),
            transcriptStore: transcriptStore
        )
        coordinator.transcriptionEngine = TranscriptionEngine(
            transcriptStore: transcriptStore,
            settings: settings,
            mode: .scripted([
                Utterance(text: "Let me walk through the rollout plan.", speaker: .you),
                Utterance(text: "The pilot scope sounds good to me.", speaker: .them),
            ])
        )
        coordinator.transcriptLogger = TranscriptLogger(directory: notesDirectory)

        let metadata = MeetingMetadata(
            detectionContext: DetectionContext(
                signal: .manual,
                detectedAt: Date(),
                meetingApp: nil,
                calendarEvent: nil
            ),
            calendarEvent: nil,
            title: "Coordinator Test",
            startedAt: Date(),
            endedAt: nil
        )

        coordinator.handle(.userStarted(metadata), settings: settings)

        for _ in 0..<20 {
            if coordinator.transcriptionEngine?.isRunning == true {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        coordinator.handle(.userStopped, settings: settings)

        for _ in 0..<50 {
            if coordinator.lastEndedSession != nil, !coordinator.sessionHistory.isEmpty {
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard let endedSession = coordinator.lastEndedSession else {
            XCTFail("Expected finalized session")
            return
        }

        XCTAssertEqual(endedSession.utteranceCount, 2)
        XCTAssertTrue(coordinator.sessionHistory.contains(where: { $0.id == endedSession.id }))

        let indices = await sessionStore.loadSessionIndex()
        let persisted = indices.first(where: { $0.id == endedSession.id })
        XCTAssertNotNil(persisted)
        XCTAssertEqual(persisted?.utteranceCount, 2)
        XCTAssertFalse(persisted?.hasNotes ?? true)
    }

    func testFinalizationWritesSidecarWithCorrectMetadata() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("OpenOatsFinalizationTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)

        let suiteName = "com.openoats.tests.finalization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(notesDirectory.path, forKey: "notesFolderPath")
        defaults.set(true, forKey: "hasAcknowledgedRecordingConsent")

        let storage = AppSettingsStorage(
            defaults: defaults,
            secretStore: .ephemeral,
            defaultNotesDirectory: notesDirectory,
            runMigrations: false
        )
        let settings = AppSettings(storage: storage)
        let transcriptStore = TranscriptStore()
        let sessionStore = SessionStore(rootDirectory: root)
        let coordinator = AppCoordinator(
            sessionStore: sessionStore,
            templateStore: TemplateStore(rootDirectory: root),
            notesEngine: NotesEngine(mode: .scripted(markdown: "Test")),
            transcriptStore: transcriptStore
        )
        coordinator.transcriptionEngine = TranscriptionEngine(
            transcriptStore: transcriptStore,
            settings: settings,
            mode: .scripted([
                Utterance(text: "Hello from you.", speaker: .you),
                Utterance(text: "Hello from them.", speaker: .them),
            ])
        )
        coordinator.transcriptLogger = TranscriptLogger(directory: notesDirectory)

        let metadata = MeetingMetadata.manual()
        coordinator.handle(.userStarted(metadata), settings: settings)

        // Wait for engine to start
        for _ in 0..<20 {
            if coordinator.transcriptionEngine?.isRunning == true { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        coordinator.handle(.userStopped, settings: settings)

        // Wait for finalization
        for _ in 0..<50 {
            if case .idle = coordinator.state, coordinator.lastEndedSession != nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Verify state returned to idle
        XCTAssertEqual(coordinator.state, .idle)

        // Verify sidecar was written
        let indices = await sessionStore.loadSessionIndex()
        XCTAssertFalse(indices.isEmpty)
        let session = indices.first!
        XCTAssertFalse(session.hasNotes)
        XCTAssertEqual(session.utteranceCount, 2)
    }

    func testFinalizationTimeoutForcesIdleState() async {
        let coordinator = AppCoordinator()
        let metadata = MeetingMetadata.manual()

        coordinator.handle(.userStarted(metadata))
        XCTAssertEqual(coordinator.isRecording, true)

        coordinator.handle(.userStopped)
        coordinator.handle(.finalizationTimeout)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testDiscardReturnsToIdleWithoutFinalization() async {
        let coordinator = AppCoordinator()
        let metadata = MeetingMetadata.manual()

        coordinator.handle(.userStarted(metadata))
        XCTAssertEqual(coordinator.isRecording, true)

        coordinator.handle(.userDiscarded)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.lastEndedSession)
    }
}
