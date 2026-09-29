import Foundation
import SwiftUI

/// The strict list of categories RentaMan tracks.
enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    // Housing & Utilities
    case rent               = "Rent"
    case water              = "Water"
    case electricity        = "Electricity"
    case cookingGas         = "Cooking Gas"
    case wifi               = "Wifi"
    case utilities          = "Utilities"
    case houseRepairs       = "House Repairs"
    case maidServices       = "Maid Services"
    
    // Daily Living
    case groceries          = "Groceries"
    case transport          = "Transport"
    case clothing           = "Clothing"
    case personalCare       = "Personal Care"
    case health             = "Health"
    case education          = "Education"
    
    // Financial & Administrative
    case subscriptions      = "Subscriptions"
    case insurance          = "Insurance"
    case shopDebts          = "Shop Debts"
    case charity            = "Charity"
    case refreshmentSavings = "Savings for Refreshment"
    
    // Fallback
    case miscellaneous      = "Miscellaneous"
    
    var id: String { rawValue }
    
    /// SF Symbol name for the category.
    var iconName: String {
        switch self {
        case .rent:               return "house.fill"
        case .water:              return "drop.fill"
        case .electricity:        return "bolt.fill"
        case .cookingGas:         return "flame.fill"
        case .wifi:               return "wifi"
        case .utilities:          return "bolt.horizontal.fill"
        case .houseRepairs:       return "wrench.and.screwdriver.fill"
        case .maidServices:       return "person.2.fill"
        case .groceries:          return "cart.fill"
        case .transport:          return "car.fill"
        case .clothing:           return "tshirt.fill"
        case .personalCare:       return "scissors"
        case .health:             return "cross.case.fill"
        case .education:          return "book.fill"
        case .subscriptions:      return "tv.fill"
        case .insurance:          return "shield.lefthalf.filled"
        case .shopDebts:          return "creditcard.fill"
        case .charity:            return "heart.fill"
        case .refreshmentSavings: return "star.fill"
        case .miscellaneous:      return "ellipsis.circle.fill"
        }
    }
    
    /// Deterministic color per category. Switch-based — cannot overflow.
    /// Uses custom RGB values where standard SwiftUI colors are already taken.
    var color: Color {
        switch self {
        case .rent:               return .blue
        case .water:              return .cyan
        case .electricity:        return .yellow
        case .cookingGas:         return .red
        case .wifi:               return .purple
        case .utilities:          return Color(red: 0.42, green: 0.58, blue: 0.78)
        case .houseRepairs:       return .gray
        case .maidServices:       return .pink
        case .groceries:          return .green
        case .transport:          return .orange
        case .clothing:           return Color(red: 0.72, green: 0.42, blue: 0.95)
        case .personalCare:       return Color(red: 0.92, green: 0.55, blue: 0.75)
        case .health:             return Color(red: 0.90, green: 0.30, blue: 0.35)
        case .education:          return .indigo
        case .subscriptions:      return Color(red: 0.95, green: 0.45, blue: 0.65)
        case .insurance:          return Color(red: 0.35, green: 0.55, blue: 0.72)
        case .shopDebts:          return .brown
        case .charity:            return Color(red: 0.30, green: 0.72, blue: 0.55)
        case .refreshmentSavings: return .mint
        case .miscellaneous:      return .teal
        }
    }
    
    /// Short description shown in tooltips.
    var helpText: String {
        switch self {
        case .rent:               return "Monthly rent for a property"
        case .water:              return "Water bill"
        case .electricity:        return "Electricity / KPLC bill"
        case .cookingGas:         return "LPG / cooking gas refill"
        case .wifi:               return "Internet / broadband"
        case .utilities:          return "Trash collection, sewerage, other utilities"
        case .houseRepairs:       return "Repairs, plumbing, electrical fixes"
        case .maidServices:       return "Housekeeper or cleaning services"
        case .groceries:          return "Food and household supplies"
        case .transport:          return "Fuel, matatu, taxi, vehicle maintenance"
        case .clothing:           return "Clothes, shoes, accessories"
        case .personalCare:       return "Haircut, salon, grooming, cosmetics"
        case .health:             return "Doctor, pharmacy, hospital, medical"
        case .education:          return "School fees, tuition, books, uniforms"
        case .subscriptions:      return "TV, streaming, digital subscriptions"
        case .insurance:          return "Insurance premiums (health, home, car)"
        case .shopDebts:          return "Debts owed to shops or individuals"
        case .charity:            return "Zakat, sadaqah, donations"
        case .refreshmentSavings: return "Savings for entertainment / travel"
        case .miscellaneous:      return "Anything that doesn't fit above"
        }
    }
}