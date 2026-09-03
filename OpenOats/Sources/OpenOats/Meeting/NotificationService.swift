import Foundation
import UserNotifications

/// Manages macOS notification delivery for meeting detection prompts.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    /// UNUserNotificationCenter requires the process to be a registered app
    /// bundle and raises (SIGABRT) on every API call when it isn't. That covers
    /// unbundled runs (`swift run`, which has no bundle identifier) and hosts
    /// that carry an identifier without being an app, such as the `xctest`
    /// runner. When false, all notification methods become no-ops.
    private let isAvailable: Bool = Bundle.main.bundleIdentifier != nil
        && Bundle.main.bundleURL.pathExtension == "app"
    private var hasRequestedPermission = false
    private var pendingTimeoutTask: Task<Void, Never>?

    /// Called when the user taps "Start Transcribing".
    var onAccept: (() -> Void)?

    /// Called when the user taps "Not a Meeting".
    var onNotAMeeting: (() -> Void)?

    /// Called when the user taps "Dismiss".
    var onDismiss: (() -> Void)?

    /// Called when the user taps "Ignore This App".
    var onIgnoreApp: (() -> Void)?

    /// Called when the notification times out (60 seconds).
    var onTimeout: (() -> Void)?

    // MARK: - Action Identifiers

    private static let categoryWithAppID = "MEETING_DETECTED_WITH_APP"
    private static let categoryNoAppID = "MEETING_DETECTED_NO_APP"
    nonisolated static let startAction = "START_TRANSCRIBING"
    nonisolated static let notMeetingAction = "NOT_A_MEETING"
    nonisolated static let ignoreAppAction = "IGNORE_APP"
    nonisolated static let dismissAction = "DISMISS"
    /// Request identifier of the meeting-detection prompt. Only this request
    /// carries the accept / not-a-meeting / ignore-app actions.
    nonisolated static let detectionRequestID = "meeting-detection"
    static let batchCompletedTitle = "Re-transcription Complete"
    static let batchCompletedBody = "Re-transcription is complete. Your meeting transcript has been updated with higher-quality text."
    static let notesFailedTitle = "Notes Generation Failed"
    static let notesFailedFallbackReason = "Meeting notes could not be generated."

    /// Body for the notes-failure notification. Leads with the specific reason —
    /// a missing API key and an unreachable server need different responses from
    /// the user — and ends with the manual remedy.
    static func notesFailedBody(reason: String) -> String {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = trimmed.isEmpty ? notesFailedFallbackReason : trimmed
        return "\(detail) Open the meeting and choose Generate Notes to try again."
    }

    override init() {
        super.init()
        registerCategory()
    }

    // MARK: - Category Registration

    private func registerCategory() {
        guard isAvailable else { return }

        // "Start Transcribing" is the default action (tap on notification body).
        // Only secondary actions appear in the dropdown.
        let notMeeting = UNNotificationAction(
            identifier: Self.notMeetingAction,
            title: "Not a Meeting",
            options: []
        )
        let ignoreApp = UNNotificationAction(
            identifier: Self.ignoreAppAction,
            title: "Ignore This App",
            options: []
        )
        let dismiss = UNNotificationAction(
            identifier: Self.dismissAction,
            title: "Dismiss",
            options: []
        )

        let categoryWithApp = UNNotificationCategory(
            identifier: Self.categoryWithAppID,
            actions: [notMeeting, ignoreApp, dismiss],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let categoryNoApp = UNNotificationCategory(
            identifier: Self.categoryNoAppID,
            actions: [notMeeting, dismiss],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([categoryWithApp, categoryNoApp])
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission

    private func ensurePermission() async -> Bool {
        guard isAvailable else { return false }
        if hasRequestedPermission {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return settings.authorizationStatus == .authorized
        }

        hasRequestedPermission = true
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Notification Delivery

    /// Post a meeting detection notification with the given app name.
    /// Returns false if permission was denied.
    func postMeetingDetected(appName: String?, isCameraTrigger: Bool = false) async -> Bool {
        guard await ensurePermission() else { return false }

        // Cancel any existing timeout
        pendingTimeoutTask?.cancel()
        pendingTimeoutTask = nil

        // Remove previous detection notifications
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [Self.detectionRequestID]
        )

        let content = UNMutableNotificationContent()
        if let appName {
            content.title = "Meeting Detected"
            if isCameraTrigger {
                content.body = "\(appName) — tap to start transcribing."
            } else {
                content.body = "\(appName) is using your microphone. Tap to start transcribing."
            }
        } else {
            if isCameraTrigger {
                content.title = "Camera Active"
                content.body = "Camera is active. Tap to start transcribing."
            } else {
                content.title = "Microphone Active"
                content.body = "A meeting may be in progress. Tap to start transcribing."
            }
        }
        content.sound = .default
        content.categoryIdentifier = appName != nil ? Self.categoryWithAppID : Self.categoryNoAppID

        let request = UNNotificationRequest(
            identifier: Self.detectionRequestID,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            return false
        }

        // Start 60-second timeout
        pendingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            Task { @MainActor [weak self] in
                self?.onTimeout?()
            }
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [Self.detectionRequestID]
            )
        }

        return true
    }

    /// Post a notification when batch transcription completes.
    func postBatchCompleted(sessionID: String) async {
        guard await ensurePermission() else { return }

        let content = UNMutableNotificationContent()
        content.title = Self.batchCompletedTitle
        content.body = Self.batchCompletedBody
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "batch-completed-\(sessionID)",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Post a notification when automatic post-meeting notes generation fails,
    /// so the failure is visible without opening the app.
    func postNotesFailed(sessionID: String, reason: String) async {
        guard await ensurePermission() else { return }

        let content = UNMutableNotificationContent()
        content.title = Self.notesFailedTitle
        content.body = Self.notesFailedBody(reason: reason)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "notes-failed-\(sessionID)",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Remove any pending detection notification.
    func cancelPending() {
        pendingTimeoutTask?.cancel()
        pendingTimeoutTask = nil
        guard isAvailable else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [Self.detectionRequestID]
        )
    }

    // MARK: - Response Routing

    /// What a notification response should do.
    enum ResponseRoute: Equatable {
        case accept
        case notAMeeting
        case ignoreApp
        case dismiss
        /// Not a detection response — the delegate must do nothing at all.
        case none
    }

    /// Routes a notification response by the request that produced it.
    ///
    /// Only the meeting-detection prompt owns the detection callbacks. Every
    /// other notification this app posts (notes failure, batch completion) has
    /// no actions of its own, so a tap on its body arrives as the default
    /// action identifier. Routing on the action alone treated that as "accept"
    /// and started a recording the user never asked for, and cancelled the
    /// timeout of a detection prompt that might still be on screen.
    nonisolated static func route(actionIdentifier: String, requestIdentifier: String) -> ResponseRoute {
        guard requestIdentifier == detectionRequestID else { return .none }

        switch actionIdentifier {
        case startAction:
            return .accept
        case notMeetingAction:
            return .notAMeeting
        case ignoreAppAction:
            return .ignoreApp
        case dismissAction, UNNotificationDismissActionIdentifier:
            return .dismiss
        default:
            // Default action: a tap on the detection prompt's body.
            return .accept
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let route = Self.route(
            actionIdentifier: response.actionIdentifier,
            requestIdentifier: response.notification.request.identifier
        )

        Task { @MainActor [weak self] in
            guard let self, route != .none else { return }

            self.pendingTimeoutTask?.cancel()
            self.pendingTimeoutTask = nil

            switch route {
            case .accept:
                self.onAccept?()
            case .notAMeeting:
                self.onNotAMeeting?()
            case .ignoreApp:
                self.onIgnoreApp?()
            case .dismiss:
                self.onDismiss?()
            case .none:
                break
            }
        }

        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
