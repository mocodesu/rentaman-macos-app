import SwiftUI

/// Central place for all user preference keys and enums.
/// Uses @AppStorage so values persist across launches automatically.
enum PreferenceKey {
    static let displayCurrency = "displayCurrency"
    static let appearance = "appAppearance"
    static let dateFormatStyle = "dateFormatStyle"
    static let startWeekOn = "startWeekOn"
    static let showDecimals = "showDecimals"
    static let enableAnimations = "enableAnimations"
    static let notifyDueSoonDays = "notifyDueSoonDays"
    static let notifyOnDueDay = "notifyOnDueDay"
    static let weeklySummary = "weeklySummary"
}

// MARK: - Appearance
enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Date Format
enum DateFormatStyle: String, CaseIterable, Identifiable {
    case system = "System"
    case dmy = "DD/MM/YYYY"
    case mdy = "MM/DD/YYYY"
    case ymd = "YYYY-MM-DD"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .system: return "globe"
        case .dmy: return "calendar"
        case .mdy: return "calendar"
        case .ymd: return "calendar"
        }
    }
}

// MARK: - Week Start
enum WeekStart: String, CaseIterable, Identifiable {
    case sunday = "Sunday"
    case monday = "Monday"
    
    var id: String { self.rawValue }
}