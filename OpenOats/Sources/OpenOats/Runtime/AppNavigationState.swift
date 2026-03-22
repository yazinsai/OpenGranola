import Foundation
import Observation

@Observable
@MainActor
final class AppNavigationState {
    @ObservationIgnored nonisolated(unsafe) private var _requestedSessionSelectionID: String?
    var requestedSessionSelectionID: String? {
        get { access(keyPath: \.requestedSessionSelectionID); return _requestedSessionSelectionID }
        set { withMutation(keyPath: \.requestedSessionSelectionID) { _requestedSessionSelectionID = newValue } }
    }

    func queueSessionSelection(_ sessionID: String?) {
        requestedSessionSelectionID = sessionID
    }

    func consumeRequestedSessionSelection() -> String? {
        defer { requestedSessionSelectionID = nil }
        return requestedSessionSelectionID
    }
}
