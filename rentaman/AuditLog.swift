import Foundation
import SwiftData
import Observation

/// Central writer for the audit trail.
///
/// Every mutation path in the app calls one of the `log*` helpers.
/// The service is intentionally fire-and-forget — the caller's job is
/// to hold a `ModelContext` and pass it in.
///
/// Auto-prune: keeps at most `maxEntries` rows. The check runs every
/// `checkFrequency` inserts so hot paths aren't slowed by a fetch each
/// time.
@Observable
final class AuditLog {

    static let shared = AuditLog()
    private init() {}

    // MARK: - Retention
    private static let maxEntries: Int = 5_000
    private static let checkFrequency: Int = 100
    private var insertsSinceCheck: Int = 0

    // MARK: - Generic Entry Point
    @MainActor
    func log(
        action: AuditAction,
        entityType: AuditEntityType,
        entityId: String,
        entityTitle: String,
        changes: [AuditFieldChange] = [],
        note: String? = nil,
        source: AuditSource = .local,
        context: ModelContext
    ) {
        let entry = AuditEntry(
            entityType: entityType,
            entityId: entityId,
            entityTitle: entityTitle,
            action: action,
            changes: changes,
            note: note,
            source: source
        )
        context.insert(entry)

        insertsSinceCheck += 1
        if insertsSinceCheck >= Self.checkFrequency {
            insertsSinceCheck = 0
            pruneIfNeeded(context: context)
        }

        try? context.save()
    }

    // MARK: - Bill Helpers
    @MainActor
    func billCreated(_ bill: Bill, context: ModelContext) {
        log(
            action: .created,
            entityType: .bill,
            entityId: bill.id,
            entityTitle: bill.title,
            changes: [
                .init(field: "Amount",  old: nil, new: CurrencyFormatter.format(bill.amount, as: .ksh)),
                .init(field: "Category",old: nil, new: bill.category.rawValue),
                .init(field: "Due",     old: nil, new: formatDate(bill.dueDate)),
                .init(field: "Property",old: nil, new: bill.property?.name ?? "(none)")
            ],
            context: context
        )
    }

    @MainActor
    func billUpdated(_ bill: Bill, changes: [AuditFieldChange], context: ModelContext) {
        guard !changes.isEmpty else { return }
        log(
            action: .updated,
            entityType: .bill,
            entityId: bill.id,
            entityTitle: bill.title,
            changes: changes,
            context: context
        )
    }

    @MainActor
    func billMarkedPaid(_ bill: Bill, isPaid: Bool, context: ModelContext) {
        let change = AuditFieldChange(
            field: "Paid",
            old: isPaid ? "No" : "Yes",
            new: isPaid ? "Yes" : "No"
        )
        var extras: [AuditFieldChange] = [change]
        if isPaid {
            extras.append(.init(field: "Payment date",
                                old: nil,
                                new: formatDate(bill.paymentDate ?? Date())))
            extras.append(.init(field: "Method",
                                old: nil,
                                new: bill.paymentMethod.displayName))
        }
        log(
            action: isPaid ? .markedPaid : .markedUnpaid,
            entityType: .bill,
            entityId: bill.id,
            entityTitle: bill.title,
            changes: extras,
            context: context
        )
    }

    @MainActor
    func billMovedToTrash(_ bill: Bill, context: ModelContext) {
        log(
            action: .movedToTrash,
            entityType: .bill,
            entityId: bill.id,
            entityTitle: bill.title,
            context: context
        )
    }

    @MainActor
    func billRestored(_ bill: Bill, context: ModelContext) {
        log(
            action: .restored,
            entityType: .bill,
            entityId: bill.id,
            entityTitle: bill.title,
            context: context
        )
    }

    @MainActor
    func billPurged(id: String, title: String, context: ModelContext) {
        log(
            action: .purged,
            entityType: .bill,
            entityId: id,
            entityTitle: title,
            context: context
        )
    }

    @MainActor
    func billDuplicated(source: Bill, copy: Bill, context: ModelContext) {
        log(
            action: .duplicated,
            entityType: .bill,
            entityId: copy.id,
            entityTitle: copy.title,
            changes: [
                .init(field: "Source",  old: nil, new: source.title),
                .init(field: "New due", old: nil, new: formatDate(copy.dueDate))
            ],
            context: context
        )
    }

    // MARK: - Property Helpers
    @MainActor
    func propertyCreated(_ property: Property, context: ModelContext) {
        log(
            action: .created,
            entityType: .property,
            entityId: property.id,
            entityTitle: property.name,
            changes: [
                .init(field: "Budget", old: nil, new: CurrencyFormatter.format(property.monthlyBudget, as: .ksh))
            ],
            context: context
        )
    }

    @MainActor
    func propertyUpdated(_ property: Property, changes: [AuditFieldChange], context: ModelContext) {
        guard !changes.isEmpty else { return }
        log(
            action: .updated,
            entityType: .property,
            entityId: property.id,
            entityTitle: property.name,
            changes: changes,
            context: context
        )
    }

    @MainActor
    func propertyDeleted(_ property: Property, context: ModelContext) {
        log(
            action: .purged,
            entityType: .property,
            entityId: property.id,
            entityTitle: property.name,
            context: context
        )
    }

    @MainActor
    func propertySetDefault(_ property: Property, context: ModelContext) {
        log(
            action: .setDefault,
            entityType: .property,
            entityId: property.id,
            entityTitle: property.name,
            context: context
        )
    }

    // MARK: - Maintenance
    @MainActor
    func clearAll(context: ModelContext) {
        let descriptor = FetchDescriptor<AuditEntry>()
        guard let all = try? context.fetch(descriptor) else { return }
        for e in all { context.delete(e) }
        try? context.save()
    }

    @MainActor
    func pruneIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<AuditEntry>(
            sortBy: [SortDescriptor<AuditEntry>(\.timestamp, order: .forward)]
        )
        guard let all = try? context.fetch(descriptor) else { return }
        guard all.count > Self.maxEntries else { return }
        let overflow = all.count - Self.maxEntries
        for entry in all.prefix(overflow) {
            context.delete(entry)
        }
        try? context.save()
    }

    // MARK: - Formatters
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}

// MARK: - Snapshots (for computing diffs)
struct BillAuditSnapshot {
    let title: String
    let amount: Double
    let categoryRaw: String
    let dueDate: Date
    let isPaid: Bool
    let paymentDate: Date?
    let paymentMethodRaw: String
    let notes: String?
    let propertyName: String?
    let isRecurring: Bool
    let recurringFrequencyRaw: String
    let isPaused: Bool

    init(_ bill: Bill) {
        self.title = bill.title
        self.amount = bill.amount
        self.categoryRaw = bill.categoryRawValue
        self.dueDate = bill.dueDate
        self.isPaid = bill.isPaid
        self.paymentDate = bill.paymentDate
        self.paymentMethodRaw = bill.paymentMethodRaw
        self.notes = bill.notes
        self.propertyName = bill.property?.name
        self.isRecurring = bill.isRecurring
        self.recurringFrequencyRaw = bill.recurringFrequencyRaw
        self.isPaused = bill.isPaused
    }

    func diff(to bill: Bill) -> [AuditFieldChange] {
        var out: [AuditFieldChange] = []

        if title != bill.title {
            out.append(.init(field: "Title", old: title, new: bill.title))
        }
        if abs(amount - bill.amount) > 0.005 {
            out.append(.init(
                field: "Amount",
                old: CurrencyFormatter.format(amount, as: .ksh),
                new: CurrencyFormatter.format(bill.amount, as: .ksh)
            ))
        }
        if categoryRaw != bill.categoryRawValue {
            out.append(.init(field: "Category", old: categoryRaw, new: bill.categoryRawValue))
        }
        if !Calendar.current.isDate(dueDate, inSameDayAs: bill.dueDate) {
            out.append(.init(field: "Due date", old: formatDate(dueDate), new: formatDate(bill.dueDate)))
        }
        if isPaid != bill.isPaid {
            out.append(.init(field: "Paid", old: isPaid ? "Yes" : "No", new: bill.isPaid ? "Yes" : "No"))
        }
        let oldPayDate = paymentDate.map { formatDate($0) }
        let newPayDate = bill.paymentDate.map { formatDate($0) }
        if isPaid == bill.isPaid && oldPayDate != newPayDate {
            out.append(.init(field: "Payment date", old: oldPayDate, new: newPayDate))
        }
        if paymentMethodRaw != bill.paymentMethodRaw {
            out.append(.init(field: "Payment method", old: paymentMethodRaw, new: bill.paymentMethodRaw))
        }
        let oldNotes = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let newNotes = (bill.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if oldNotes != newNotes {
            out.append(.init(field: "Notes",
                             old: oldNotes.isEmpty ? "(empty)" : oldNotes,
                             new: newNotes.isEmpty ? "(empty)" : newNotes))
        }
        if propertyName != bill.property?.name {
            out.append(.init(field: "Property",
                             old: propertyName ?? "(none)",
                             new: bill.property?.name ?? "(none)"))
        }
        if isRecurring != bill.isRecurring {
            out.append(.init(field: "Recurring", old: isRecurring ? "Yes" : "No", new: bill.isRecurring ? "Yes" : "No"))
        }
        if recurringFrequencyRaw != bill.recurringFrequencyRaw {
            out.append(.init(field: "Frequency", old: recurringFrequencyRaw, new: bill.recurringFrequencyRaw))
        }
        if isPaused != bill.isPaused {
            out.append(.init(field: "Paused", old: isPaused ? "Yes" : "No", new: bill.isPaused ? "Yes" : "No"))
        }
        return out
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}

// MARK: - Property snapshot
struct PropertyAuditSnapshot {
    let name: String
    let address: String?
    let colorHex: String
    let monthlyBudget: Double
    let isDefault: Bool

    init(_ property: Property) {
        self.name = property.name
        self.address = property.address
        self.colorHex = property.colorHex
        self.monthlyBudget = property.monthlyBudget
        self.isDefault = property.isDefault
    }

    func diff(to property: Property) -> [AuditFieldChange] {
        var out: [AuditFieldChange] = []

        if name != property.name {
            out.append(.init(field: "Name", old: name, new: property.name))
        }
        if (address ?? "") != (property.address ?? "") {
            out.append(.init(field: "Address",
                             old: (address?.isEmpty ?? true) ? "(none)" : (address ?? ""),
                             new: (property.address?.isEmpty ?? true) ? "(none)" : (property.address ?? "")))
        }
        if colorHex != property.colorHex {
            out.append(.init(field: "Color", old: colorHex, new: property.colorHex))
        }
        if abs(monthlyBudget - property.monthlyBudget) > 0.005 {
            out.append(.init(
                field: "Budget",
                old: CurrencyFormatter.format(monthlyBudget, as: .ksh),
                new: CurrencyFormatter.format(property.monthlyBudget, as: .ksh)
            ))
        }
        if isDefault != property.isDefault {
            out.append(.init(field: "Default", old: isDefault ? "Yes" : "No", new: property.isDefault ? "Yes" : "No"))
        }
        return out
    }
}