import SwiftUI
import SwiftData
import Charts

struct ReportsView: View {
    @Environment(\.appCurrency) private var currency: AppCurrency
    @Query private var allBills: [Bill]
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
    
    private var kpiColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // MARK: - Header
                HStack(alignment: .center) {
                    RMPageHeader(
                        icon: "chart.pie.fill",
                        title: "Reports & Analytics",
                        subtitle: "Insights into your spending patterns"
                    )
                    
                    Spacer()
                    
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
                        subtitle: "Current month",
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
                            message: "No spending data yet"
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
                        if analytics.propertyComparison.isEmpty {
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
                    subtitle: "Current month"
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
                // Rank badge
                ZStack {
                    Circle()
                        .fill(rank <= 3 ? rankColor.opacity(0.15) : Color.gray.opacity(0.08))
                        .frame(width: 30, height: 30)
                    Text("\(rank)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(rank <= 3 ? rankColor : .secondary)
                }
                
                // Category icon
                Image(systemName: bill.category.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(bill.category.color)
                    .frame(width: 30, height: 30)
                    .background(bill.category.color.opacity(0.12))
                    .cornerRadius(8)
                
                // Info
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
                
                // Due date
                Text(bill.dueDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                // Amount
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