import SwiftUI
import SwiftData

struct AuditLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \AuditEntry.timestamp, order: .reverse)
    private var entries: [AuditEntry]

    @State private var searchText = ""
    @State private var entityFilter: EntityFilter = .all
    @State private var actionFilter: ActionFilter = .all
    @State private var timeFilter: TimeFilter = .all
    @State private var selectedId: String? = nil
    @State private var showingClearConfirm = false

    enum EntityFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case bills = "Bills"
        case properties = "Properties"
        var id: String { rawValue }
    }

    enum ActionFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case created = "Created"
        case updated = "Updated"
        case paid = "Paid"
        case unpaid = "Unpaid"
        case trashed = "Trashed"
        case restored = "Restored"
        case purged = "Purged"
        case duplicated = "Duplicated"
        case setDefault = "Default"
        var id: String { rawValue }

        func matches(_ action: AuditAction) -> Bool {
            switch self {
            case .all:        return true
            case .created:    return action == .created
            case .updated:    return action == .updated
            case .paid:       return action == .markedPaid
            case .unpaid:     return action == .markedUnpaid
            case .trashed:    return action == .movedToTrash
            case .restored:   return action == .restored
            case .purged:     return action == .purged
            case .duplicated: return action == .duplicated
            case .setDefault: return action == .setDefault
            }
        }
    }

    enum TimeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case day = "24h"
        case week = "7d"
        case month = "30d"
        var id: String { rawValue }

        var cutoff: Date? {
            let cal = Calendar.current
            switch self {
            case .all:   return nil
            case .day:   return cal.date(byAdding: .day, value: -1, to: Date())
            case .week:  return cal.date(byAdding: .day, value: -7, to: Date())
            case .month: return cal.date(byAdding: .day, value: -30, to: Date())
            }
        }
    }

    // MARK: - Filtering
    private var filtered: [AuditEntry] {
        var result = entries
        switch entityFilter {
        case .all: break
        case .bills: result = result.filter { $0.entityType == .bill }
        case .properties: result = result.filter { $0.entityType == .property }
        }
        if actionFilter != .all {
            result = result.filter { actionFilter.matches($0.action) }
        }
        if let cutoff = timeFilter.cutoff {
            result = result.filter { $0.timestamp >= cutoff }
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result = result.filter {
                $0.entityTitle.localizedCaseInsensitiveContains(trimmed) ||
                $0.action.label.localizedCaseInsensitiveContains(trimmed)
            }
        }
        return result
    }

    private var selectedEntry: AuditEntry? {
        guard let id = selectedId else { return filtered.first }
        return filtered.first(where: { $0.id == id })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            filterBar
            Divider().opacity(0.5)

            if filtered.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    listPane
                    Divider()
                    detailPane
                        .frame(width: 340)
                }
            }

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 940, height: 640)
        .background(RMDesign.pageBackground)
        .alert("Clear audit log?", isPresented: $showingClearConfirm) {
            Button("Clear", role: .destructive) {
                AuditLog.shared.clearAll(context: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all \(entries.count) audit entr\(entries.count == 1 ? "y" : "ies"). This cannot be undone.")
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(RMDesign.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Audit Log")
                    .font(.system(size: 16, weight: .semibold))
                Text("\(entries.count) entr\(entries.count == 1 ? "y" : "ies") — every change to your bills and properties")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    // MARK: - Filter Bar
    private var filterBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Search title or action…", text: $searchText)
                    .textFieldStyle(.plain).font(.system(size: 12))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26).frame(width: 220)
            .background(RMDesign.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: RMDesign.fieldRadius))
            .overlay(RoundedRectangle(cornerRadius: RMDesign.fieldRadius)
                .stroke(RMDesign.borderColor, lineWidth: 1))

            Picker("", selection: $entityFilter) {
                ForEach(EntityFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented).frame(width: 240)

            Picker("", selection: $actionFilter) {
                ForEach(ActionFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().frame(width: 140)

            Picker("", selection: $timeFilter) {
                ForEach(TimeFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented).frame(width: 200)

            Spacer()

            Text("\(filtered.count) shown")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - List Pane
    private var listPane: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filtered) { entry in
                    row(entry)
                    Divider().opacity(0.4)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func row(_ entry: AuditEntry) -> some View {
        let isSelected = entry.id == selectedId || (selectedId == nil && filtered.first?.id == entry.id)
        Button {
            selectedId = entry.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.action.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color(hex: entry.action.colorHex))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.action.shortLabel)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(hex: entry.action.colorHex))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(hex: entry.action.colorHex).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                        Text(entry.entityTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Text(entry.entityType.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        if !entry.changes.isEmpty {
                            Text("•")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text("\(entry.changes.count) field\(entry.changes.count == 1 ? "" : "s") changed")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Text(shortRelative(entry.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? RMDesign.accentSoft : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail Pane
    @ViewBuilder
    private var detailPane: some View {
        if let entry = selectedEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: entry.action.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Color(hex: entry.action.colorHex))
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.action.label)
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(entry.entityType.label)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(entry.entityTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(2)

                        Text(longAbsolute(entry.timestamp))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Changes
                    if entry.changes.isEmpty {
                        Text(noChangesMessage(entry))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Changes")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.3)

                            ForEach(entry.changes) { change in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(change.field)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)

                                    HStack(alignment: .top, spacing: 6) {
                                        Text(change.old ?? "—")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(RMDesign.danger.opacity(0.85))
                                            .lineLimit(3)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                            .padding(.top, 2)
                                        Text(change.new ?? "—")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(RMDesign.success.opacity(0.9))
                                            .lineLimit(3)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
                            }
                        }
                    }

                    if let note = entry.note, !note.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Note")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.3)
                            Text(note)
                                .font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RMDesign.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
                    }
                }
                .padding(14)
            }
            .background(RMDesign.pageBackground)
        } else {
            VStack {
                Spacer()
                Text("Select an entry")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(RMDesign.pageBackground)
        }
    }

    // MARK: - Empty
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text(entries.isEmpty ? "No activity yet" : "No entries match your filters")
                .font(.system(size: 13, weight: .semibold))
            Text(entries.isEmpty
                 ? "Every change you make will appear here."
                 : "Try adjusting your search, action, or date filter.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer
    private var footer: some View {
        HStack {
            if !entries.isEmpty {
                Button(role: .destructive) {
                    showingClearConfirm = true
                } label: {
                    Label("Clear Log", systemImage: "trash.slash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(RMDesign.danger)
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    // MARK: - Helpers
    private func noChangesMessage(_ entry: AuditEntry) -> String {
        switch entry.action {
        case .created:      return "This \(entry.entityType.label.lowercased()) was created."
        case .movedToTrash: return "This \(entry.entityType.label.lowercased()) was moved to the Trash."
        case .restored:     return "This \(entry.entityType.label.lowercased()) was restored from the Trash."
        case .purged:       return "This \(entry.entityType.label.lowercased()) was permanently deleted."
        case .markedPaid:   return "Marked as paid."
        case .markedUnpaid: return "Marked as unpaid."
        case .setDefault:   return "Set as the default property."
        case .duplicated:   return "Duplicated from another bill."
        case .updated:      return "No field changes recorded."
        }
    }

    private func shortRelative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func longAbsolute(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}