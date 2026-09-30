import SwiftUI
import SwiftData
import Charts

// MARK: - Buffer level
enum BudgetBufferLevel: String, CaseIterable, Identifiable {
    case tight       = "Tight"
    case comfortable = "Comfortable"
    case generous    = "Generous"

    var id: String { rawValue }

    /// Percentage added on top of the base (median) amount.
    var percent: Double {
        switch self {
        case .tight:       return 0.10   // 10% — thin margin
        case .comfortable: return 0.20   // 20% — recommended default
        case .generous:    return 0.35   // 35% — lots of slack
        }
    }

    var icon: String {
        switch self {
        case .tight:       return "minus.circle"
        case .comfortable: return "equal.circle"
        case .generous:    return "plus.circle"
        }
    }

    var explanation: String {
        switch self {
        case .tight:
            return "Just enough for a typical month with a 10% cushion."
        case .comfortable:
            return "Covers a typical month plus a 20% cushion for surprises."
        case .generous:
            return "A 35% cushion — extra room for savings or a bad month."
        }
    }
}

// MARK: - Analytics
struct MonthlyBudgetAdvisor {
    let bills: [Bill]
    private var calendar: Calendar { Calendar.current }

    struct MonthlyTotal: Identifiable, Hashable {
        let id: String
        let date: Date
        let total: Double
    }

    struct CategoryAverage: Identifiable {
        let id: String
        let category: ExpenseCategory
        let monthlyAverage: Double
        let total: Double
        let occurrences: Int
        let isRecurring: Bool
    }

    struct Recommendation {
        let windowMonths: Int
        let activeMonths: Int
        let startDate: Date
        let endDate: Date
        let monthlyTotals: [MonthlyTotal]

        // Base statistics (of active months)
        let median: Double
        let mean: Double
        let p75: Double
        let lowest: MonthlyTotal?
        let highest: MonthlyTotal?

        // Buffer + final
        let bufferLevel: BudgetBufferLevel
        let bufferAmount: Double     // absolute currency added
        let recommended: Double      // base + buffer, rounded up

        let categoryBreakdown: [CategoryAverage]
        let committedMonthly: Double
        let variableMonthly: Double
    }

    // MARK: - Compute
    func recommend(windowMonths: Int, bufferLevel: BudgetBufferLevel) -> Recommendation? {
        let now = Date()
        let start: Date

        if windowMonths <= 0 {
            guard let earliest = bills.map({ effectiveDate(for: $0) }).min() else { return nil }
            start = earliest
        } else {
            guard let s = calendar.date(byAdding: .month, value: -windowMonths, to: now) else { return nil }
            start = s
        }

        // 1. Bucket by calendar month (using effective date)
        var buckets: [Date: Double] = [:]
        for bill in bills {
            let d = effectiveDate(for: bill)
            guard d >= start, d <= now else { continue }
            guard let monthStart = calendar.dateInterval(of: .month, for: d)?.start else { continue }
            buckets[monthStart, default: 0] += bill.amount
        }

        // 2. Fill every month in the range so the chart has no gaps
        guard let firstMonth = calendar.dateInterval(of: .month, for: start)?.start else { return nil }
        var monthlyTotals: [MonthlyTotal] = []
        var cursor = firstMonth
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.timeZone = .current

        while cursor <= now {
            let total = buckets[cursor] ?? 0
            monthlyTotals.append(MonthlyTotal(
                id: formatter.string(from: cursor),
                date: cursor,
                total: total
            ))
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }

        // 3. Only count months with actual activity.
        let active = monthlyTotals.filter { $0.total > 0 }
        guard !active.isEmpty else { return nil }

        let sortedValues = active.map { $0.total }.sorted()
        let count = sortedValues.count

        let median: Double
        if count % 2 == 0 {
            median = (sortedValues[count / 2 - 1] + sortedValues[count / 2]) / 2
        } else {
            median = sortedValues[count / 2]
        }

        let mean = sortedValues.reduce(0, +) / Double(count)
        let p75Index = min(count - 1, Int((Double(count) * 0.75).rounded(.down)))
        let p75 = sortedValues[p75Index]

        // 4. Category breakdown (average per active month)
        let inRange = bills.filter {
            let d = effectiveDate(for: $0)
            return d >= start && d <= now
        }
        let byCat = Dictionary(grouping: inRange, by: { $0.category })
        let activeCount = Double(count)

        let categories: [CategoryAverage] = byCat.map { cat, list in
            let total = list.reduce(0.0) { $0 + $1.amount }
            let recurring = list.allSatisfy { $0.isRecurring }
            return CategoryAverage(
                id: cat.rawValue,
                category: cat,
                monthlyAverage: total / activeCount,
                total: total,
                occurrences: list.count,
                isRecurring: recurring
            )
        }.sorted { $0.monthlyAverage > $1.monthlyAverage }

        // 5. Committed vs variable
        let committedMonthly = inRange
            .filter { $0.isRecurring }
            .reduce(0.0) { $0 + $1.amount } / activeCount

        let variableMonthly = inRange
            .filter { !$0.isRecurring }
            .reduce(0.0) { $0 + $1.amount } / activeCount

        // 6. Buffer + headline recommendation
        let bufferAmount = median * bufferLevel.percent
        let basePlusBuffer = median + bufferAmount
        // Round up to nearest 500 so the number feels like a real target.
        let recommended = (basePlusBuffer / 500).rounded(.up) * 500

        return Recommendation(
            windowMonths: windowMonths,
            activeMonths: count,
            startDate: start,
            endDate: now,
            monthlyTotals: monthlyTotals,
            median: median,
            mean: mean,
            p75: p75,
            lowest: active.min(by: { $0.total < $1.total }),
            highest: active.max(by: { $0.total > $1.total }),
            bufferLevel: bufferLevel,
            bufferAmount: recommended - median,   // actual delta after rounding
            recommended: recommended,
            categoryBreakdown: categories,
            committedMonthly: committedMonthly,
            variableMonthly: variableMonthly
        )
    }

    private func effectiveDate(for bill: Bill) -> Date {
        bill.isPaid ? (bill.paymentDate ?? bill.dueDate) : bill.dueDate
    }
}

// MARK: - Card
struct BudgetRecommendationCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCurrency) private var currency: AppCurrency
   @Query(filter: #Predicate<Bill> { $0.isDeleted == false })
private var allBills: [Bill]
    @Query private var properties: [Property]

    @State private var window: BudgetWindow = .twelve
    @State private var bufferLevel: BudgetBufferLevel = .comfortable
    @State private var showApplyConfirm = false
    @State private var didApply = false

    enum BudgetWindow: Int, CaseIterable, Identifiable {
        case three = 3
        case six = 6
        case twelve = 12
        case twentyFour = 24
        case all = 0
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .three: return "3M"
            case .six: return "6M"
            case .twelve: return "12M"
            case .twentyFour: return "24M"
            case .all: return "All"
            }
        }
    }

    private var recommendation: MonthlyBudgetAdvisor.Recommendation? {
        MonthlyBudgetAdvisor(bills: allBills).recommend(
            windowMonths: window.rawValue,
            bufferLevel: bufferLevel
        )
    }

    private var defaultProperty: Property? {
        properties.first(where: { $0.isDefault }) ?? properties.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            bufferPicker
            if let rec = recommendation {
                headlineNumber(rec)
                statsRow(rec)
                monthlyChart(rec)
                if !rec.categoryBreakdown.isEmpty {
                    categoryBreakdown(rec)
                }
                applyRow(rec)
            } else {
                emptyState
            }
        }
        .padding(20)
        .background(RMDesign.cardBackground)
        .cornerRadius(RMDesign.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(Color.gray.opacity(0.08), lineWidth: 1)
        )
        .alert("Apply budget?", isPresented: $showApplyConfirm) {
            Button("Apply", role: .none) { applyBudget() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let rec = recommendation, let prop = defaultProperty {
                Text("Set **\(prop.name)**'s monthly budget to **\(CurrencyFormatter.format(rec.recommended, as: currency))**?\n\nThis includes a \(Int(bufferLevel.percent * 100))% breathing-room cushion (\(CurrencyFormatter.format(rec.bufferAmount, as: currency))) on top of your typical month.")
            } else {
                Text("Set the recommended amount as the monthly budget?")
            }
        }
        .onChange(of: window)      { _, _ in didApply = false }
        .onChange(of: bufferLevel) { _, _ in didApply = false }
    }

    // MARK: - Header
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "target")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.green.gradient)
                .cornerRadius(9)

            VStack(alignment: .leading, spacing: 2) {
                Text("Recommended Monthly Budget")
                    .font(.system(size: 14, weight: .semibold))
                Text("Based on your actual bill history, plus breathing room")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $window) {
                ForEach(BudgetWindow.allCases) { w in
                    Text(w.label).tag(w)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 230)
        }
    }

    // MARK: - Buffer Picker
    private var bufferPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lungs.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.teal)
                Text("Breathing room")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("+\(Int(bufferLevel.percent * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.teal)
            }

            Picker("", selection: $bufferLevel) {
                ForEach(BudgetBufferLevel.allCases) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Text(bufferLevel.explanation)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.teal.opacity(0.06))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.teal.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Headline
    private func headlineNumber(_ rec: MonthlyBudgetAdvisor.Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Big number
            Text(CurrencyFormatter.format(rec.recommended, as: currency))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            // Breakdown of base + buffer
            HStack(spacing: 8) {
                // Base
                HStack(spacing: 5) {
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                    Text("Base \(CurrencyFormatter.format(rec.median, as: currency))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.blue)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)

                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                // Buffer
                HStack(spacing: 5) {
                    Circle().fill(Color.teal).frame(width: 6, height: 6)
                    Text("Buffer \(CurrencyFormatter.format(rec.bufferAmount, as: currency))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.teal)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.teal.opacity(0.1))
                .cornerRadius(6)

                Image(systemName: "equal")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                // Total
                Text(CurrencyFormatter.format(rec.recommended, as: currency))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(6)
            }

            // Explanation line
            Text(headlineExplanation(rec))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.12), Color.mint.opacity(0.05)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }

    private func headlineExplanation(_ rec: MonthlyBudgetAdvisor.Recommendation) -> String {
        let base = "Your typical month costs around \(CurrencyFormatter.format(rec.median, as: currency))."
        switch bufferLevel {
        case .tight:
            return base + " Adding a small 10% cushion."
        case .comfortable:
            return base + " Adding a comfortable 20% cushion so there's room left after paying bills."
        case .generous:
            return base + " Adding a generous 35% cushion for savings or an unexpected month."
        }
    }

    // MARK: - Stats Row
    private func statsRow(_ rec: MonthlyBudgetAdvisor.Recommendation) -> some View {
        HStack(spacing: 10) {
            AdvisorStat(
                title: "Typical",
                value: CurrencyFormatter.format(rec.median, as: currency),
                subtitle: "\(rec.activeMonths) active months",
                icon: "chart.line.uptrend.xyaxis",
                color: .blue
            )
            AdvisorStat(
                title: "Buffer",
                value: "+\(Int(bufferLevel.percent * 100))%",
                subtitle: CurrencyFormatter.format(rec.bufferAmount, as: currency),
                icon: "lungs.fill",
                color: .teal
            )
            AdvisorStat(
                title: "Peak month",
                value: rec.highest.map { CurrencyFormatter.format($0.total, as: currency) } ?? "—",
                subtitle: rec.highest.map { shortMonth($0.date) } ?? "",
                icon: "arrow.up.circle.fill",
                color: .red
            )
            AdvisorStat(
                title: "Lowest",
                value: rec.lowest.map { CurrencyFormatter.format($0.total, as: currency) } ?? "—",
                subtitle: rec.lowest.map { shortMonth($0.date) } ?? "",
                icon: "arrow.down.circle.fill",
                color: .orange
            )
        }
    }

    // MARK: - Chart
    private func monthlyChart(_ rec: MonthlyBudgetAdvisor.Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Month-by-month spend")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                HStack(spacing: 10) {
                    legend(color: .green, label: "Recommended")
                    legend(color: .blue,   label: "Base")
                }
            }

            Chart {
                // Base line (median)
                RuleMark(
                    y: .value("Base", CurrencyFormatter.convert(rec.median, to: currency))
                )
                .foregroundStyle(Color.blue.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Base")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.blue)
                }

                // Recommended line
                RuleMark(
                    y: .value("Recommended", CurrencyFormatter.convert(rec.recommended, to: currency))
                )
                .foregroundStyle(Color.green)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Recommended")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.green)
                }

                ForEach(rec.monthlyTotals) { point in
                    BarMark(
                        x: .value("Month", point.date),
                        y: .value("Amount", CurrencyFormatter.convert(point.total, to: currency)),
                        width: .fixed(14)
                    )
                    .foregroundStyle(
                        point.total > rec.recommended
                            ? Color.red.gradient
                            : point.total > rec.median
                                ? Color.orange.gradient
                                : Color.blue.gradient
                    )
                    .cornerRadius(3)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 8)) { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.1))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.dateTime.month(.abbreviated).year(.twoDigits)))
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.1))
                    AxisValueLabel {
                        if let amount = value.as(Double.self), amount.isFinite {
                            Text(CurrencyFormatter.compact(
                                CurrencyFormatter.toKsh(amount, from: currency),
                                as: currency
                            ))
                            .font(.system(size: 9))
                        }
                    }
                }
            }
            .frame(height: 190)

            Text("Bars above the recommended line are months where you went over budget. Blue = under base, orange = between base and recommended, red = over recommended.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Category Breakdown
    private func categoryBreakdown(_ rec: MonthlyBudgetAdvisor.Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Average per category")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                HStack(spacing: 12) {
                    legend(color: .blue, label: "Committed (recurring)")
                    legend(color: .orange, label: "Variable")
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(rec.categoryBreakdown.prefix(8).enumerated()), id: \.element.id) { idx, item in
                    HStack(spacing: 10) {
                        Image(systemName: item.category.iconName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(item.category.color)
                            .frame(width: 22, height: 22)
                            .background(item.category.color.opacity(0.12))
                            .cornerRadius(6)

                        Text(item.category.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)

                        if item.isRecurring {
                            Text("recurring")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }

                        Spacer()

                        Text("\(item.occurrences) bills")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        Text(CurrencyFormatter.format(item.monthlyAverage, as: currency))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 130, alignment: .trailing)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)

                    if idx < min(rec.categoryBreakdown.count, 8) - 1 {
                        Divider().padding(.leading, 42)
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.4))
            .cornerRadius(10)

            HStack(spacing: 16) {
                Text("Committed: \(CurrencyFormatter.format(rec.committedMonthly, as: currency))/mo")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.blue)
                Text("Variable: \(CurrencyFormatter.format(rec.variableMonthly, as: currency))/mo")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                Spacer()
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Apply Row
    private func applyRow(_ rec: MonthlyBudgetAdvisor.Recommendation) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Apply this budget")
                    .font(.system(size: 12, weight: .semibold))
                Text(applySubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if didApply {
                Label("Applied", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button {
                    showApplyConfirm = true
                } label: {
                    Label("Set Budget", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(defaultProperty == nil)
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.06))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.green.opacity(0.15), lineWidth: 1)
        )
    }

    private var applySubtitle: String {
        guard let prop = defaultProperty else { return "No property available" }
        return "Sets the monthly budget on '\(prop.name)'"
    }

    // MARK: - Empty
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "target")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Not enough data yet")
                .font(.system(size: 13, weight: .semibold))
            Text("Add or import bills to see a recommended monthly budget.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Apply
    private func applyBudget() {
        guard let rec = recommendation, let prop = defaultProperty else { return }
        prop.monthlyBudget = rec.recommended
        prop.updatedAt = Date()
        prop.syncStatus = .pendingUpload
        try? modelContext.save()
        SyncService.shared.schedulePush()
        didApply = true
    }

    // MARK: - Small helpers
    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    private func shortMonth(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
    }
}

// MARK: - Stat pill
private struct AdvisorStat: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
            }
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(NSColor.textBackgroundColor).opacity(0.4))
        .cornerRadius(9)
    }
}