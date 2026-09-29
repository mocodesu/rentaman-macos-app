import Foundation
import SwiftUI

/// The strict list of categories RentaMan tracks.
enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case rent = "Rent"
    case water = "Water"
    case electricity = "Electricity"
    case wifi = "Wifi"
    case groceries = "Groceries"
    case education = "Education"
    case transport = "Transport"
    case cookingGas = "Cooking Gas"
    case maidServices = "Maid Services"
    case shopDebts = "Shop Debts"
    case houseRepairs = "House Repairs"
    case refreshmentSavings = "Savings for Refreshment"
    case miscellaneous = "Miscellaneous"
    
    var id: String { self.rawValue }
    
    /// Provides a system icon for each category to make the UI look professional.
    var iconName: String {
        switch self {
        case .rent: return "house.fill"
        case .water: return "drop.fill"
        case .electricity: return "bolt.fill"
        case .wifi: return "wifi"
        case .groceries: return "cart.fill"
        case .education: return "book.fill"
        case .transport: return "car.fill"
        case .cookingGas: return "flame.fill"
        case .maidServices: return "person.2.fill"
        case .shopDebts: return "creditcard.fill"
        case .houseRepairs: return "wrench.and.screwdriver.fill"
        case .refreshmentSavings: return "star.fill"
        case .miscellaneous: return "ellipsis.circle.fill"
        }
    }
    
    /// Deterministic color for each category.
    /// Uses a switch statement — NO arithmetic, so it is IMPOSSIBLE to overflow.
    var color: Color {
        switch self {
        case .rent:                    return .blue
        case .water:                   return .cyan
        case .electricity:             return .yellow
        case .wifi:                    return .purple
        case .groceries:               return .green
        case .education:               return .indigo
        case .transport:               return .orange
        case .cookingGas:              return .red
        case .maidServices:            return .pink
        case .shopDebts:               return .brown
        case .houseRepairs:            return .gray
        case .refreshmentSavings:      return .mint
        case .miscellaneous:           return .teal
        }
    }
}
