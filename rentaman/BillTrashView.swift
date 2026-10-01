import SwiftUI
import SwiftData

struct BillTrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appCurrency) private var currency: AppCurrency

    @Query(filter: #Predicate<Bill> { $0.isDeleted == true },
           sort: \Bill.deletedAt, order: .reverse)
    private var deletedBills: [Bill]

    @State private var selection = Set<Bill.ID>()
    @State private var showingPurgeAllConfirm = false
    @State private var showingEmptyPurgeConfirm = false

    private var sorted: [Bill] {
        deletedBills.sorted {
            ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            if deletedBills.isEmpty {
                emptyState
            } else {
                tableArea
            }

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 720, height: 560)
        .background(RMDesign.pageBackground)
        .alert("Delete permanently?", isPresented: $showingPurgeAllConfirm) {
            Button("Purge All", role: .destructive) { purgeAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes **\(deletedBills.count) bill\(deletedBills.count == 1 ? "" : "s")** from every device. This cannot be undone.")
        }
        .alert("Delete permanently?", isPresented: $showingEmptyPurgeConfirm) {
            Button("Delete", role: .destructive) { purgeSelection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently remove **\(selection.count) bill\(selection.count == 1 ? "" : "s")** from every device?")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(RMDesign.danger)
            VStack(alignment: .leading, spacing: 1) {
                Text("Trash")
                    .font(.system(size: 16, weight: .semibold))
                Text(deletedBills.isEmpty
                     ? "Nothing here"
                     : "\(deletedBills.count) bill\(deletedBills.count == 1 ? "" : "s") — restore or permanently delete")
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

    private var tableArea: some View {
        Table(sorted, selection: $selection) {
            TableColumn("Title") { bill in
                HStack(spacing: 8) {
                    Image(systemName: bill.category.iconName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(bill.category.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(bill.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                        if let prop = bill.property {
                            Text(prop.name)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .width(min: 180, ideal: 240)

            TableColumn("Amount") { bill in
                Text(CurrencyFormatter.format(bill.amount, as: currency))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            .width(110)

            TableColumn("Was Due") { bill in
                Text(bill.dueDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .width(110)

            TableColumn("Deleted") { bill in
                if let date = bill.deletedAt {
                    Text(relativeTime(date))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            .width(100)

            TableColumn("") { bill in
                HStack(spacing: 4) {
                    Button {
                        restore(bill)
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 12)).foregroundStyle(RMDesign.success)
                    }
                    .buttonStyle(.borderless)
                    .help("Restore")

                    Button {
                        purge(bill)
                    } label: {
                        Image(systemName: "trash.slash.fill")
                            .font(.system(size: 12)).foregroundStyle(RMDesign.danger)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete permanently")
                }
            }
            .width(70)
        }
        .contextMenu(forSelectionType: Bill.ID.self) { ids in
            if !ids.isEmpty {
                Button {
                    for bill in sorted where ids.contains(bill.id) {
                        restore(bill)
                    }
                } label: {
                    Label(ids.count == 1 ? "Restore" : "Restore \(ids.count) Bills",
                          systemImage: "arrow.uturn.backward")
                }
                Divider()
                Button(role: .destructive) {
                    showingEmptyPurgeConfirm = true
                } label: {
                    Label(ids.count == 1 ? "Delete Permanently" : "Delete \(ids.count) Permanently",
                          systemImage: "trash.slash")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Trash is empty")
                .font(.system(size: 14, weight: .semibold))
            Text("Deleted bills appear here until you restore them or delete them permanently.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var footer: some View {
        HStack {
            if !deletedBills.isEmpty {
                Button {
                    showingPurgeAllConfirm = true
                } label: {
                    Label("Purge All", systemImage: "trash.slash.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(RMDesign.danger)
                .disabled(deletedBills.isEmpty)
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    // MARK: - Actions
    private func restore(_ bill: Bill) {
        bill.isDeleted = false
        bill.deletedAt = nil
        bill.syncStatus = .pendingUpload
        bill.updatedAt = Date()

        AuditLog.shared.billRestored(bill, context: modelContext)

        try? modelContext.save()
        SyncService.shared.schedulePush()
    }

    private func purge(_ bill: Bill) {
        AuditLog.shared.billPurged(id: bill.id, title: bill.title, context: modelContext)
        Task { await SyncService.shared.permanentlyDeleteBill(bill) }
    }

    private func purgeSelection() {
        let targets = sorted.filter { selection.contains($0.id) }
        for bill in targets {
            AuditLog.shared.billPurged(id: bill.id, title: bill.title, context: modelContext)
            Task { await SyncService.shared.permanentlyDeleteBill(bill) }
        }
        selection.removeAll()
    }

    private func purgeAll() {
        for bill in deletedBills {
            AuditLog.shared.billPurged(id: bill.id, title: bill.title, context: modelContext)
            Task { await SyncService.shared.permanentlyDeleteBill(bill) }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}