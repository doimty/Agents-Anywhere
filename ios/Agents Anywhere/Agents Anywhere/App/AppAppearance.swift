import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "agentsAnywhere.appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            String(localized: "System")
        case .light:
            String(localized: "Light")
        case .dark:
            String(localized: "Dark")
        }
    }

    var description: String {
        switch self {
        case .system:
            String(localized: "Match the device appearance.")
        case .light:
            String(localized: "Always use the light appearance.")
        case .dark:
            String(localized: "Always use the dark appearance.")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}
