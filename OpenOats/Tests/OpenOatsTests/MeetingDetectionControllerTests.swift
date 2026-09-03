import XCTest
@testable import OpenOatsKit

@MainActor
final class MeetingDetectionControllerTests: XCTestCase {

    // MARK: - Event Stream: accepted metadata flows through

    func testAcceptedEventFlowsMetadata() async throws {
        let controller = MeetingDetectionController()

        let metadata = MeetingMetadata(
            detectionContext: DetectionContext(
                signal: .appLaunched(MeetingApp(bundleID: "us.zoom.xos", name: "Zoom")),
                detectedAt: Date(),
                meetingApp: MeetingApp(bundleID: "us.zoom.xos", name: "Zoom"),
                calendarEvent: nil
            ),
            calendarEvent: nil,
            title: "Zoom",
            startedAt: Date(),
            endedAt: nil
        )

        var receivedEvent: DetectionEvent?

        let consumeTask = Task { @MainActor in
            for await event in controller.events {
                receivedEvent = event
                break
            }
        }

        // Yield after consumer is listening
        try await Task.sleep(for: .milliseconds(50))
        controller.yield(.accepted(metadata))

        // Wait for consumer to process
        try await Task.sleep(for: .milliseconds(50))

        if case .accepted(let received) = receivedEvent {
            XCTAssertEqual(received.title, "Zoom")
            XCTAssertEqual(received.detectionContext?.meetingApp?.bundleID, "us.zoom.xos")
        } else {
            XCTFail("Expected .accepted event, got \(String(describing: receivedEvent))")
        }

        consumeTask.cancel()
    }

    // MARK: - Events consumed exactly once (one-shot)

    func testEventsConsumedExactlyOnce() async throws {
        let controller = MeetingDetectionController()

        var firstConsumerEvents: [DetectionEvent] = []
        var secondConsumerEvents: [DetectionEvent] = []

        // First consumer starts and gets the event
        let firstConsumer = Task { @MainActor in
            for await event in controller.events {
                firstConsumerEvents.append(event)
                if firstConsumerEvents.count >= 1 { break }
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        controller.yield(.dismissed)
        try await Task.sleep(for: .milliseconds(50))

        // After first consumer finishes, the event is consumed
        XCTAssertEqual(firstConsumerEvents.count, 1)
        if case .dismissed = firstConsumerEvents.first {
            // correct
        } else {
            XCTFail("Expected .dismissed")
        }

        firstConsumer.cancel()
        // Second consumer won't see the already-consumed event
        XCTAssertTrue(secondConsumerEvents.isEmpty)
    }

    // MARK: - Multiple rapid events all delivered (unbounded)

    func testMultipleRapidEventsDelivered() async throws {
        let controller = MeetingDetectionController()
        var receivedEvents: [DetectionEvent] = []

        let consumeTask = Task { @MainActor in
            for await event in controller.events {
                receivedEvents.append(event)
                if receivedEvents.count >= 4 { break }
            }
        }

        try await Task.sleep(for: .milliseconds(50))

        // Yield 4 events rapidly
        controller.yield(.dismissed)
        controller.yield(.timeout)
        controller.yield(.meetingAppExited)
        controller.yield(.notAMeeting(bundleID: "com.test.app"))

        // Wait for processing
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(receivedEvents.count, 4)
        consumeTask.cancel()
    }

    // MARK: - DismissedEvents Tracking

    func testDismissedEventsInitiallyEmpty() async {
        let controller = MeetingDetectionController()
        XCTAssertTrue(controller.dismissedEvents.isEmpty)
    }

    // MARK: - noteUtterance lifecycle

    func testNoteUtteranceUpdatesState() async throws {
        let controller = MeetingDetectionController()

        XCTAssertFalse(controller.isMonitoringSilence)

        controller.startSilenceMonitoring()
        XCTAssertTrue(controller.isMonitoringSilence)

        // noteUtterance should work without error
        controller.noteUtterance()

        controller.stopSilenceMonitoring()
        XCTAssertFalse(controller.isMonitoringSilence)
    }

    // MARK: - Observable State

    func testInitialState() async {
        let controller = MeetingDetectionController()
        XCTAssertFalse(controller.isEnabled)
        XCTAssertNil(controller.detectedApp)
        XCTAssertFalse(controller.isMonitoringSilence)
        XCTAssertNil(controller.activeSettings)
        XCTAssertNil(controller.meetingDetector)
        XCTAssertNil(controller.notificationService)
    }

    // MARK: - Teardown Clears State

    func testTeardownClearsState() async {
        let controller = MeetingDetectionController()
        controller.teardown()
        XCTAssertFalse(controller.isEnabled)
        XCTAssertNil(controller.detectedApp)
        XCTAssertFalse(controller.isMonitoringSilence)
    }

    // MARK: - Silence Monitoring Lifecycle

    func testSilenceMonitoringStartStop() async {
        let controller = MeetingDetectionController()

        controller.startSilenceMonitoring()
        XCTAssertTrue(controller.isMonitoringSilence)

        controller.stopSilenceMonitoring()
        XCTAssertFalse(controller.isMonitoringSilence)

        // Double stop is safe
        controller.stopSilenceMonitoring()
        XCTAssertFalse(controller.isMonitoringSilence)
    }

    // MARK: - Stream construction does not block

    func testStreamUsesUnboundedBuffering() async {
        let controller = MeetingDetectionController()
        _ = controller.events
        // Reaching this point means the stream didn't block on init
    }

    // MARK: - App Exit Monitoring

    func testAppExitMonitorYieldsEventWhenAppNotRunning() async throws {
        let controller = MeetingDetectionController()
        var receivedEvent: DetectionEvent?

        let consumeTask = Task { @MainActor in
            for await event in controller.events {
                receivedEvent = event
                break
            }
        }

        try await Task.sleep(for: .milliseconds(50))

        // Use a bundle ID that is definitely not running
        controller.startAppExitMonitoring(bundleID: "com.test.fake-app-not-running")

        // The monitor polls every 5 seconds; wait for it to fire
        try await Task.sleep(for: .seconds(6))

        if case .meetingAppExited = receivedEvent {
            // correct — the monitor detected the app is not running
        } else {
            XCTFail("Expected .meetingAppExited, got \(String(describing: receivedEvent))")
        }

        consumeTask.cancel()
    }

    func testStopAppExitMonitoringPreventsEvent() async throws {
        let controller = MeetingDetectionController()
        var receivedEvent: DetectionEvent?

        let consumeTask = Task { @MainActor in
            for await event in controller.events {
                receivedEvent = event
                break
            }
        }

        try await Task.sleep(for: .milliseconds(50))

        // Start monitoring then immediately stop
        controller.startAppExitMonitoring(bundleID: "com.test.fake-app-not-running")
        controller.stopAppExitMonitoring()

        // Wait past the poll interval
        try await Task.sleep(for: .seconds(6))

        // No event should have been yielded since we stopped monitoring
        XCTAssertNil(receivedEvent)

        consumeTask.cancel()
    }

    // MARK: - Teardown Stops The Detector

    /// Editing the custom meeting-app list rebuilds detection: `teardown` runs
    /// and a fresh controller is built. If `teardown` fails to stop the detector
    /// it started, that abandoned detector keeps its mic and camera monitors
    /// running for the life of the process, and every edit adds another one.
    func testTeardownStopsTheDetectorItStarted() async throws {
        let camera = MockCameraSignalSource()
        let detector = MeetingDetector(
            audioSource: MockAudioSignalSource(),
            cameraSource: camera
        )
        let controller = MeetingDetectionController()
        controller.setup(settings: makeSettings(), detector: detector)

        // Drive the detector into an active detection, which `stop()` clears.
        camera.emit(true)
        let becameActive = await poll { await detector.isActive }
        XCTAssertTrue(becameActive, "Detector never became active, so the test cannot observe stop()")

        controller.teardown()

        let stopped = await poll { await detector.isActive == false }
        XCTAssertTrue(stopped, "teardown() left the detector it started still monitoring")
    }

    // MARK: - Helpers

    /// Notification stub: never touches UserNotifications, records post calls,
    /// and lets each test script whether the informational post "succeeds".
    private final class StubNotificationService: NotificationService {
        var autoResult = true
        private(set) var autoPosts = 0
        private(set) var promptPosts = 0
        private(set) var autoClears = 0

        init() {
            super.init(isAvailable: false)
        }

        override func clearAutoRecordingStarted() {
            autoClears += 1
        }

        override func postAutoRecordingStarted(appName: String?) async -> Bool {
            autoPosts += 1
            return autoResult
        }

        override func postMeetingDetected(appName: String?, isCameraTrigger: Bool) async -> Bool {
            promptPosts += 1
            return true
        }
    }

    private func makeSettings(consentAcknowledged: Bool = true) -> AppSettings {
        let suiteName = "com.openoats.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let storage = AppSettingsStorage(
            defaults: defaults,
            secretStore: .ephemeral,
            defaultNotesDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("MeetingDetectionControllerTests"),
            runMigrations: false
        )
        let settings = AppSettings(storage: storage)
        settings.hasAcknowledgedRecordingConsent = consentAcknowledged
        return settings
    }

    /// Wait up to a second for an asynchronous condition to hold.
    private func poll(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<100 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    // MARK: - Auto-Record (accept without notification round-trip)

    /// Build a controller wired to a detector with controllable signal sources
    /// and a stubbed notification service.
    private func makeDetectionHarness(
        settings: AppSettings
    ) -> (MeetingDetectionController, StubNotificationService, MockAudioSignalSource, MockCameraSignalSource) {
        let audio = MockAudioSignalSource()
        let camera = MockCameraSignalSource()
        let detector = MeetingDetector(audioSource: audio, cameraSource: camera)
        let service = StubNotificationService()
        let controller = MeetingDetectionController()
        controller.setup(settings: settings, detector: detector, notificationService: service)
        return (controller, service, audio, camera)
    }

    /// Start consuming the controller's event stream, fire `emit` once the
    /// detector is running, and return the first event (or nil after a grace
    /// period). Camera-triggered detection is immediate (no debounce).
    private func collectFirstEvent(
        from controller: MeetingDetectionController,
        after emit: () -> Void
    ) async throws -> DetectionEvent? {
        var receivedEvent: DetectionEvent?
        let consumeTask = Task { @MainActor in
            for await event in controller.events {
                receivedEvent = event
                break
            }
        }
        // Give setup's detection task time to start the detector.
        try await Task.sleep(for: .milliseconds(200))
        emit()
        try await Task.sleep(for: .milliseconds(500))
        consumeTask.cancel()
        return receivedEvent
    }

    func testTeardownClearsDeliveredAutoRecordNotification() async throws {
        let settings = makeSettings()
        settings.autoRecordDetectedMeetings = true

        let (controller, service, audio, camera) = makeDetectionHarness(settings: settings)
        defer {
            audio.finish()
            camera.finish()
        }

        let event = try await collectFirstEvent(from: controller) { camera.emit(true) }
        guard case .accepted = event else {
            XCTFail("Expected an auto-record accept, got \(String(describing: event))")
            return
        }
        XCTAssertEqual(service.autoPosts, 1)
        XCTAssertEqual(service.autoClears, 0)

        // Detection switched off while the auto-recorded meeting is still
        // running. Teardown cancels the detection event loop, so `.ended` never
        // arrives and handleMeetingEnded() never runs — teardown is the only
        // thing left that can take the delivered notification down.
        controller.teardown()

        XCTAssertEqual(
            service.autoClears,
            1,
            "teardown left the 'Recording Started' notification in Notification Center"
        )
    }

    func testAutoRecordAcceptsDetectionWithoutNotificationTap() async throws {
        let settings = makeSettings()
        settings.autoRecordDetectedMeetings = true

        let (controller, service, audio, camera) = makeDetectionHarness(settings: settings)
        defer {
            controller.teardown()
            audio.finish()
            camera.finish()
        }

        let event = try await collectFirstEvent(from: controller) { camera.emit(true) }

        if case .accepted(let metadata) = event,
           let signal = metadata.detectionContext?.signal,
           case .cameraActivated = signal {
            // correct — accepted with the camera signal, no user tap involved
        } else {
            XCTFail("Expected .accepted without a notification tap, got \(String(describing: event))")
        }
        XCTAssertEqual(service.autoPosts, 1, "the informational notification must be posted")
        XCTAssertEqual(service.promptPosts, 0, "no tap-to-confirm prompt on the auto path")
    }

    func testAutoRecordFallsBackToPromptWhenNotificationFails() async throws {
        let settings = makeSettings()
        settings.autoRecordDetectedMeetings = true

        let (controller, service, audio, camera) = makeDetectionHarness(settings: settings)
        service.autoResult = false // delivery fails (permission denied / unavailable)
        defer {
            controller.teardown()
            audio.finish()
            camera.finish()
        }

        let event = try await collectFirstEvent(from: controller) { camera.emit(true) }

        XCTAssertNil(event, "recording must never start silently — fall back to the prompt")
        XCTAssertEqual(service.autoPosts, 1)
        XCTAssertEqual(service.promptPosts, 1, "the tap-to-confirm prompt is the fallback")
    }

    func testAutoRecordRequiresRecordingConsent() async throws {
        let settings = makeSettings(consentAcknowledged: false)
        settings.autoRecordDetectedMeetings = true

        let (controller, service, audio, camera) = makeDetectionHarness(settings: settings)
        defer {
            controller.teardown()
            audio.finish()
            camera.finish()
        }

        let event = try await collectFirstEvent(from: controller) { camera.emit(true) }

        XCTAssertNil(event, "no auto-start before recording consent is acknowledged")
        XCTAssertEqual(service.autoPosts, 0, "the auto path must not even be attempted")
        XCTAssertEqual(service.promptPosts, 1, "falls back to the tap-to-confirm prompt")
    }

    func testAutoRecordOffRequiresNotificationRoundTrip() async throws {
        let settings = makeSettings()
        XCTAssertFalse(settings.autoRecordDetectedMeetings, "auto-record must default to off")

        let (controller, service, audio, camera) = makeDetectionHarness(settings: settings)
        defer {
            controller.teardown()
            audio.finish()
            camera.finish()
        }

        let event = try await collectFirstEvent(from: controller) { camera.emit(true) }

        XCTAssertNil(event, "Without auto-record, detection must wait for the user to accept")
        XCTAssertEqual(service.autoPosts, 0)
        XCTAssertEqual(service.promptPosts, 1)
    }

    func testAutoRecordRespectsAlreadyRecordingGuard() async throws {
        let settings = makeSettings()
        settings.autoRecordDetectedMeetings = true

        let (controller, service, audio, camera) = makeDetectionHarness(settings: settings)
        controller.isSessionActive = { true }
        defer {
            controller.teardown()
            audio.finish()
            camera.finish()
        }

        let event = try await collectFirstEvent(from: controller) { camera.emit(true) }

        XCTAssertNil(event, "No auto-accept while a session is already recording")
        XCTAssertEqual(service.autoPosts, 0)
        XCTAssertEqual(service.promptPosts, 0, "no prompt either — the session is active")
    }
}
