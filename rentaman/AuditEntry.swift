import Foundation
import SwiftData

// MARK: - Enums
enum AuditAction: String, Codable, CaseIterable {
    case created
    case updated
    case markedPaid
    case markedUnpaid
    case movedToTrash
    case restored
    case purged
    case duplicated
    case setDefault

    var label: String {
        switch self {
        case .created:      return "Created"
        case .updated:      return "Updated"
        case .markedPaid:   return "Marked paid"
        case .markedUnpaid: return "Marked unpaid"
        case .movedToTrash: return "Moved to Trash"
        case .restored:     return "Restored"
        case .purged:       return "Permanently deleted"
        case .duplicated:   return "Duplicated"
        case .setDefault:   return "Set as default"
        }
    }

    var shortLabel: String {
        switch self {
        case .created:      return "Created"
        case .updated:      return "Updated"
        case .markedPaid:   return "Paid"
        case .markedUnpaid: return "Unpaid"
        case .movedToTrash: return "Trashed"
        case .restored:     return "Restored"
        case .purged:       return "Purged"
        case .duplicated:   return "Duplicated"
        case .setDefault:   return "Default"
        }
    }

    var icon: String {
        switch self {
        case .created:      return "plus.circle.fill"
        case .updated:      return "pencil.circle.fill"
        case .markedPaid:   return "checkmark.circle.fill"
        case .markedUnpaid: return "circle"
        case .movedToTrash: return "trash.circle.fill"
        case .restored:     return "arrow.uturn.backward.circle.fill"
        case .purged:       return "trash.slash.fill"
        case .duplicated:   return "doc.on.doc.fill"
        case .setDefault:   return "star.circle.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .created:      return "#34C759"  // green
        case .updated:      return "#007AFF"  // blue
        case .markedPaid:   return "#30D158"  // mint
        case .markedUnpaid: return "#FF9500"  // orange
        case .movedToTrash: return "#FF3B30"  // red
        case .restored:     return "#5AC8FA"  // cyan
        case .purged:       return "#AF52DE"  // purple
        case .duplicated:   return "#5856D6"  // indigo
        case .setDefault:   return "#FFCC00"  // yellow
        }
    }
}

enum AuditEntityType: String, Codable, CaseIterable {
    case bill
    case property

    var label: String {
        switch self {
        case .bill:     return "Bill"
        case .property: return "Property"
        }
    }

    var icon: String {
        switch self {
        case .bill:     return "doc.text.fill"
        case .property: return "house.fill"
        }
    }
}

enum AuditSource: String, Codable {
    case local
    case sync
}

// MARK: - Field Change
struct AuditFieldChange: Codable, Hashable, Identifiable {
    var id: String { field + "|" + (old ?? "") + "|" + (new ?? "") }
    let field: String
    let old: String?
    let new: String?
}

// MARK: - Model
@Model
final class AuditEntry {
    @Attribute(.unique) var id: String
    var timestamp: Date

    var entityTypeRaw: String
    var entityId: String
    var entityTitle: String

    var actionRaw: String

    /// JSON-encoded `[AuditFieldChange]`, optional because state-change
    /// actions (paid/unpaid/trash/restore/purge) don't carry field diffs.
    var changesJson: String?

    var note: String?
    var sourceRaw: String

    // MARK: Computed
    var entityType: AuditEntityType {
        AuditEntityType(rawValue: entityTypeRaw) ?? .bill
    }

    var action: AuditAction {
        AuditAction(rawValue: actionRaw) ?? .updated
    }

    var source: AuditSource {
        AuditSource(rawValue: sourceRaw) ?? .local
    }

    var changes: [AuditFieldChange] {
        guard let json = changesJson,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([AuditFieldChange].self, from: data)
        else { return [] }
        return decoded
    }

    // MARK: Init
    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        entityType: AuditEntityType,
        entityId: String,
        entityTitle: String,
        action: AuditAction,
        changes: [AuditFieldChange] = [],
        note: String? = nil,
        source: AuditSource = .local
    ) {
        self.id = id
        self.timestamp = timestamp
        self.entityTypeRaw = entityType.rawValue
        self.entityId = entityId
        self.entityTitle = entityTitle
        self.actionRaw = action.rawValue
        self.changesJson = Self.encodeChanges(changes)
        self.note = note
        self.sourceRaw = source.rawValue
    }

    private static func encodeChanges(_ changes: [AuditFieldChange]) -> String? {
        guard !changes.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(changes),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json
    }
}