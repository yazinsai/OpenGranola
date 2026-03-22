import SwiftUI

extension Speaker {
    var presentationColor: Color {
        switch self {
        case .you:
            Color(red: 0.35, green: 0.55, blue: 0.75)
        case .them:
            Color(red: 0.82, green: 0.6, blue: 0.3)
        case .remote(let number):
            Self.remotePresentationColors[(number - 1) % Self.remotePresentationColors.count]
        }
    }

    private static let remotePresentationColors: [Color] = [
        Color(red: 0.82, green: 0.6, blue: 0.3),
        Color(red: 0.6, green: 0.75, blue: 0.45),
        Color(red: 0.75, green: 0.5, blue: 0.7),
        Color(red: 0.85, green: 0.5, blue: 0.45),
        Color(red: 0.5, green: 0.7, blue: 0.75),
        Color(red: 0.7, green: 0.65, blue: 0.4),
        Color(red: 0.6, green: 0.55, blue: 0.8),
        Color(red: 0.8, green: 0.55, blue: 0.55),
        Color(red: 0.45, green: 0.7, blue: 0.6),
        Color(red: 0.75, green: 0.65, blue: 0.55),
    ]
}
