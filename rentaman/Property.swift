import Foundation
import SwiftData

@Model
final class Property {
    @Attribute(.unique) var id: String
    var name: String
    var address: String?
    var colorHex: String
    var monthlyBudget: Double
    var isDefault: Bool = false // NEW: Marks the default property for quick bill entry
    var createdAt: Date
    
    var syncStatusRaw: String
    var updatedAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \Bill.property)
    var bills: [Bill] = []
    
    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pendingUpload }
        set { syncStatusRaw = newValue.rawValue }
    }
    
    init(
        id: String = UUID().uuidString,
        name: String,
        address: String? = nil,
        colorHex: String = "#007AFF",
        monthlyBudget: Double = 0.0,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.colorHex = colorHex
        self.monthlyBudget = monthlyBudget
        self.isDefault = isDefault
        self.createdAt = Date()
        self.updatedAt = Date()
        self.syncStatusRaw = SyncStatus.pendingUpload.rawValue
    }
}
