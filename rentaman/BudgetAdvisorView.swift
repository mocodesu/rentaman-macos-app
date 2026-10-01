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
        VStack(alignment: .leading, spacing: 16) {
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
        .padding(16)
        .background(RMDesign.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(RMDesign.borderColor, lineWidth: 1)
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
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "target")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(RMDesign.success)
                .frame(width: 24, height: 24)
                .background(RMDesign.success.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text("Recommended Monthly Budget")
                    .font(.system(size: 13, weight: .semibold))
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
            .frame(width: 220)
        }
    }

    // MARK: - Buffer Picker
    private var bufferPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lungs.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.teal)
                Text("Breathing room")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("+\(Int(bufferLevel.percent * 100))%")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
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
        .background(Color.teal.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(Color.teal.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Headline
    private func headlineNumber(_ rec: MonthlyBudgetAdvisor.Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(CurrencyFormatter.format(rec.recommended, as: currency))
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            HStack(spacing: 6) {
                // Base
                HStack(spacing: 4) {
                    Circle().fill(RMDesign.accent).frame(width: 6, height: 6)
                    Text("Base \(CurrencyFormatter.format(rec.median, as: currency))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(RMDesign.accent)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RMDesign.accent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 5))

                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)

                // Buffer
                HStack(spacing: 4) {
                    Circle().fill(.teal).frame(width: 6, height: 6)
                    Text("Buffer \(CurrencyFormatter.format(rec.bufferAmount, as: currency))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.teal)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.teal.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 5))

                Image(systemName: "equal")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)

                // Total
                Text(CurrencyFormatter.format(rec.recommended, as: currency))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(RMDesign.success)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RMDesign.success.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            Text(headlineExplanation(rec))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.green.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(RMDesign.success.opacity(0.15), lineWidth: 1)
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
        HStack(spacing: 8) {
            AdvisorStat(
                title: "Typical",
                value: CurrencyFormatter.format(rec.median, as: currency),
                subtitle: "\(rec.activeMonths) active months",
                icon: "chart.line.uptrend.xyaxis",
                color: RMDesign.accent
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
                color: RMDesign.danger
            )
            AdvisorStat(
                title: "Lowest",
                value: rec.lowest.map { CurrencyFormatter.format($0.total, as: currency) } ?? "—",
                subtitle: rec.lowest.map { shortMonth($0.date) } ?? "",
                icon: "arrow.down.circle.fill",
                color: RMDesign.warning
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
                    legend(color: RMDesign.success, label: "Recommended")
                    legend(color: RMDesign.accent,   label: "Base")
                }
            }

            Chart {
                // Base line (median)
                RuleMark(
                    y: .value("Base", CurrencyFormatter.convert(rec.median, to: currency))
                )
                .foregroundStyle(RMDesign.accent.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Base")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(RMDesign.accent)
                }

                // Recommended line
                RuleMark(
                    y: .value("Recommended", CurrencyFormatter.convert(rec.recommended, to: currency))
                )
                .foregroundStyle(RMDesign.success)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Recommended")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(RMDesign.success)
                }

                ForEach(rec.monthlyTotals) { point in
                    BarMark(
                        x: .value("Month", point.date),
                        y: .value("Amount", CurrencyFormatter.convert(point.total, to: currency)),
                        width: .fixed(14)
                    )
                    .foregroundStyle(
                        point.total > rec.recommended
                            ? RMDesign.danger
                            : point.total > rec.median
                                ? RMDesign.warning
                                : RMDesign.accent
                    )
                    .cornerRadius(3)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 8)) { value in
                    AxisGridLine().foregroundStyle(RMDesign.dividerColor)
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
                    AxisGridLine().foregroundStyle(RMDesign.dividerColor)
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
            .frame(height: 180)

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
                    legend(color: RMDesign.accent, label: "Committed (recurring)")
                    legend(color: RMDesign.warning, label: "Variable")
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(rec.categoryBreakdown.prefix(8).enumerated()), id: \.element.id) { idx, item in
                    HStack(spacing: 10) {
                        Image(systemName: item.category.iconName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(item.category.color)
                            .frame(width: 22, height: 22)
                            .background(item.category.color.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Text(item.category.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)

                        if item.isRecurring {
                            Text("recurring")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(RMDesign.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(RMDesign.accent.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }

                        Spacer()

                        Text("\(item.occurrences) bills")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        Text(CurrencyFormatter.format(item.monthlyAverage, as: currency))
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .frame(width: 130, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)

                    if idx < min(rec.categoryBreakdown.count, 8) - 1 {
                        Divider().padding(.leading, 40)
                    }
                }
            }
            .background(RMDesign.fieldBackground.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))

            HStack(spacing: 16) {
                Text("Committed: \(CurrencyFormatter.format(rec.committedMonthly, as: currency))/mo")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RMDesign.accent)
                Text("Variable: \(CurrencyFormatter.format(rec.variableMonthly, as: currency))/mo")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RMDesign.warning)
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
                    .foregroundStyle(RMDesign.success)
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
        .background(Color.green.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(RMDesign.success.opacity(0.15), lineWidth: 1)
        )
    }

    private var applySubtitle: String {
        guard let prop = defaultProperty else { return "No property available" }
        return "Sets the monthly budget on '\(prop.name)'"
    }

    // MARK: - Empty
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "target")
                .font(.system(size: 28, weight: .light))
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(color)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
            }
            Text(value)
                .font(.system(size: 13, weight: .semibold))
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
        .background(RMDesign.fieldBackground.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
    }
}