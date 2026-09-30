import Foundation
import SwiftData
import Observation

@Observable
final class AddBillViewModel {
    var title: String = ""
    var amountString: String = ""
    var selectedCategory: ExpenseCategory = .miscellaneous
    var selectedPropertyId: String? = nil
    var dueDate: Date = Date()
    var isPaid: Bool = false
    var paymentDate: Date = Date()
    var paymentMethod: PaymentMethod = .other
    var notes: String = ""
    var isRecurring: Bool = false
    var recurringFrequency: RecurringFrequency = .monthly
    var isPaused: Bool = false
    var entryCurrency: AppCurrency = .ksh

    var editingBill: Bill? = nil
    var isEditMode: Bool { editingBill != nil }

    var isValid: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }
        guard let amount = Double(amountString), amount > 0 else { return false }
        guard selectedPropertyId != nil else { return false }
        return true
    }

    var validationErrorMessage: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Please enter a bill title."
        }
        if Double(amountString) == nil || Double(amountString) ?? 0 <= 0 {
            return "Please enter a valid amount greater than 0."
        }
        if selectedPropertyId == nil {
            return "Please select a property."
        }
        return nil
    }

    func loadFrom(_ bill: Bill) {
        editingBill = bill
        title = bill.title
        amountString = String(format: "%.2f", bill.amount)
        selectedCategory = bill.category
        selectedPropertyId = bill.property?.id
        dueDate = bill.dueDate
        isPaid = bill.isPaid
        paymentDate = bill.paymentDate ?? Date()
        paymentMethod = bill.paymentMethod
        notes = bill.notes ?? ""
        isRecurring = bill.isRecurring
        recurringFrequency = bill.recurringFrequency
        isPaused = bill.isPaused
    }

    func prefillFromHistory(bills: [Bill], properties: [Property]) {
        guard amountString.isEmpty else { return }
        guard let propertyId = selectedPropertyId else { return }

        let candidates = bills
            .filter { $0.category == selectedCategory && $0.property?.id == propertyId }
            .sorted { $0.dueDate > $1.dueDate }

        guard let last = candidates.first else { return }
        amountString = String(format: "%.2f", last.amount)
        if title.isEmpty { title = last.title }
    }

    func save(context: ModelContext, properties: [Property]) -> Bool {
        guard isValid else { return false }
        guard let amountInEntryCurrency = Double(amountString) else { return false }
        guard let property = properties.first(where: { $0.id == selectedPropertyId }) else { return false }

        let amountInKsh = CurrencyFormatter.toKsh(amountInEntryCurrency, from: entryCurrency)

        if let existing = editingBill {
            existing.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.amount = amountInKsh
            existing.categoryRawValue = selectedCategory.rawValue
            existing.dueDate = dueDate
            existing.isPaid = isPaid
            existing.paymentDate = isPaid ? paymentDate : nil
            existing.paymentMethodRaw = paymentMethod.rawValue
            existing.notes = notes.isEmpty ? nil : notes
            existing.property = property
            existing.isRecurring = isRecurring
            existing.recurringFrequencyRaw = isRecurring ? recurringFrequency.rawValue : RecurringFrequency.none.rawValue
            existing.isPaused = isRecurring ? isPaused : false
            existing.updatedAt = Date()
            existing.syncStatus = .pendingUpload
        } else {
            let newBill = Bill(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: amountInKsh,
                category: selectedCategory,
                dueDate: dueDate,
                isPaid: isPaid,
                property: property,
                isRecurring: isRecurring,
                recurringFrequency: isRecurring ? recurringFrequency : .none,
                isPaused: isRecurring ? isPaused : false
            )
            if isPaid { newBill.paymentDate = paymentDate }
            newBill.paymentMethodRaw = paymentMethod.rawValue
            newBill.notes = notes.isEmpty ? nil : notes
            context.insert(newBill)
        }

        SyncService.shared.schedulePush()
        return true
    }

    func reset() {
        title = ""
        amountString = ""
        selectedCategory = .miscellaneous
        selectedPropertyId = nil
        dueDate = Date()
        isPaid = false
        paymentDate = Date()
        paymentMethod = .other
        notes = ""
        isRecurring = false
        recurringFrequency = .monthly
        isPaused = false
        editingBill = nil
    }
}