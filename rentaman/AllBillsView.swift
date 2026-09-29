import SwiftUI
import SwiftData

// MARK: - Cached stats
private struct BillsStats {
    var total: Double = 0
    var paid: Double = 0
    var unpaid: Double = 0
    static let zero = BillsStats()
}

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
    @State private var trendWrapper: TrendWrapper? = nil
    @State private var showGenerateFuture = false

    // ── Cached derived data ──
    @State private var cachedFiltered: [Bill] = []
    @State private var cachedPaged: [Bill] = []
    @State private var cachedStats: BillsStats = .zero

    // ── Pagination ──
    @State private var currentPage: Int = 1
    @State private var pageSize: PageSize = .fifty

    enum PageSize: Int, CaseIterable, Identifiable {
        case twentyFive = 25
        case fifty      = 50
        case hundred    = 100
        case all        = 0
        var id: Int { rawValue }
        var label: String { self == .all ? "All" : "\(rawValue)" }
    }

    enum FilterStatus: String, CaseIterable, Identifiable {
        case all = "All"
        case unpaid = "Unpaid"
        case paid = "Paid"
        var id: String { rawValue }
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

    struct TrendWrapper: Identifiable {
        let id: String
        let bill: Bill
    }

    private var totalPages: Int {
        guard pageSize != .all else { return 1 }
        return max(1, Int(ceil(Double(cachedFiltered.count) / Double(pageSize.rawValue))))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider().opacity(0.5)

            if cachedFiltered.isEmpty {
                RMEmptyState(
                    icon: allBills.isEmpty ? "tray" : "magnifyingglass",
                    title: allBills.isEmpty ? "No bills yet" : "No bills match your filters",
                    message: allBills.isEmpty
                        ? "Add your first bill to start tracking expenses across all your properties."
                        : "Try adjusting your search, filters, or selecting a different property."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    AllBillsTable(
                        bills: cachedPaged,
                        currency: currency,
                        allBills: allBills,
                        selection: $selection,
                        sortOrder: $sortOrder,
                        onDirty: handleDirty,
                        onDuplicate: duplicateBills,
                        onDelete: deleteBills,
                        onMarkPaid: markBills,
                        onOpenSheet: { bill in
                            editingBillWrapper = EditingBillWrapper(id: bill.id, bill: bill)
                        },
                        onOpenTrend: { bill in
                            trendWrapper = TrendWrapper(id: bill.id, bill: bill)
                        }
                    )
                    Divider().opacity(0.5)
                    PaginationBar(
                        currentPage: $currentPage,
                        pageSize: $pageSize,
                        totalItems: cachedFiltered.count,
                        totalPages: totalPages
                    )
                }
            }
        }
        .background(RMDesign.pageBackground)
        .sheet(item: $editingBillWrapper) { wrapper in
            AddBillView(billToEdit: wrapper.bill)
                .environment(\.appCurrency, currency)
        }
        .sheet(item: $trendWrapper) { wrapper in
            BillTrendView(initialBill: wrapper.bill)
                .environment(\.appCurrency, currency)
        }
        .sheet(isPresented: $showGenerateFuture) {
            GenerateFutureBillsSheet()
                .environment(\.appCurrency, currency)
        }
        // ── Cache invalidation ──
        .onAppear { recomputeAll() }
        .onChange(of: allBills.count)      { _, _ in recomputeAll() }
        .onChange(of: searchText)          { _, _ in currentPage = 1; recomputeAll() }
        .onChange(of: filterStatus)        { _, _ in currentPage = 1; recomputeAll() }
        .onChange(of: selectedPropertyId)  { _, _ in currentPage = 1; recomputeAll() }
        .onChange(of: sortOrder)           { _, _ in currentPage = 1; recomputeAll() }
        .onChange(of: pageSize)            { _, _ in currentPage = 1; recomputeAll() }
        .onChange(of: currentPage)         { _, _ in recomputePaged() }
        .onChange(of: totalPages) { _, newTotal in
            if currentPage > newTotal { currentPage = max(1, newTotal) }
        }
    }

    // MARK: - Header
    private var headerView: some View {
        VStack(spacing: 20) {
            HStack(alignment: .center) {
                RMPageHeader(
                    icon: "list.bullet.rectangle.portrait.fill",
                    title: "All Bills",
                    subtitle: "\(cachedFiltered.count) bill\(cachedFiltered.count == 1 ? "" : "s") in view"
                )
                Spacer()
                HStack(spacing: 8) {
                    StatPill(icon: "banknote.fill", label: "Total",
                             value: CurrencyFormatter.format(cachedStats.total, as: currency), color: .blue)
                    StatPill(icon: "checkmark.circle.fill", label: "Paid",
                             value: CurrencyFormatter.format(cachedStats.paid, as: currency), color: .green)
                    if cachedStats.unpaid > 0 {
                        StatPill(icon: "clock.fill", label: "Unpaid",
                                 value: CurrencyFormatter.format(cachedStats.unpaid, as: currency), color: .orange)
                    }
                }
            }
            HStack(spacing: 10) {
                SearchField(text: $searchText)
                PropertyFilterMenu(properties: properties, selection: $selectedPropertyId)
                StatusSegmentedControl(selection: $filterStatus)

                // 🆕 Generate future recurring bills
                Button {
                    showGenerateFuture = true
                } label: {
                    Label("Generate", systemImage: "calendar.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Pre-create your recurring bills for the next few months")

                Spacer()
                if !selection.isEmpty {
                    Button { selection.removeAll() } label: {
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
    }

    // MARK: - Cache
    private func recomputeAll() {
        var result = allBills
        if let propId = selectedPropertyId {
            result = result.filter { $0.property?.id == propId }
        }
        switch filterStatus {
        case .unpaid: result = result.filter { !$0.isPaid }
        case .paid:   result = result.filter { $0.isPaid }
        case .all:    break
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed) ||
                $0.category.rawValue.localizedCaseInsensitiveContains(trimmed) ||
                ($0.property?.name.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
        }
        cachedFiltered = result.sorted(using: sortOrder)

        var s = BillsStats.zero
        for b in cachedFiltered {
            s.total += b.amount
            if b.isPaid { s.paid += b.amount } else { s.unpaid += b.amount }
        }
        cachedStats = s

        recomputePaged()
    }

    private func recomputePaged() {
        guard pageSize != .all else {
            cachedPaged = cachedFiltered
            return
        }
        let start = (currentPage - 1) * pageSize.rawValue
        let end = min(start + pageSize.rawValue, cachedFiltered.count)
        cachedPaged = start < end ? Array(cachedFiltered[start..<end]) : []
    }

    // MARK: - Mutation callbacks
    private func handleDirty(_ bill: Bill) {
        try? modelContext.save()
        SyncService.shared.schedulePush()
        recomputeAll()
    }

    private func markBills(ids: Set<Bill.ID>, asPaid: Bool) {
        for bill in allBills where ids.contains(bill.id) {
            bill.isPaid = asPaid
            bill.paymentDate = asPaid ? Date() : nil
            bill.syncStatus = .pendingUpload
            bill.updatedAt = Date()
        }
        SyncService.shared.schedulePush()
        recomputeAll()
    }

    private func deleteBills(ids: Set<Bill.ID>) {
        let toDelete = allBills.filter { ids.contains($0.id) }
        for bill in toDelete {
            Task { await SyncService.shared.deleteBill(bill) }
        }
    }

    private func duplicateBills(ids: Set<Bill.ID>) {
        let source = allBills.filter { ids.contains($0.id) }
        guard !source.isEmpty else { return }
        for bill in source {
            let copy = Bill(
                title: bill.title,
                amount: bill.amount,
                category: bill.category,
                dueDate: nextDueDate(for: bill),
                isPaid: false,
                property: bill.property,
                isRecurring: bill.isRecurring,
                recurringFrequency: bill.recurringFrequency
            )
            copy.notes = bill.notes
            copy.receiptIdentifier = nil
            copy.syncStatus = .pendingUpload
            copy.updatedAt = Date()
            modelContext.insert(copy)
        }
        try? modelContext.save()
        SyncService.shared.schedulePush()
        recomputeAll()
    }

    private func nextDueDate(for bill: Bill) -> Date {
        let cal = Calendar.current
        let comp: DateComponents
        switch bill.recurringFrequency {
        case .weekly:    comp = DateComponents(weekOfYear: 1)
        case .monthly:   comp = DateComponents(month: 1)
        case .quarterly: comp = DateComponents(month: 3)
        case .yearly:    comp = DateComponents(year: 1)
        case .none:      comp = DateComponents(month: 1)
        }
        return cal.date(byAdding: comp, to: bill.dueDate) ?? bill.dueDate
    }
}

// MARK: - Table
private struct AllBillsTable: View {
    let bills: [Bill]
    let currency: AppCurrency
    let allBills: [Bill]
    @Binding var selection: Set<Bill.ID>
    @Binding var sortOrder: [KeyPathComparator<Bill>]

    let onDirty: (Bill) -> Void
    let onDuplicate: (Set<Bill.ID>) -> Void
    let onDelete: (Set<Bill.ID>) -> Void
    let onMarkPaid: (Set<Bill.ID>, Bool) -> Void
    let onOpenSheet: (Bill) -> Void
    let onOpenTrend: (Bill) -> Void

    var body: some View {
        Table(bills, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Paid") { bill in
                Toggle("", isOn: Binding(
                    get: { bill.isPaid },
                    set: { newValue in
                        bill.isPaid = newValue
                        bill.paymentDate = newValue ? Date() : nil
                        bill.syncStatus = .pendingUpload
                        bill.updatedAt = Date()
                        onDirty(bill)
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }
            .width(45)

            TableColumn("Title", value: \.title) { bill in
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

                    // Over-limit pill
                    if let limit = BillLimits.shared.limit(for: bill.title),
                       bill.amount > limit {
                        Text("OVER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.gradient)
                            .cornerRadius(3)
                            .help("Exceeds your \(CurrencyFormatter.format(limit, as: currency)) limit")
                    }
                }
            }
            .width(min: 150, ideal: 220)

            TableColumn("Property") { bill in
                if let prop = bill.property {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: prop.colorHex)).frame(width: 8, height: 8)
                        Text(prop.name).font(.system(size: 12)).lineLimit(1)
                    }
                } else {
                    Text("—").font(.system(size: 12)).foregroundStyle(.tertiary)
                }
            }
            .width(min: 110, ideal: 150)

            TableColumn("Category") { bill in
                HStack(spacing: 6) {
                    Image(systemName: bill.category.iconName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(bill.category.color)
                    Text(bill.category.rawValue)
                        .font(.system(size: 12)).lineLimit(1)
                }
            }
            .width(min: 130, ideal: 160)

            TableColumn("Amount", value: \.amount) { bill in
                Text(CurrencyFormatter.format(bill.amount, as: currency))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .width(min: 110, ideal: 140)

            TableColumn("Due Date", value: \.dueDate) { bill in
                HStack(spacing: 6) {
                    Text(bill.dueDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundStyle(isOverdue(bill) ? .red : .primary)
                    if isOverdue(bill) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10)).foregroundStyle(.red)
                            .help("Overdue")
                    }
                }
            }
            .width(min: 110, ideal: 130)

            TableColumn("") { bill in
                HStack(spacing: 4) {
                    if !bill.isPaid {
                        Button {
                            bill.isPaid = true
                            bill.paymentDate = Date()
                            bill.syncStatus = .pendingUpload
                            bill.updatedAt = Date()
                            onDirty(bill)
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13)).foregroundStyle(.green)
                        }
                        .buttonStyle(.borderless)
                        .help("Mark as paid")
                    }
                    Button {
                        onOpenTrend(bill)
                    } label: {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 13)).foregroundStyle(.purple)
                    }
                    .buttonStyle(.borderless)
                    .help("View trend")

                    Button {
                        onOpenSheet(bill)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 13)).foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                    .help("Edit")
                }
            }
            .width(90)
        }
        .contextMenu(forSelectionType: Bill.ID.self) { selectedIds in
            if !selectedIds.isEmpty {
                Button {
                    if let firstId = selectedIds.first,
                       let bill = allBills.first(where: { $0.id == firstId }) {
                        onOpenSheet(bill)
                    }
                } label: { Label("Edit", systemImage: "square.and.pencil") }

                if selectedIds.count == 1,
                   let firstId = selectedIds.first,
                   let bill = allBills.first(where: { $0.id == firstId }) {
                    Button {
                        onOpenTrend(bill)
                    } label: {
                        Label("View Trend", systemImage: "chart.xyaxis.line")
                    }
                }

                Button {
                    onDuplicate(selectedIds)
                } label: {
                    Label(
                        selectedIds.count == 1 ? "Duplicate" : "Duplicate \(selectedIds.count) Bills",
                        systemImage: "doc.on.doc"
                    )
                }

                Divider()
                Button { onMarkPaid(selectedIds, true) } label:
                    { Label("Mark as Paid", systemImage: "checkmark.circle") }
                Button { onMarkPaid(selectedIds, false) } label:
                    { Label("Mark as Unpaid", systemImage: "circle") }
                Divider()
                Button(role: .destructive) { onDelete(selectedIds) } label:
                    { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private func isOverdue(_ bill: Bill) -> Bool {
        !bill.isPaid && bill.dueDate < Date()
    }
}

// MARK: - Pagination Bar
struct PaginationBar: View {
    @Binding var currentPage: Int
    @Binding var pageSize: AllBillsView.PageSize
    let totalItems: Int
    let totalPages: Int

    private var rangeStart: Int {
        guard totalItems > 0 else { return 0 }
        if pageSize == .all { return 1 }
        return (currentPage - 1) * pageSize.rawValue + 1
    }
    private var rangeEnd: Int {
        guard totalItems > 0 else { return 0 }
        if pageSize == .all { return totalItems }
        return min(currentPage * pageSize.rawValue, totalItems)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Showing \(rangeStart)–\(rangeEnd) of \(totalItems)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            HStack(spacing: 6) {
                Text("Rows:").font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("", selection: $pageSize) {
                    ForEach(AllBillsView.PageSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .labelsHidden().pickerStyle(.menu)
                .frame(width: 74).controlSize(.small)
            }

            Divider().frame(height: 16)

            HStack(spacing: 4) {
                Button {
                    if currentPage > 1 { currentPage -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(currentPage <= 1 || pageSize == .all)
                .help("Previous page")

                HStack(spacing: 4) {
                    Text("Page").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("", value: Binding(
                        get: { currentPage },
                        set: { currentPage = min(max(1, $0), totalPages) }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .frame(width: 40)
                    .multilineTextAlignment(.center)
                    .controlSize(.small)
                    .disabled(pageSize == .all)

                    Text("of \(totalPages)")
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }

                Button {
                    if currentPage < totalPages { currentPage += 1 }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(currentPage >= totalPages || pageSize == .all)
                .help("Next page")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(RMDesign.pageBackground)
    }
}

// MARK: - Search Field
struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Search bills...", text: $text)
                .textFieldStyle(.plain).font(.system(size: 13))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34).frame(width: 220)
        .background(RMDesign.cardBackground)
        .cornerRadius(RMDesign.fieldRadius)
        .overlay(RoundedRectangle(cornerRadius: RMDesign.fieldRadius)
            .stroke(Color.gray.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Property Filter Menu
struct PropertyFilterMenu: View {
    let properties: [Property]
    @Binding var selection: String?
    private var label: String {
        if let id = selection, let prop = properties.first(where: { $0.id == id }) { return prop.name }
        return "All Properties"
    }
    var body: some View {
        Menu {
            Button { selection = nil } label: {
                Label("All Properties", systemImage: selection == nil ? "checkmark" : "house")
            }
            if !properties.isEmpty {
                Divider()
                ForEach(properties) { p in
                    Button { selection = p.id } label: {
                        Label(p.name, systemImage: selection == p.id ? "checkmark" : "house")
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "house.fill").font(.system(size: 11)).foregroundStyle(.blue)
                Text(label).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).frame(height: 34).frame(minWidth: 140)
            .background(RMDesign.cardBackground)
            .cornerRadius(RMDesign.fieldRadius)
            .overlay(RoundedRectangle(cornerRadius: RMDesign.fieldRadius)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = status }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: status.icon).font(.system(size: 10, weight: .semibold))
                        Text(status.rawValue).font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12).frame(height: 30)
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
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.gray.opacity(0.15), lineWidth: 1))
    }
}