import Foundation
import SwiftUI

// MARK: - Currency Enum
enum AppCurrency: String, CaseIterable, Identifiable {
    case ksh = "KSH"
    case usd = "USD"
    
    var id: String { self.rawValue }
    
    /// Symbol used for display
    var symbol: String {
        switch self {
        case .ksh: return "Ksh"
        case .usd: return "$"
        }
    }
    
    /// Name shown in pickers
    var displayName: String {
        switch self {
        case .ksh: return "Kenyan Shilling"
        case .usd: return "US Dollar"
        }
    }
}

// MARK: - Exchange Rate
/// Central place for the KSH ↔ USD exchange rate.
/// Update this value periodically, or later fetch it from an API.
enum ExchangeRate {
    static let kshPerUsd: Double = 129.0
}

// MARK: - Currency Formatter
/// Central formatter for all money amounts in the app.
/// All amounts are STORED in KSH (base currency) and displayed in the user's preferred currency.
struct CurrencyFormatter {
    
    /// Formats an amount (stored in KSH) into the display currency with commas and 2 decimals.
    /// Example: `CurrencyFormatter.format(67000, as: .ksh)` → `"Ksh 67,000.00"`
    ///          `CurrencyFormatter.format(67000, as: .usd)` → `"$ 519.38"`
    static func format(_ amountInKsh: Double, as currency: AppCurrency) -> String {
        guard amountInKsh.isFinite else { return "\(currency.symbol) 0.00" }
        
        let value = convert(amountInKsh, to: currency)
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        formatter.locale = Locale(identifier: "en_US")
        
        let numStr = formatter.string(from: NSNumber(value: value)) ?? "0.00"
        return "\(currency.symbol) \(numStr)"
    }
    
    /// Compact version for chart axes (e.g., "67.0K", "$ 5.2K")
    static func compact(_ amountInKsh: Double, as currency: AppCurrency) -> String {
        guard amountInKsh.isFinite else { return "\(currency.symbol) 0" }
        
        let value = convert(amountInKsh, to: currency)
        
        if abs(value) >= 1_000_000 {
            return String(format: "%@ %.1fM", currency.symbol, value / 1_000_000)
        }
        if abs(value) >= 1_000 {
            return String(format: "%@ %.1fK", currency.symbol, value / 1_000)
        }
        return String(format: "%@ %.0f", currency.symbol, value)
    }
    
    /// Plain number string, no symbol (for text fields)
    static func plainNumber(_ amountInKsh: Double, as currency: AppCurrency) -> String {
        guard amountInKsh.isFinite else { return "0.00" }
        let value = convert(amountInKsh, to: currency)
        return String(format: "%.2f", value)
    }
    
    /// Converts a KSH base amount to the target currency
    static func convert(_ amountInKsh: Double, to currency: AppCurrency) -> Double {
        switch currency {
        case .ksh: return amountInKsh
        case .usd: return amountInKsh / ExchangeRate.kshPerUsd
        }
    }
    
    /// Converts a value entered in a given currency BACK to KSH for storage
    static func toKsh(_ amount: Double, from currency: AppCurrency) -> Double {
        switch currency {
        case .ksh: return amount
        case .usd: return amount * ExchangeRate.kshPerUsd
        }
    }
}

// MARK: - Recurring Frequency
enum RecurringFrequency: String, CaseIterable, Identifiable, Codable {
    case none = "None"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case yearly = "Yearly"
    
    var id: String { self.rawValue }
    
    var iconName: String {
        switch self {
        case .none: return "1.circle"
        case .weekly: return "calendar.badge.clock"
        case .monthly: return "calendar"
        case .quarterly: return "calendar.badge.plus"
        case .yearly: return "calendar.circle"
        }
    }
}
