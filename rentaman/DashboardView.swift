import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.appCurrency) private var currency: AppCurrency
    @Environment(SyncService.self) private var syncService
    @Query private var properties: [Property]
    @Query private var allBills: [Bill]
    
    @State private var selectedPropertyId: String? = nil
    @State private var lastRefreshCheck: Date = Date()
    
    private var filteredBills: [Bill] {
        if let selectedId = selectedPropertyId {
            return allBills.filter { $0.property?.id == selectedId }
        }
        return allBills
    }
    
    private var filteredProperties: [Property] {
        if let selectedId = selectedPropertyId {
            return properties.filter { $0.id == selectedId }
        }
        return properties
    }
    
    private var analytics: DashboardAnalytics {
        DashboardAnalytics(bills: filteredBills, properties: filteredProperties)
    }
    
    private let kpiColumns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 14),
        count: 4
    )
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // MARK: - Page Header + Live Freshness
                HStack(alignment: .center) {
                    RMPageHeader(
                        icon: "square.grid.2x2.fill",
                        title: "Dashboard",
                        subtitle: "\(filteredBills.count) bill\(filteredBills.count == 1 ? "" : "s") tracked"
                    )
                    
                    Spacer()
                    
                    liveFreshnessIndicator
                    
                    propertyFilter
                }
                .padding(.horizontal, 24)
                
                // MARK: - Hero KPIs
                LazyVGrid(columns: kpiColumns, spacing: 14) {
                    HeroKPICard(
                        title: "Unpaid Bills",
                        value: "\(analytics.unpaidBills.count)",
                        subtitle: CurrencyFormatter.format(analytics.totalUnpaidAmount, as: currency),
                        icon: "exclamationmark.triangle.fill",
                        gradient: LinearGradient(
                            colors: [Color(red: 0.95, green: 0.35, blue: 0.35),
                                     Color(red: 0.85, green: 0.15, blue: 0.35)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        iconAccent: .red
                    )
                    
                    HeroKPICard(
                        title: "Upcoming",
                        value: "\(analytics.upcomingBills.count)",
                        subtitle: upcomingSubtitle,
                        icon: "clock.fill",
                        gradient: LinearGradient(
                            colors: [Color(red: 0.98, green: 0.62, blue: 0.15),
                                     Color(red: 0.92, green: 0.42, blue: 0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        iconAccent: .orange
                    )
                    
                    HeroKPICard(
                        title: "Spent This Month",
                        value: CurrencyFormatter.format(analytics.totalSpentThisMonth, as: currency),
                        subtitle: analytics.spentThisMonthLabel,
                        icon: "chart.pie.fill",
                        gradient: LinearGradient(
                            colors: [Color(red: 0.28, green: 0.55, blue: 0.98),
                                     Color(red: 0.45, green: 0.28, blue: 0.92)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        iconAccent: .blue
                    )
                    
                    HeroKPICard(
                        title: "Anomalies",
                        value: "\(analytics.anomalies.count)",
                        subtitle: analytics.anomalies.isEmpty ? "No issues detected" : "Unusually high bills",
                        icon: "bell.badge.fill",
                        gradient: LinearGradient(
                            colors: [Color(red: 0.62, green: 0.28, blue: 0.95),
                                     Color(red: 0.85, green: 0.25, blue: 0.75)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        iconAccent: .purple
                    )
                }
                .padding(.horizontal, 24)
                
                // MARK: - Budget Progress
                if analytics.totalBudget > 0 {
                    BudgetProgressCard(
                        spent: analytics.totalSpentThisMonth,
                        budget: analytics.totalBudget,
                        progress: analytics.budgetProgress,
                        currency: currency
                    )
                    .padding(.horizontal, 24)
                }
                
                // MARK: - Charts Row
                HStack(alignment: .top, spacing: 14) {
                    RMContentCard(
                        title: "Expenses by Category",
                        icon: "chart.pie.fill",
                        iconColor: .blue,
                        subtitle: analytics.spentThisMonthLabel
                    ) {
                        if analytics.expensesByCategory.isEmpty || analytics.totalForCategoryChart <= 0 {
                            SmallEmptyState(icon: "chart.pie", message: "No expenses recorded")
                        } else {
                            Chart(analytics.expensesByCategory) { item in
                                SectorMark(
                                    angle: .value("Amount", item.amount),
                                    innerRadius: .ratio(0.62),
                                    angularInset: 2
                                )
                                .foregroundStyle(item.color.gradient)
                                .cornerRadius(4)
                                .annotation(position: .overlay) {
                                    let share = item.amount / analytics.totalForCategoryChart
                                    if share.isFinite && share > 0.15 {
                                        Text("\(Int(share * 100))%")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .chartLegend(position: .bottom, alignment: .center, spacing: 12)
                            .frame(height: 260)
                        }
                    }
                    
                    RMContentCard(
                        title: "Recent Anomalies",
                        icon: "bell.badge.fill",
                        iconColor: .purple,
                        subtitle: "Unusual spending patterns"
                    ) {
                        if analytics.anomalies.isEmpty {
                            SmallEmptyState(
                                icon: "checkmark.seal.fill",
                                message: "All bills look normal",
                                color: .green
                            )
                        } else {
                            VStack(spacing: 8) {
                                ForEach(analytics.anomalies.prefix(4)) { bill in
                                    AnomalyRow(bill: bill, currency: currency)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxHeight: 400)
                
                // MARK: - Action Center
                RMContentCard(
                    title: "Action Center",
                    icon: "list.bullet.circle.fill",
                    iconColor: .red,
                    subtitle: actionCenterSubtitle
                ) {
                    if analytics.unpaidBills.isEmpty {
                        SmallEmptyState(
                            icon: "checkmark.circle.fill",
                            message: "All bills are paid. Great job!",
                            color: .green
                        )
                    } else {
                        VStack(spacing: 6) {
                            // Overdue section
                            if !analytics.overdueBills.isEmpty {
                                HStack {
                                    Text("Overdue")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.red)
                                        .tracking(0.5)
                                    Spacer()
                                    Text("\(analytics.overdueBills.count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red)
                                        .clipShape(Capsule())
                                }
                                .padding(.horizontal, 4)
                                .padding(.bottom, 2)
                                
                                ForEach(analytics.overdueBills.prefix(3)) { bill in
                                    UnpaidBillRow(
                                        bill: bill,
                                        currency: currency,
                                        onMarkPaid: { markBillAsPaid(bill) }
                                    )
                                }
                            }
                            
                            // Regular unpaid section
                            let nonOverdue = analytics.unpaidBills.filter { $0.dueDate >= Date() }
                            if !nonOverdue.isEmpty {
                                if !analytics.overdueBills.isEmpty {
                                    Divider().padding(.vertical, 4)
                                }
                                
                                HStack {
                                    Text("Upcoming")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.orange)
                                        .tracking(0.5)
                                    Spacer()
                                    Text("\(nonOverdue.count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange)
                                        .clipShape(Capsule())
                                }
                                .padding(.horizontal, 4)
                                .padding(.bottom, 2)
                                
                                ForEach(nonOverdue.prefix(5)) { bill in
                                    UnpaidBillRow(
                                        bill: bill,
                                        currency: currency,
                                        onMarkPaid: { markBillAsPaid(bill) }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 24)
        }
        .background(RMDesign.pageBackground)
        // MARK: - Auto-refresh
        .task {
            // Trigger a sync when the dashboard appears so we have latest data
            if syncService.state.isLive || syncService.state.isIdle {
                await syncService.forceSync()
            }
        }
    }
    
    // MARK: - Live Freshness Indicator
    private var liveFreshnessIndicator: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                Circle()
                    .fill(freshnessColor)
                    .frame(width: 6, height: 6)
                
                Text(freshnessText(at: context.date))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.gray.opacity(0.08))
                    .overlay(Capsule().stroke(Color.gray.opacity(0.12), lineWidth: 0.75))
            )
            .help("Data updates automatically as bills sync")
        }
    }
    
    private var freshnessColor: Color {
        guard let last = syncService.lastSyncAt else { return .gray }
        let secondsAgo = Date().timeIntervalSince(last)
        if secondsAgo < 60 { return .green }
        if secondsAgo < 600 { return .orange }
        return .red
    }
    
    private func freshnessText(at date: Date) -> String {
        guard let last = syncService.lastSyncAt else { return "Never synced" }
        let seconds = max(0, Int(date.timeIntervalSince(last)))
        if seconds < 5 { return "Just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
    
    // MARK: - Sub-computations
    private var upcomingSubtitle: String {
        if analytics.upcomingBills.isEmpty && analytics.overdueBills.isEmpty {
            return "Nothing due soon"
        }
        if !analytics.overdueBills.isEmpty {
            return "\(analytics.overdueBills.count) overdue"
        }
        return "Bills due within 7 days"
    }
    
    private var actionCenterSubtitle: String {
        let total = analytics.unpaidBills.count
        if total == 0 { return "Nothing to pay" }
        return "\(total) bill\(total == 1 ? "" : "s") waiting to be paid"
    }
    
    // MARK: - Actions
    private func markBillAsPaid(_ bill: Bill) {
        bill.isPaid = true
        bill.paymentDate = Date()
        bill.syncStatus = .pendingUpload
        bill.updatedAt = Date()
        SyncService.shared.schedulePush()
    }
    
    // MARK: - Property Filter
    private var propertyFilter: some View {
        Menu {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedPropertyId = nil
                }
            } label: {
                Label("All Properties", systemImage: selectedPropertyId == nil ? "checkmark" : "")
            }
            
            if !properties.isEmpty {
                Divider()
                ForEach(properties) { property in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedPropertyId = property.id
                        }
                    } label: {
                        Label(
                            property.name,
                            systemImage: selectedPropertyId == property.id ? "checkmark" : "house"
                        )
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 13))
                Text(selectedPropertyLabel)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(RMDesign.cardBackground)
            .cornerRadius(RMDesign.pillRadius)
            .overlay(
                Capsule().stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
    
    private var selectedPropertyLabel: String {
        if let id = selectedPropertyId,
           let prop = properties.first(where: { $0.id == id }) {
            return prop.name
        }
        return "All Properties"
    }
}

// MARK: - Budget Progress Card
struct BudgetProgressCard: View {
    let spent: Double
    let budget: Double
    let progress: Double
    let currency: AppCurrency
    
    private var isOverBudget: Bool { progress >= 1.0 }
    private var isWarning: Bool { progress >= 0.8 && progress < 1.0 }
    
    private var statusColor: Color {
        if isOverBudget { return .red }
        if isWarning { return .orange }
        return .green
    }
    
    private var statusText: String {
        if isOverBudget { return "Over budget" }
        if isWarning { return "Approaching limit" }
        return "On track"
    }
    
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "gauge.medium")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(statusColor.gradient)
                        .cornerRadius(9)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Monthly Budget")
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(CurrencyFormatter.format(spent, as: currency)) of \(CurrencyFormatter.format(budget, as: currency))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Text(statusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.12))
                    .cornerRadius(RMDesign.pillRadius)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.12))
                        .frame(height: 8)
                    
                    Capsule()
                        .fill(statusColor.gradient)
                        .frame(width: geo.size.width * progress, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(18)
        .background(RMDesign.cardBackground)
        .cornerRadius(RMDesign.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(Color.gray.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Anomaly Row
struct AnomalyRow: View {
    let bill: Bill
    let currency: AppCurrency
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: bill.category.iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(bill.category.color)
                .frame(width: 28, height: 28)
                .background(bill.category.color.opacity(0.12))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(bill.property?.name ?? "Unknown")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(CurrencyFormatter.format(bill.amount, as: currency))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
                .monospacedDigit()
        }
        .padding(10)
        .background(isHovered ? Color.purple.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Unpaid Bill Row
struct UnpaidBillRow: View {
    let bill: Bill
    let currency: AppCurrency
    let onMarkPaid: () -> Void
    
    @State private var isHovered = false
    
    private var isOverdue: Bool {
        !bill.isPaid && bill.dueDate < Date()
    }
    
    private var daysUntilDue: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: bill.dueDate).day ?? 0
    }
    
    private var dueText: String {
        if isOverdue {
            let days = abs(daysUntilDue)
            return days == 0 ? "Due today" : "\(days)d overdue"
        }
        if daysUntilDue == 0 { return "Due today" }
        if daysUntilDue == 1 { return "Due tomorrow" }
        return "Due in \(daysUntilDue)d"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isOverdue ? Color.red : Color.orange)
                .frame(width: 8, height: 8)
            
            Image(systemName: bill.category.iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(bill.category.color)
                .frame(width: 30, height: 30)
                .background(bill.category.color.opacity(0.12))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(bill.property?.name ?? "Unknown")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    
                    Text(dueText)
                        .font(.system(size: 10, weight: isOverdue ? .semibold : .regular))
                        .foregroundStyle(isOverdue ? .red : .secondary)
                }
            }
            
            Spacer()
            
            Text(CurrencyFormatter.format(bill.amount, as: currency))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
            
            Button(action: onMarkPaid) {
                Label("Pay", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.small)
            .opacity(isHovered ? 1 : 0.7)
        }
        .padding(10)
        .background(isHovered ? Color.blue.opacity(0.04) : Color.clear)
        .cornerRadius(10)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Small Empty State
struct SmallEmptyState: View {
    let icon: String
    let message: String
    var color: Color = .secondary
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(color.opacity(0.7))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 180)
    }
}