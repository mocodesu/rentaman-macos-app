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
    
    private let kpiColumns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                HStack {
                    Image(systemName: "chart.pie.fill")
                        .font(.title)
                        .foregroundStyle(.blue)
                    Text("Reports & Analytics")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Picker("Property", selection: $selectedPropertyId) {
                        Text("All Properties").tag(nil as String?)
                        ForEach(properties) { prop in
                            Text(prop.name).tag(prop.id as String?)
                        }
                    }
                    .frame(width: 180)
                }
                .padding(.horizontal)
                
                LazyVGrid(columns: kpiColumns, spacing: 16) {
                    ReportKPICard(
                        title: "Total Spent",
                        value: CurrencyFormatter.format(analytics.totalSpentThisYear, as: currency),
                        subtitle: "This year",
                        icon: "banknote.fill",
                        color: .blue
                    )
                    ReportKPICard(
                        title: "This Month",
                        value: CurrencyFormatter.format(analytics.totalSpentThisMonth, as: currency),
                        subtitle: "Current month",
                        icon: "calendar",
                        color: .green
                    )
                    ReportKPICard(
                        title: "Monthly Average",
                        value: CurrencyFormatter.format(analytics.averageMonthlySpend, as: currency),
                        subtitle: "12-month average",
                        icon: "chart.line.uptrend.xyaxis",
                        color: .purple
                    )
                    ReportKPICard(
                        title: "Over Budget",
                        value: "\(analytics.propertiesOverBudget.count)",
                        subtitle: analytics.propertiesOverBudget.isEmpty ? "All on track" : analytics.propertiesOverBudget.joined(separator: ", "),
                        icon: "exclamationmark.triangle.fill",
                        color: analytics.propertiesOverBudget.isEmpty ? .green : .red
                    )
                }
                .padding(.horizontal)
                
                ChartCard(title: "Monthly Spending Trend", subtitle: "Last 12 months") {
                    if analytics.monthlyTrend.allSatisfy({ $0.amount == 0 }) {
                        EmptyChartState(message: "No spending data for the last 12 months.")
                    } else {
                        Chart(analytics.monthlyTrend) { point in
                            AreaMark(
                                x: .value("Month", point.date),
                                y: .value("Amount", CurrencyFormatter.convert(point.amount, to: currency))
                            )
                            .foregroundStyle(.blue.opacity(0.15))
                            .interpolationMethod(.monotone)
                            
                            LineMark(
                                x: .value("Month", point.date),
                                y: .value("Amount", CurrencyFormatter.convert(point.amount, to: currency))
                            )
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.monotone)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .month)) { _ in
                                AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                                AxisValueLabel(format: .dateTime.month(.abbreviated))
                            }
                        }
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                                AxisValueLabel {
                                    if let amount = value.as(Double.self), amount.isFinite {
                                        Text(CurrencyFormatter.compact(CurrencyFormatter.toKsh(amount, from: currency), as: currency))
                                            .font(.caption2)
                                    }
                                }
                            }
                        }
                        .frame(height: 260)
                    }
                }
                .padding(.horizontal)
                
                HStack(alignment: .top, spacing: 16) {
                    ChartCard(title: "Category Breakdown", subtitle: "Current year") {
                        if analytics.categoryBreakdown.isEmpty {
                            EmptyChartState(message: "No category data.")
                        } else {
                            Chart(analytics.categoryBreakdown) { point in
                                BarMark(
                                    x: .value("Amount", CurrencyFormatter.convert(point.amount, to: currency)),
                                    y: .value("Category", point.category.rawValue)
                                )
                                .foregroundStyle(point.category.color)
                                .cornerRadius(4)
                            }
                            .chartXAxis(.hidden)
                            .frame(height: 320)
                        }
                    }
                    
                    ChartCard(title: "Spending by Property", subtitle: "Current year") {
                        if analytics.propertyComparison.isEmpty {
                            EmptyChartState(message: "No property data.")
                        } else {
                            Chart(analytics.propertyComparison) { point in
                                BarMark(
                                    x: .value("Property", point.name),
                                    y: .value("Amount", CurrencyFormatter.convert(point.amount, to: currency))
                                )
                                .foregroundStyle(point.color)
                                .cornerRadius(6)
                            }
                            .frame(height: 320)
                        }
                    }
                }
                .padding(.horizontal)
                
                ChartCard(title: "Budget vs Actual", subtitle: "Current month") {
                    if analytics.budgetVsActual.isEmpty || analytics.budgetVsActual.allSatisfy({ $0.budget == 0 }) {
                        EmptyChartState(message: "No budgets set. Add a budget to each property to see this chart.")
                    } else {
                        Chart {
                            ForEach(analytics.budgetVsActual) { point in
                                BarMark(
                                    x: .value("Property", point.name),
                                    y: .value("Amount", CurrencyFormatter.convert(point.budget, to: currency))
                                )
                                .foregroundStyle(.gray.opacity(0.4))
                                .position(by: .value("Type", "Budget"))
                                .cornerRadius(4)
                            }
                            ForEach(analytics.budgetVsActual) { point in
                                BarMark(
                                    x: .value("Property", point.name),
                                    y: .value("Amount", CurrencyFormatter.convert(point.spent, to: currency))
                                )
                                .foregroundStyle(point.spent > point.budget ? Color.red : Color.green)
                                .position(by: .value("Type", "Spent"))
                                .cornerRadius(4)
                            }
                        }
                        .chartLegend(position: .bottom)
                        .frame(height: 280)
                    }
                }
                .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("Top 10 Expenses")
                            .font(.headline)
                        Spacer()
                        Text("Current year")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if analytics.topExpenses.isEmpty {
                        Text("No expenses recorded this year.")
                            .foregroundStyle(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(Array(analytics.topExpenses.enumerated()), id: \.element.id) { index, bill in
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, alignment: .leading)
                                
                                Image(systemName: bill.category.iconName)
                                    .foregroundStyle(bill.category.color)
                                    .frame(width: 20)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bill.title).fontWeight(.medium)
                                    Text("\(bill.property?.name ?? "Unknown") • \(bill.category.rawValue)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Text(bill.dueDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Text(CurrencyFormatter.format(bill.amount, as: currency))
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                    .frame(width: 130, alignment: .trailing)
                            }
                            .padding(.vertical, 6)
                            
                            if index < analytics.topExpenses.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Reusable Chart Card Wrapper
struct ChartCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Reusable Report KPI Card
struct ReportKPICard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Empty Chart State
struct EmptyChartState: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
