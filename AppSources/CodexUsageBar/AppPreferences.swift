import CodexUsageCore
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case russian

    var id: String { rawValue }

    var usageDisplayLanguage: UsageDisplayLanguage {
        self == .english ? .english : .russian
    }

    func text(_ english: String, _ russian: String) -> String {
        self == .english ? english : russian
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case blue
    case indigo
    case purple
    case pink
    case orange
    case green
    case teal

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .orange: return .orange
        case .green: return .green
        case .teal: return .teal
        }
    }
}
