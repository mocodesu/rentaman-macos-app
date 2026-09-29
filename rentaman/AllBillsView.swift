import SwiftUI
import SwiftData

struct AllBillsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCurrency) private var currency: AppCurrency
    @Query private var allBills: [Bill]
    @Query private var properties: [Property]
    
    @State private var selection = Set<Bill.ID>()
    @State private var sortOrder = [KeyPathComparator(\Bill.dueDate, order: .reverse)]
    @State private var searchText = ""
    @State private var filterStatus: FilterStatus = .all
    @State private var selectedPropertyId: String? = nil
    
    // 🔧 Use a wrapper so .sheet(item:) has a stable, non-optional identity
    @State private var editingBillWrapper: EditingBillWrapper? = nil
    
    enum FilterStatus: String, CaseIterable, Identifiable {
        case all = "All"
        case unpaid = "Unpaid"
        case paid = "Paid"
        var id: String { self.rawValue }
    }
    
    /// Wrapper that is safely Identifiable for .sheet(item:)
    struct EditingBillWrapper: Identifiable {
        let id: String
        let bill: Bill
    }
    
    private var filteredBills: [Bill] {
        var result = allBills
        if let propId = selectedPropertyId {
            result = result.filter { $0.property?.id == propId }
        }
        switch filterStatus {
        case .unpaid: result = result.filter { !$0.isPaid }
        case .paid: result = result.filter { $0.isPaid }
        case .all: break
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed) ||
                $0.category.rawValue.localizedCaseInsensitiveContains(trimmed) ||
                ($0.property?.name.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
        }
        return result.sorted(using: sortOrder)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.title)
                        .foregroundStyle(.blue)
                    Text("All Bills")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search bills...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(7)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .frame(maxWidth: 260)
                    
                    Picker(selection: $selectedPropertyId) {
                        Text("All Properties").tag(nil as String?)
                        ForEach(properties) { prop in
                            Text(prop.name).tag(prop.id as String?)
                        }
                    } label: {
                        Label("Property", systemImage: "house")
                    }
                    .labelsHidden()
                    .frame(width: 170)
                    
                    Picker(selection: $filterStatus) {
                        ForEach(FilterStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    } label: {
                        Label("Status", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                    
                    Spacer()
                }
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            if filteredBills.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No bills found")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Try adjusting your filters or add a new bill.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            } else {
                Table(filteredBills, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Paid") { (bill: Bill) in
                        Toggle("", isOn: Binding(
                            get: { bill.isPaid },
                            set: { newValue in
                                bill.isPaid = newValue
                                bill.paymentDate = newValue ? Date() : nil
                                bill.syncStatus = .pendingUpload
                                bill.updatedAt = Date()
                                SyncService.shared.schedulePush()
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    }
                    .width(45)
                    
                    TableColumn("Title", value: \.title) { (bill: Bill) in
                        HStack(spacing: 6) {
                            if bill.isRecurring {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                    .help("Recurring: \(bill.recurringFrequency.rawValue)")
                            }
                            Text(bill.title)
                                .fontWeight(.medium)
                        }
                    }
                    .width(min: 150, ideal: 220)
                    
                    TableColumn("Property") { (bill: Bill) in
                        if let prop = bill.property {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: prop.colorHex))
                                    .frame(width: 8, height: 8)
                                Text(prop.name)
                            }
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 100, ideal: 140)
                    
                    TableColumn("Category") { (bill: Bill) in
                        HStack(spacing: 6) {
                            Image(systemName: bill.category.iconName)
                                .foregroundStyle(bill.category.color)
                            Text(bill.category.rawValue)
                        }
                    }
                    .width(min: 130, ideal: 160)
                    
                    TableColumn("Amount", value: \.amount) { (bill: Bill) in
                        Text(CurrencyFormatter.format(bill.amount, as: currency))
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    .width(min: 110, ideal: 140)
                    
                    TableColumn("Due Date", value: \.dueDate) { (bill: Bill) in
                        HStack(spacing: 6) {
                            Text(bill.dueDate.formatted(date: .abbreviated, time: .omitted))
                            if !bill.isPaid && bill.dueDate < Date() {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.red)
                                    .help("Overdue")
                            }
                        }
                    }
                    .width(min: 110, ideal: 130)
                    
                    TableColumn("") { (bill: Bill) in
                        Button {
                            // ✅ Set the wrapper — sheet opens with a valid item
                            editingBillWrapper = EditingBillWrapper(id: bill.id, bill: bill)
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.borderless)
                        .help("Edit this bill")
                    }
                    .width(40)
                }
                .contextMenu(forSelectionType: Bill.ID.self) { selectedIds in
                    if !selectedIds.isEmpty {
                        Button {
                            if let firstId = selectedIds.first,
                               let bill = allBills.first(where: { $0.id == firstId }) {
                                editingBillWrapper = EditingBillWrapper(id: bill.id, bill: bill)
                            }
                        } label: {
                            Label("Edit", systemImage: "square.and.pencil")
                        }
                        Button {
                            markBills(ids: selectedIds, asPaid: true)
                        } label: {
                            Label("Mark as Paid", systemImage: "checkmark.circle")
                        }
                        Button {
                            markBills(ids: selectedIds, asPaid: false)
                        } label: {
                            Label("Mark as Unpaid", systemImage: "circle")
                        }
                        Divider()
                        Button(role: .destructive) {
                            deleteBills(ids: selectedIds)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        // ✅ Use .sheet(item:) — sheet only opens when editingBillWrapper is non-nil
        .sheet(item: $editingBillWrapper) { wrapper in
            AddBillView(billToEdit: wrapper.bill)
                .environment(\.appCurrency, currency)
        }
    }
    
    private func markBills(ids: Set<Bill.ID>, asPaid: Bool) {
        for bill in allBills where ids.contains(bill.id) {
            bill.isPaid = asPaid
            bill.paymentDate = asPaid ? Date() : nil
            bill.syncStatus = .pendingUpload
            bill.updatedAt = Date()
        }
        SyncService.shared.schedulePush()
    }
    
    private func deleteBills(ids: Set<Bill.ID>) {
        let toDelete = allBills.filter { ids.contains($0.id) }
        for bill in toDelete {
            Task {
                await SyncService.shared.deleteBill(bill)
            }
        }
    }
}