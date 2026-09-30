import Foundation
import SwiftData

@Model
final class Bill {
    @Attribute(.unique) var id: String
    var title: String
    var amount: Double
    var categoryRawValue: String
    var dueDate: Date
    var isPaid: Bool
    var paymentDate: Date?
    var notes: String?
    var receiptIdentifier: String?

    // Recurring metadata
    var isRecurring: Bool = false
    var recurringFrequencyRaw: String = RecurringFrequency.none.rawValue

    // Pause recurring generation
    var isPaused: Bool = false

    // Payment method (raw string; default "Other")
    var paymentMethodRaw: String = PaymentMethod.other.rawValue

    // Soft delete
    var isDeleted: Bool = false
    var deletedAt: Date? = nil

    var syncStatusRaw: String
    var updatedAt: Date

    var property: Property?

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRawValue) ?? .miscellaneous }
        set { categoryRawValue = newValue.rawValue }
    }

    var recurringFrequency: RecurringFrequency {
        get { RecurringFrequency(rawValue: recurringFrequencyRaw) ?? .none }
        set { recurringFrequencyRaw = newValue.rawValue }
    }

    var paymentMethod: PaymentMethod {
        get { PaymentMethod(rawValue: paymentMethodRaw) ?? .other }
        set { paymentMethodRaw = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pendingUpload }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        amount: Double,
        category: ExpenseCategory,
        dueDate: Date,
        isPaid: Bool = false,
        property: Property? = nil,
        isRecurring: Bool = false,
        recurringFrequency: RecurringFrequency = .none,
        isPaused: Bool = false
    ) {
        self.amount = max(0, amount)
        self.id = id
        self.title = title
        self.categoryRawValue = category.rawValue
        self.dueDate = dueDate
        self.isPaid = isPaid
        self.property = property
        self.isRecurring = isRecurring
        self.recurringFrequencyRaw = recurringFrequency.rawValue
        self.isPaused = isPaused
        self.paymentMethodRaw = PaymentMethod.other.rawValue
        self.isDeleted = false
        self.deletedAt = nil
        self.updatedAt = Date()
        self.syncStatusRaw = SyncStatus.pendingUpload.rawValue

        if isPaid {
            self.paymentDate = Date()
        }
    }
}