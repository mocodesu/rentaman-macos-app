import Foundation
import SwiftUI

/// How a bill was paid. Only meaningful once `Bill.isPaid == true`,
/// but stored unconditionally so switching paid↔unpaid never loses it.
enum PaymentMethod: String, Codable, CaseIterable, Identifiable {
    case cash         = "Cash"
    case mpesa        = "M-Pesa"
    case airtelMoney  = "Airtel Money"
    case bank         = "Bank Transfer"
    case card         = "Card"
    case cheque       = "Cheque"
    case other        = "Other"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var iconName: String {
        switch self {
        case .cash:        return "banknote"
        case .mpesa:       return "iphone.gen3"
        case .airtelMoney: return "iphone"
        case .bank:        return "building.columns.fill"
        case .card:        return "creditcard.fill"
        case .cheque:      return "doc.text.fill"
        case .other:       return "ellipsis.circle"
        }
    }

    /// Brand-ish colors — M-Pesa green, Airtel red, etc.
    var color: Color {
        switch self {
        case .cash:        return Color(red: 0.20, green: 0.70, blue: 0.35)
        case .mpesa:       return Color(red: 0.00, green: 0.65, blue: 0.35)
        case .airtelMoney: return Color(red: 0.90, green: 0.15, blue: 0.15)
        case .bank:        return .blue
        case .card:        return .purple
        case .cheque:      return .brown
        case .other:       return .gray
        }
    }
}