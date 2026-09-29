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
    @State private var editingBillWrapper: EditingBillWrapper? = nil
    
    enum FilterStatus: String, CaseIterable, Identifiable {
        case all = "All"
        case unpaid = "Unpaid"
        case paid = "Paid"
        var id: String { self.rawValue }
        
        var icon: String {
            switch self {
            case .all: return "square.stack.3d.up"
            case .unpaid: return "circle.dotted"
            case .paid: return "checkmark.circle"
            }
        }
    }
    
    struct EditingBillWrapper: Identifiable {
        let id: String
        let bill: Bill
    }
    
    // MARK: - Filtered Data
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
    
    // MARK: - Stats
    private var stats: (total: Double, paid: Double, unpaid: Double) {
        let total = filteredBills.reduce(0.0) { $0 + $1.amount }
        let paid = filteredBills.filter { $0.isPaid }.reduce(0.0) { $0 + $1.amount }
        let unpaid = filteredBills.filter { !$0.isPaid }.reduce(0.0) { $0 + $1.amount }
        return (total, paid, unpaid)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Page Header
            VStack(spacing: 20) {
                HStack(alignment: .center) {
                    RMPageHeader(
                        icon: "list.bullet.rectangle.portrait.fill",
                        title: "All Bills",
                        subtitle: "\(filteredBills.count) bill\(filteredBills.count == 1 ? "" : "s") in view"
                    )
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        StatPill(
                            icon: "banknote.fill",
                            label: "Total",
                            value: CurrencyFormatter.format(stats.total, as: currency),
                            color: .blue
                        )
                        
                        StatPill(
                            icon: "checkmark.circle.fill",
                            label: "Paid",
                            value: CurrencyFormatter.format(stats.paid, as: currency),
                            color: .green
                        )
                        
                        if stats.unpaid > 0 {
                            StatPill(
                                icon: "clock.fill",
                                label: "Unpaid",
                                value: CurrencyFormatter.format(stats.unpaid, as: currency),
                                color: .orange
                            )
                        }
                    }
                }
                
                // MARK: - Filter Bar
                HStack(spacing: 10) {
                    SearchField(text: $searchText)
                    
                    PropertyFilterMenu(
                        properties: properties,
                        selection: $selectedPropertyId
                    )
                    
                    StatusSegmentedControl(selection: $filterStatus)
                    
                    Spacer()
                    
                    if !selection.isEmpty {
                        Button {
                            selection.removeAll()
                        } label: {
                            Label("Clear selection", systemImage: "xmark.circle.fill")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .background(RMDesign.pageBackground)
            
            Divider().opacity(0.5)
            
            // MARK: - Table or Empty
            if filteredBills.isEmpty {
                RMEmptyState(
                    icon: allBills.isEmpty ? "tray" : "magnifyingglass",
                    title: allBills.isEmpty ? "No bills yet" : "No bills match your filters",
                    message: allBills.isEmpty
                        ? "Add your first bill to start tracking expenses across all your properties."
                        : "Try adjusting your search, filters, or selecting a different property."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                billsTable
            }
        }
        .background(RMDesign.pageBackground)
        .sheet(item: $editingBillWrapper) { wrapper in
            AddBillView(billToEdit: wrapper.bill)
                .environment(\.appCurrency, currency)
        }
    }
    
    // MARK: - Table
    private var billsTable: some View {
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
                HStack(spacing: 8) {
                    if bill.isRecurring {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.blue)
                            .help("Recurring: \(bill.recurringFrequency.rawValue)")
                    }
                    Text(bill.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
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
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 110, ideal: 150)
            
            TableColumn("Category") { (bill: Bill) in
                HStack(spacing: 6) {
                    Image(systemName: bill.category.iconName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(bill.category.color)
                    Text(bill.category.rawValue)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
            }
            .width(min: 130, ideal: 160)
            
            TableColumn("Amount", value: \.amount) { (bill: Bill) in
                Text(CurrencyFormatter.format(bill.amount, as: currency))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .width(min: 110, ideal: 140)
            
            TableColumn("Due Date", value: \.dueDate) { (bill: Bill) in
                HStack(spacing: 6) {
                    Text(bill.dueDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundStyle(isOverdue(bill) ? .red : .primary)
                    if isOverdue(bill) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .help("Overdue")
                    }
                }
            }
            .width(min: 110, ideal: 130)
            
            TableColumn("") { (bill: Bill) in
                HStack(spacing: 4) {
                    // Quick Pay button (only if unpaid)
                    if !bill.isPaid {
                        Button {
                            bill.isPaid = true
                            bill.paymentDate = Date()
                            bill.syncStatus = .pendingUpload
                            bill.updatedAt = Date()
                            SyncService.shared.schedulePush()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.borderless)
                        .help("Mark as paid")
                    }
                    
                    Button {
                        editingBillWrapper = EditingBillWrapper(id: bill.id, bill: bill)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 13))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                    .help("Edit")
                }
            }
            .width(60)
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
    
    // MARK: - Helpers
    private func isOverdue(_ bill: Bill) -> Bool {
        !bill.isPaid && bill.dueDate < Date()
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
            Task { await SyncService.shared.deleteBill(bill) }
        }
    }
}

// MARK: - Search Field
struct SearchField: View {
    @Binding var text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            TextField("Search bills...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .frame(width: 220)
        .background(RMDesign.cardBackground)
        .cornerRadius(RMDesign.fieldRadius)
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.fieldRadius)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Property Filter Menu
struct PropertyFilterMenu: View {
    let properties: [Property]
    @Binding var selection: String?
    
    private var label: String {
        if let id = selection, let prop = properties.first(where: { $0.id == id }) {
            return prop.name
        }
        return "All Properties"
    }
    
    var body: some View {
        Menu {
            Button {
                selection = nil
            } label: {
                Label("All Properties", systemImage: selection == nil ? "checkmark" : "house")
            }
            
            if !properties.isEmpty {
                Divider()
                ForEach(properties) { property in
                    Button {
                        selection = property.id
                    } label: {
                        Label(
                            property.name,
                            systemImage: selection == property.id ? "checkmark" : "house"
                        )
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "house.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .frame(minWidth: 140)
            .background(RMDesign.cardBackground)
            .cornerRadius(RMDesign.fieldRadius)
            .overlay(
                RoundedRectangle(cornerRadius: RMDesign.fieldRadius)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Status Segmented Control
struct StatusSegmentedControl: View {
    @Binding var selection: AllBillsView.FilterStatus
    @Namespace private var namespace
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(AllBillsView.FilterStatus.allCases) { status in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selection = status
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: status.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(status.rawValue)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .foregroundStyle(selection == status ? .white : .primary)
                    .background {
                        if selection == status {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.blue.gradient)
                                .matchedGeometryEffect(id: "statusBg", in: namespace)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RMDesign.cardBackground)
        .cornerRadius(9)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}