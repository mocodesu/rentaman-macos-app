import SwiftUI
import SwiftData
import Charts

struct ReportsView: View {
    @Environment(\.appCurrency) private var currency: AppCurrency
    @Environment(SyncService.self) private var syncService
    @Query(filter: #Predicate<Bill> { $0.isDeleted == false })
private var allBills: [Bill]
    @Query private var properties: [Property]
    
    @State private var selectedPropertyId: String? = nil
    
    private var filteredBills: [Bill] {
        if let propId = selectedPropertyId {
            return allBills.filter { $0.property?.id == propId }
        }
        return allBills
    }
    
    private var filteredProperties: [Property] {
        if let propId = selectedPropertyId {
            return properties.filter { $0.id == propId }
        }
        return properties
    }
    
    private var analytics: ReportsAnalytics {
        ReportsAnalytics(bills: filteredBills, properties: filteredProperties)
    }
    
    private let kpiColumns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 14),
        count: 4
    )
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // MARK: - Header
                HStack(alignment: .center) {
                    RMPageHeader(
                        icon: "chart.pie.fill",
                        title: "Reports & Analytics",
                        subtitle: "\(analytics.totalBillsThisYear) bill\(analytics.totalBillsThisYear == 1 ? "" : "s") this year"
                    )
                    
                    Spacer()
                    
                    liveFreshnessIndicator
                    
                    PropertyFilterMenu(
                        properties: properties,
                        selection: $selectedPropertyId
                    )
                }
                .padding(.horizontal, 24)
                
                // MARK: - KPI Cards
                LazyVGrid(columns: kpiColumns, spacing: 14) {
                    HeroKPICard(
                        title: "Total Spent",
                        value: CurrencyFormatter.format(analytics.totalSpentThisYear, as: currency),
                        subtitle: "This year",
                        icon: "banknote.fill",
                        gradient: LinearGradient(
                            colors: [Color(red: 0.28, green: 0.55, blue: 0.98),
                                     Color(red: 0.45, green: 0.28, blue: 0.92)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        iconAccent: .blue
                    )
                    
                    HeroKPICard(
                        title: "This Month",
                        value: CurrencyFormatter.format(analytics.totalSpentThisMonth, as: currency),
                        subtitle: analytics.thisMonthLabel,
                        icon: "calendar",
                        gradient: LinearGradient(
                            colors: [Color(red: 0.15, green: 0.75, blue: 0.55),
                                     Color(red: 0.08, green: 0.65, blue: 0.42)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        iconAccent: .green
                    )
                    
                    HeroKPICard(
                        title: "Monthly Average",
                        value: CurrencyFormatter.format(analytics.averageMonthlySpend, as: currency),
                        subtitle: "12-month average",
                        icon: "chart.line.uptrend.xyaxis",
                        gradient: LinearGradient(
                            colors: [Color(red: 0.62, green: 0.28, blue: 0.95),
                                     Color(red: 0.85, green: 0.25, blue: 0.75)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        iconAccent: .purple
                    )
                    
                    HeroKPICard(
                        title: "Over Budget",
                        value: "\(analytics.propertiesOverBudget.count)",
                        subtitle: analytics.propertiesOverBudget.isEmpty
                            ? "All on track"
                            : analytics.propertiesOverBudget.joined(separator: ", "),
                        icon: "exclamationmark.triangle.fill",
                        gradient: analytics.propertiesOverBudget.isEmpty
                            ? LinearGradient(
                                colors: [Color(red: 0.15, green: 0.75, blue: 0.55),
                                         Color(red: 0.08, green: 0.65, blue: 0.42)],
                                startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(
                                colors: [Color(red: 0.95, green: 0.35, blue: 0.35),
                                         Color(red: 0.85, green: 0.15, blue: 0.35)],
                                startPoint: .topLeading, endPoint: .bottomTrailing),
                        iconAccent: analytics.propertiesOverBudget.isEmpty ? .green : .red
                    )
                }
                .padding(.horizontal, 24)
                
                // 🆕 Recommended budget advisor
BudgetRecommendationCard()
    .padding(.horizontal, 24)
    
    // After the BudgetRecommendationCard line:
CashFlowPlannerView()
    .padding(.horizontal, 24)
                // MARK: - Payment Rate Strip
                if analytics.totalBillsThisYear > 0 {
                    PaymentRateStrip(
                        paid: analytics.paidBillsThisYear,
                        unpaid: analytics.unpaidBillsThisYear,
                        rate: analytics.paymentRate
                    )
                    .padding(.horizontal, 24)
                }
                
                // MARK: - Monthly Trend
                RMContentCard(
                    title: "Monthly Spending Trend",
                    icon: "chart.xyaxis.line",
                    iconColor: .blue,
                    subtitle: "Last 12 months"
                ) {
                    if analytics.monthlyTrend.allSatisfy({ $0.amount == 0 }) {
                        SmallEmptyState(
                            icon: "chart.line.uptrend.xyaxis",
                            message: "No spending data for the last 12 months"
                        )
                    } else {
                        Chart(analytics.monthlyTrend) { point in
                            AreaMark(
                                x: .value("Month", point.date),
                                y: .value("Amount", CurrencyFormatter.convert(point.amount, to: currency))
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue.opacity(0.25), .blue.opacity(0.02)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.monotone)
                            
                            LineMark(
                                x: .value("Month", point.date),
                                y: .value("Amount", CurrencyFormatter.convert(point.amount, to: currency))
                            )
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.monotone)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .month)) { _ in
                                AxisGridLine().foregroundStyle(.gray.opacity(0.15))
                                AxisValueLabel(format: .dateTime.month(.abbreviated))
                                    .font(.system(size: 10))
                            }
                        }
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine().foregroundStyle(.gray.opacity(0.15))
                                AxisValueLabel {
                                    if let amount = value.as(Double.self), amount.isFinite {
                                        Text(CurrencyFormatter.compact(
                                            CurrencyFormatter.toKsh(amount, from: currency),
                                            as: currency
                                        ))
                                        .font(.system(size: 10))
                                    }
                                }
                            }
                        }
                        .frame(height: 260)
                    }
                }
                .padding(.horizontal, 24)
                
                // MARK: - Category & Property Comparison
                HStack(alignment: .top, spacing: 14) {
                    RMContentCard(
                        title: "Category Breakdown",
                        icon: "chart.bar.fill",
                        iconColor: .orange,
                        subtitle: "Current year"
                    ) {
                        if analytics.categoryBreakdown.isEmpty {
                            SmallEmptyState(
                                icon: "chart.bar",
                                message: "No category data yet"
                            )
                        } else {
                            Chart(analytics.categoryBreakdown) { point in
                                BarMark(
                                    x: .value("Amount", CurrencyFormatter.convert(point.amount, to: currency)),
                                    y: .value("Category", point.category.rawValue)
                                )
                                .foregroundStyle(point.category.color.gradient)
                                .cornerRadius(5)
                            }
                            .chartXAxis(.hidden)
                            .frame(height: 320)
                        }
                    }
                    
                    RMContentCard(
                        title: "Spending by Property",
                        icon: "house.fill",
                        iconColor: .green,
                        subtitle: "Current year"
                    ) {
                        if analytics.propertyComparison.isEmpty || analytics.propertyComparison.allSatisfy({ $0.amount == 0 }) {
                            SmallEmptyState(
                                icon: "house",
                                message: "No property data yet"
                            )
                        } else {
                            Chart(analytics.propertyComparison) { point in
                                BarMark(
                                    x: .value("Property", point.name),
                                    y: .value("Amount", CurrencyFormatter.convert(point.amount, to: currency))
                                )
                                .foregroundStyle(point.color.gradient)
                                .cornerRadius(6)
                            }
                            .frame(height: 320)
                        }
                    }
                }
                .padding(.horizontal, 24)
                
                // MARK: - Budget vs Actual
                RMContentCard(
                    title: "Budget vs Actual",
                    icon: "gauge.medium",
                    iconColor: .purple,
                    subtitle: analytics.budgetVsActualLabel
                ) {
                    if analytics.budgetVsActual.isEmpty || analytics.budgetVsActual.allSatisfy({ $0.budget == 0 }) {
                        SmallEmptyState(
                            icon: "gauge",
                            message: "Set a monthly budget on each property to see this chart"
                        )
                    } else {
                        Chart {
                            ForEach(analytics.budgetVsActual) { point in
                                BarMark(
                                    x: .value("Property", point.name),
                                    y: .value("Amount", CurrencyFormatter.convert(point.budget, to: currency))
                                )
                                .foregroundStyle(.gray.opacity(0.35))
                                .position(by: .value("Type", "Budget"))
                                .cornerRadius(4)
                            }
                            ForEach(analytics.budgetVsActual) { point in
                                BarMark(
                                    x: .value("Property", point.name),
                                    y: .value("Amount", CurrencyFormatter.convert(point.spent, to: currency))
                                )
                                .foregroundStyle(point.spent > point.budget ? Color.red.gradient : Color.green.gradient)
                                .position(by: .value("Type", "Spent"))
                                .cornerRadius(4)
                            }
                        }
                        .chartLegend(position: .bottom, spacing: 16)
                        .frame(height: 280)
                    }
                }
                .padding(.horizontal, 24)
                
                // MARK: - Top 10 Expenses
                RMContentCard(
                    title: "Top 10 Expenses",
                    icon: "flame.fill",
                    iconColor: .orange,
                    subtitle: "Current year"
                ) {
                    if analytics.topExpenses.isEmpty {
                        SmallEmptyState(
                            icon: "flame",
                            message: "No expenses recorded this year"
                        )
                    } else {
                        VStack(spacing: 4) {
                            ForEach(Array(analytics.topExpenses.enumerated()), id: \.element.id) { index, bill in
                                TopExpenseRow(
                                    rank: index + 1,
                                    bill: bill,
                                    currency: currency,
                                    isLast: index == analytics.topExpenses.count - 1
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 24)
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
            .help("Reports update automatically as data syncs")
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
}

// MARK: - Payment Rate Strip
struct PaymentRateStrip: View {
    let paid: Int
    let unpaid: Int
    let rate: Double
    
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Payment Progress")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(paid) paid · \(unpaid) unpaid")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.red.opacity(0.2))
                        .frame(height: 8)
                    
                    Capsule()
                        .fill(Color.green.gradient)
                        .frame(width: geo.size.width * rate, height: 8)
                }
            }
            .frame(height: 8)
            .frame(maxWidth: 200)
            
            Text("\(Int(rate * 100))%")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(rate > 0.8 ? .green : rate > 0.5 ? .orange : .red)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(16)
        .background(RMDesign.cardBackground)
        .cornerRadius(RMDesign.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(Color.gray.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Top Expense Row
struct TopExpenseRow: View {
    let rank: Int
    let bill: Bill
    let currency: AppCurrency
    let isLast: Bool
    
    @State private var isHovered = false
    
    private var rankColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .secondary
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(rank <= 3 ? rankColor.opacity(0.15) : Color.gray.opacity(0.08))
                        .frame(width: 30, height: 30)
                    Text("\(rank)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(rank <= 3 ? rankColor : .secondary)
                }
                
                Image(systemName: bill.category.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(bill.category.color)
                    .frame(width: 30, height: 30)
                    .background(bill.category.color.opacity(0.12))
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(bill.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        if let prop = bill.property {
                            Text(prop.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(bill.category.rawValue)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Text(bill.dueDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                Text(CurrencyFormatter.format(bill.amount, as: currency))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 130, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.blue.opacity(0.04) : Color.clear)
            .cornerRadius(8)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            
            if !isLast {
                Divider().padding(.leading, 54).opacity(0.6)
            }
        }
    }
}