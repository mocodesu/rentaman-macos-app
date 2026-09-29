import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.appCurrency) private var currency: AppCurrency
    @Query private var properties: [Property]
    @Query private var allBills: [Bill]
    
    @State private var selectedPropertyId: String? = nil
    
    private var filteredBills: [Bill] {
        if let selectedId = selectedPropertyId {
            return allBills.filter { $0.property?.id == selectedId }
        }
        return allBills
    }
    
    private var analytics: DashboardAnalytics {
        DashboardAnalytics(bills: filteredBills)
    }
    
    private var totalBudget: Double {
        if let selectedId = selectedPropertyId,
           let prop = properties.first(where: { $0.id == selectedId }) {
            return prop.monthlyBudget
        }
        return properties.reduce(0.0) { $0 + $1.monthlyBudget }
    }
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                HStack {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.title)
                        .foregroundStyle(.blue)
                    Text("Dashboard")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Picker("Filter by Property", selection: $selectedPropertyId) {
                        Text("All Properties").tag(nil as String?)
                        ForEach(properties) { property in
                            Text(property.name).tag(property.id as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
                .padding(.horizontal)
                
                LazyVGrid(columns: columns, spacing: 16) {
                    KPICard(
                        title: "Unpaid Bills",
                        value: "\(analytics.unpaidBills.count)",
                        subtitle: CurrencyFormatter.format(analytics.totalUnpaidAmount, as: currency),
                        icon: "exclamationmark.triangle.fill",
                        color: .red
                    )
                    KPICard(
                        title: "Upcoming (7 Days)",
                        value: "\(analytics.upcomingBills.count)",
                        subtitle: "Bills due soon",
                        icon: "clock.fill",
                        color: .orange
                    )
                    KPICard(
                        title: "Spent This Month",
                        value: CurrencyFormatter.format(analytics.totalSpentThisMonth, as: currency),
                        subtitle: "Budget: \(CurrencyFormatter.format(totalBudget, as: currency))",
                        icon: "chart.pie.fill",
                        color: .blue
                    )
                    KPICard(
                        title: "Anomalies Detected",
                        value: "\(analytics.anomalies.count)",
                        subtitle: "Unusually high bills",
                        icon: "bell.badge.fill",
                        color: .purple
                    )
                }
                .padding(.horizontal)
                
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: "chart.pie.fill")
                                .foregroundStyle(.blue)
                            Text("Expenses by Category")
                                .font(.headline)
                            Spacer()
                        }
                        
                        if analytics.expensesByCategory.isEmpty || analytics.totalSpentThisMonth <= 0 {
                            VStack(spacing: 8) {
                                Image(systemName: "chart.pie")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("No expenses this month.")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Chart(analytics.expensesByCategory) { item in
                                SectorMark(
                                    angle: .value("Amount", item.amount),
                                    innerRadius: .ratio(0.6),
                                    angularInset: 1.5
                                )
                                .foregroundStyle(item.color)
                                .annotation(position: .overlay) {
                                    let share = item.amount / analytics.totalSpentThisMonth
                                    if share.isFinite && share > 0.15 {
                                        Text("\(Int(share * 100))%")
                                            .font(.caption2)
                                            .foregroundStyle(.white)
                                            .fontWeight(.bold)
                                    }
                                }
                            }
                            .chartLegend(position: .bottom, alignment: .center, spacing: 10)
                            .frame(height: 250)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: "bell.badge.fill")
                                .foregroundStyle(.purple)
                            Text("Recent Anomalies")
                                .font(.headline)
                                .foregroundStyle(.purple)
                            Spacer()
                        }
                        
                        if analytics.anomalies.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.green)
                                Text("No anomalies detected.")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List(analytics.anomalies.prefix(4)) { bill in
                                HStack {
                                    Image(systemName: bill.category.iconName)
                                        .foregroundStyle(bill.category.color)
                                    VStack(alignment: .leading) {
                                        Text(bill.title).fontWeight(.medium)
                                        Text(bill.property?.name ?? "Unknown House")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(CurrencyFormatter.format(bill.amount, as: currency))
                                        .fontWeight(.bold)
                                        .foregroundStyle(.red)
                                }
                                .padding(.vertical, 4)
                            }
                            .listStyle(.plain)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .frame(height: 300)
                
                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: "list.bullet.circle.fill")
                            .foregroundStyle(.red)
                        Text("Action Center: Unpaid Bills")
                            .font(.headline)
                        Spacer()
                    }
                    
                    if analytics.unpaidBills.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.green)
                            Text("All bills are paid! Great job.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        List(analytics.unpaidBills) { bill in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(bill.title).fontWeight(.medium)
                                    Text("\(bill.category.rawValue) • Due: \(bill.dueDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(CurrencyFormatter.format(bill.amount, as: currency))
                                    .fontWeight(.bold)
                                
                                Button {
                                    bill.isPaid = true
                                    bill.paymentDate = Date()
                                    bill.syncStatus = .pendingUpload
                                    bill.updatedAt = Date()
                                    
                                    // 🔥 Trigger sync
                                    SyncService.shared.schedulePush()
                                } label: {
                                    Label("Mark Paid", systemImage: "checkmark.circle")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(height: 200)
                        .listStyle(.plain)
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

// MARK: - Reusable KPI Card Component
struct KPICard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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