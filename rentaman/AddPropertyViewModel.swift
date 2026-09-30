import Foundation
import SwiftData
import Observation

@Observable
final class AddPropertyViewModel {
    var name: String = ""
    var address: String = ""
    var monthlyBudgetString: String = ""
    var colorHex: String = "#007AFF"
    var isDefault: Bool = false

    var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        guard let budget = Double(monthlyBudgetString), budget >= 0 else { return false }
        return true
    }

    var validationErrorMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Please enter a property name."
        }
        if Double(monthlyBudgetString) == nil || Double(monthlyBudgetString) ?? -1 < 0 {
            return "Please enter a valid monthly budget (0 or greater)."
        }
        return nil
    }

    func save(context: ModelContext, allProperties: [Property]) -> Bool {
        guard isValid, let budget = Double(monthlyBudgetString) else { return false }

        if isDefault {
            for prop in allProperties {
                prop.isDefault = false
                prop.syncStatus = .pendingUpload
                prop.updatedAt = Date()
            }
        }

        let forceDefault = allProperties.isEmpty || isDefault

        let newProperty = Property(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            address: address.isEmpty ? nil : address,
            colorHex: colorHex,
            monthlyBudget: budget,
            isDefault: forceDefault
        )

        context.insert(newProperty)

        AuditLog.shared.propertyCreated(newProperty, context: context)
        if forceDefault {
            AuditLog.shared.propertySetDefault(newProperty, context: context)
        }

        SyncService.shared.schedulePush()
        return true
    }

    func reset() {
        name = ""
        address = ""
        monthlyBudgetString = ""
        colorHex = "#007AFF"
        isDefault = false
    }
}