import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.appCurrency) private var currency: AppCurrency
    @Environment(SyncService.self) private var syncService
    @Environment(\.modelContext) private var modelContext

    @Query private var properties: [Property]
    @Query(filter: #Predicate<Bill> { $0.isDeleted == false })
    private var allBills: [Bill]

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
        repeating: GridItem(.flexible(), spacing: 12),
        count: 4
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                LazyVGrid(columns: kpiColumns, spacing: 12) {
                    HeroKPICard(
                        title: "Unpaid Bills",
                        value: "\(analytics.unpaidBills.count)",
                        subtitle: CurrencyFormatter.format(analytics.totalUnpaidAmount, as: currency),
                        icon: "exclamationmark.triangle.fill",
                        gradient: LinearGradient(
                            colors: [.red, .red],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        iconAccent: RMDesign.danger
                    )

                    HeroKPICard(
                        title: "Upcoming",
                        value: "\(analytics.upcomingBills.count)",
                        subtitle: upcomingSubtitle,
                        icon: "clock.fill",
                        gradient: LinearGradient(
                            colors: [.orange, .orange],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        iconAccent: RMDesign.warning
                    )

                    HeroKPICard(
                        title: "Spent This Month",
                        value: CurrencyFormatter.format(analytics.totalPaidThisMonth, as: currency),
                        subtitle: analytics.spentThisMonthLabel(currency: currency),
                        icon: "chart.pie.fill",
                        gradient: LinearGradient(
                            colors: [.blue, .blue],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        iconAccent: RMDesign.accent
                    )

                    HeroKPICard(
                        title: "Anomalies",
                        value: "\(analytics.anomalyReports.count)",
                        subtitle: analytics.anomalySubtitle,
                        icon: "bell.badge.fill",
                        gradient: LinearGradient(
                            colors: [.purple, .purple],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        iconAccent: .purple
                    )
                }
                .padding(.horizontal, 24)

                // MARK: - Budget Progress
                if analytics.totalBudget > 0 {
                    BudgetProgressCard(
                        paid: analytics.totalPaidThisMonth,
                        expected: analytics.totalExpectedThisMonth,
                        budget: analytics.totalBudget,
                        currency: currency
                    )
                    .padding(.horizontal, 24)
                }

                // MARK: - Charts Row
                HStack(alignment: .top, spacing: 12) {
                    RMContentCard(
                        title: "Expenses by Category",
                        icon: "chart.pie.fill",
                        iconColor: RMDesign.accent,
                        subtitle: analytics.spentThisMonthLabel(currency: currency)
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
                                .cornerRadius(3)
                                .annotation(position: .overlay) {
                                    let share = item.amount / analytics.totalForCategoryChart
                                    if share.isFinite && share > 0.15 {
                                        Text("\(Int(share * 100))%")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .chartLegend(position: .bottom, alignment: .center, spacing: 12)
                            .frame(height: 240)
                        }
                    }

                    RMContentCard(
                        title: "Recent Anomalies",
                        icon: "bell.badge.fill",
                        iconColor: .purple,
                        subtitle: anomaliesCardSubtitle
                    ) {
                        if analytics.anomalyReports.isEmpty {
                            SmallEmptyState(
                                icon: "checkmark.seal.fill",
                                message: "All bills look normal",
                                color: RMDesign.success
                            )
                        } else {
                            VStack(spacing: 6) {
                                ForEach(analytics.anomalyReports.prefix(4)) { anomaly in
                                    AnomalyRow(anomaly: anomaly, currency: currency)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxHeight: 380)

                // MARK: - Action Center
                RMContentCard(
                    title: "Action Center",
                    icon: "list.bullet.circle.fill",
                    iconColor: RMDesign.danger,
                    subtitle: actionCenterSubtitle
                ) {
                    if analytics.unpaidBills.isEmpty {
                        SmallEmptyState(
                            icon: "checkmark.circle.fill",
                            message: "All bills are paid. Great job!",
                            color: RMDesign.success
                        )
                    } else {
                        VStack(spacing: 4) {
                            // Overdue section
                            if !analytics.overdueBills.isEmpty {
                                SectionBadge(
                                    title: "Overdue",
                                    count: analytics.overdueBills.count,
                                    color: RMDesign.danger
                                )

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
                                    Divider()
                                        .background(RMDesign.dividerColor)
                                        .padding(.vertical, 6)
                                }

                                SectionBadge(
                                    title: "Upcoming",
                                    count: nonOverdue.count,
                                    color: RMDesign.warning
                                )

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
            .padding(.vertical, 20)
        }
        .background(RMDesign.pageBackground)
        .task {
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
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .help("Data updates automatically as bills sync")
        }
    }

    private var freshnessColor: Color {
        guard let last = syncService.lastSyncAt else { return .secondary }
        let secondsAgo = Date().timeIntervalSince(last)
        if secondsAgo < 60 { return RMDesign.success }
        if secondsAgo < 600 { return RMDesign.warning }
        return RMDesign.danger
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

    private var anomaliesCardSubtitle: String {
        guard !analytics.anomalyReports.isEmpty else { return "All bills look normal" }
        let overLimit = analytics.anomalyReports.filter { $0.kind.isOverLimit }.count
        if overLimit > 0 {
            return "\(overLimit) over limit · top \(min(4, analytics.anomalyReports.count)) shown"
        }
        return "Unusual spending patterns"
    }

    private func markBillAsPaid(_ bill: Bill) {
        guard !bill.isPaid else { return }
        bill.isPaid = true
        bill.paymentDate = Date()
        bill.syncStatus = .pendingUpload
        bill.updatedAt = Date()

        AuditLog.shared.billMarkedPaid(bill, isPaid: true, context: modelContext)

        try? modelContext.save()
        SyncService.shared.schedulePush()
    }

    // MARK: - Property Filter
    private var propertyFilter: some View {
        Menu {
            Button {
                withAnimation(RMDesign.ease) {
                    selectedPropertyId = nil
                }
            } label: {
                Label("All Properties", systemImage: selectedPropertyId == nil ? "checkmark" : "")
            }

            if !properties.isEmpty {
                Divider()
                ForEach(properties) { property in
                    Button {
                        withAnimation(RMDesign.ease) {
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
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(RMDesign.accent)
                Text(selectedPropertyLabel)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RMDesign.cardBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(RMDesign.borderColor, lineWidth: 1)
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

// MARK: - Section Badge (small pill header used in Action Center)
private struct SectionBadge: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            Text("\(count)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(color)
                .clipShape(Capsule())

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }
}

// MARK: - Budget Progress Card (dual-layer bar)
//
// Layer 1 (solid)      = amount actually paid this month
// Layer 2 (tinted)     = amount committed (paid + expected) this month
// Status color driven by `committed / budget` — that's what determines
// whether you'll stay within budget.
struct BudgetProgressCard: View {
    let paid: Double
    let expected: Double
    let budget: Double
    let currency: AppCurrency

    private var committed: Double { paid + expected }
    private var remaining: Double { max(0, budget - committed) }

    private var paidProgress: Double {
        guard budget > 0 else { return 0 }
        return min(paid / budget, 1.0)
    }

    private var committedProgress: Double {
        guard budget > 0 else { return 0 }
        return min(committed / budget, 1.0)
    }

    private var isOver: Bool { committed > budget }
    private var isWarning: Bool { !isOver && committed >= budget * 0.8 }
    private var isIdle: Bool { paid == 0 && expected == 0 }

    private var statusColor: Color {
        if isOver { return RMDesign.danger }
        if isWarning { return RMDesign.warning }
        return RMDesign.success
    }

    private var statusText: String {
        if isIdle { return "No activity" }
        if isOver { return "Over budget" }
        if paid == 0 && expected > 0 { return "Committed" }
        if expected == 0 { return "All paid" }
        if isWarning { return "Approaching limit" }
        return "On track"
    }

    var body: some View {
        VStack(spacing: 12) {
            // ── Header row ──
            HStack(spacing: 10) {
                Image(systemName: "gauge.medium")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(statusColor)
                    .frame(width: 24, height: 24)
                    .background(statusColor.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Monthly Budget")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("\(CurrencyFormatter.format(paid, as: currency)) paid of \(CurrencyFormatter.format(budget, as: currency))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                Text(statusText)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            // ── Dual-layer progress bar ──
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.gray.opacity(0.10))

                    // Committed layer (paid + expected) — tinted
                    if committedProgress > 0 {
                        Capsule()
                            .fill(statusColor.opacity(0.30))
                            .frame(width: geo.size.width * committedProgress)
                    }

                    // Paid layer — solid
                    if paidProgress > 0 {
                        Capsule()
                            .fill(statusColor)
                            .frame(width: geo.size.width * paidProgress)
                    }
                }
            }
            .frame(height: 8)

            // ── Numeric breakdown ──
            HStack(spacing: 0) {
                budgetFact(
                    label: "Paid",
                    value: CurrencyFormatter.format(paid, as: currency),
                    color: RMDesign.success
                )
                budgetSeparator
                budgetFact(
                    label: "Expected",
                    value: CurrencyFormatter.format(expected, as: currency),
                    color: RMDesign.warning
                )
                budgetSeparator
                budgetFact(
                    label: isOver ? "Over by" : "Left",
                    value: isOver
                        ? CurrencyFormatter.format(committed - budget, as: currency)
                        : CurrencyFormatter.format(remaining, as: currency),
                    color: isOver ? RMDesign.danger : RMDesign.accent
                )
            }
        }
        .padding(14)
        .background(RMDesign.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(RMDesign.borderColor, lineWidth: 1)
        )
    }

    // MARK: - Small fact column
    private func budgetFact(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var budgetSeparator: some View {
        Rectangle()
            .fill(RMDesign.dividerColor)
            .frame(width: 1, height: 22)
    }
}

// MARK: - Anomaly Row
struct AnomalyRow: View {
    let anomaly: Anomaly
    let currency: AppCurrency

    @State private var isHovered = false

    private var bill: Bill { anomaly.bill }
    private var isOverLimit: Bool { anomaly.kind.isOverLimit }

    private var badgeText: String {
        switch anomaly.kind {
        case .overLimit(let limit, _):
            return "Over \(CurrencyFormatter.format(limit, as: currency))"
        case .categoryOutlier(_, let ratio):
            return String(format: "%.1f× avg", ratio)
        }
    }

    private var detailText: String {
        switch anomaly.kind {
        case .overLimit(_, let overBy):
            return "Over limit by \(CurrencyFormatter.format(overBy, as: currency))"
        case .categoryOutlier(let avg, _):
            return "Typical: \(CurrencyFormatter.format(avg, as: currency))"
        }
    }

    private var accentColor: Color {
        isOverLimit ? RMDesign.danger : .purple
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isOverLimit ? "exclamationmark.octagon.fill" : bill.category.iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 24, height: 24)
                .background(accentColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(bill.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)

                    Text(badgeText)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                HStack(spacing: 5) {
                    Text(bill.property?.name ?? "Unknown")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(detailText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(CurrencyFormatter.format(bill.amount, as: currency))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isOverLimit ? RMDesign.danger : .primary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered ? Color.gray.opacity(0.04) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            withAnimation(RMDesign.ease) {
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

    private var isOverLimit: Bool {
        guard let limit = BillLimits.shared.limit(for: bill.title) else { return false }
        return bill.amount > limit
    }

    private var rowTint: Color {
        if isOverdue { return RMDesign.danger }
        if isOverLimit { return RMDesign.warning }
        return RMDesign.accent
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(rowTint)
                .frame(width: 2)
                .clipShape(Capsule())

            Image(systemName: bill.category.iconName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(bill.category.color)
                .frame(width: 26, height: 26)
                .background(bill.category.color.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(bill.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    if isOverLimit {
                        Text("OVER")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RMDesign.danger)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                HStack(spacing: 5) {
                    Text(bill.property?.name ?? "Unknown")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(dueText)
                        .font(.system(size: 10.5, weight: isOverdue ? .semibold : .regular))
                        .foregroundStyle(isOverdue ? RMDesign.danger : .secondary)
                }
            }

            Spacer()

            Text(CurrencyFormatter.format(bill.amount, as: currency))
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()

            Button(action: onMarkPaid) {
                Label("Pay", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(RMDesign.success)
            .controlSize(.small)
            .opacity(isHovered ? 1 : 0.75)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered ? Color.gray.opacity(0.04) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            withAnimation(RMDesign.ease) {
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
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(color.opacity(0.6))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 160)
    }
}