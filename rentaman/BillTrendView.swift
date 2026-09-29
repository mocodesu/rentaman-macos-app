import SwiftUI
import SwiftData
import Charts

// MARK: - Scope
enum TrendScope: String, CaseIterable, Identifiable {
    case everything = "All Bills"
    case bill       = "By Bill"
    case category   = "By Category"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .everything: return "square.stack.3d.up"
        case .bill:       return "doc.text"
        case .category:   return "tag"
        }
    }
}

// MARK: - Granularity
enum TrendGranularity: String, CaseIterable, Identifiable {
    case day   = "Day"
    case week  = "Week"
    case month = "Month"
    case year  = "Year"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .day:   return "calendar"
        case .week:  return "calendar.badge.clock"
        case .month: return "calendar.circle"
        case .year:  return "calendar.badge.plus"
        }
    }
}

// MARK: - Point
struct TrendPoint: Identifiable, Hashable {
    let id: Date
    let date: Date
    let amount: Double
    let count: Int
}

// MARK: - Analytics
struct TrendAnalytics {
    let bills: [Bill]
    private var calendar: Calendar { Calendar.current }

    private func effectiveDate(for bill: Bill) -> Date {
        bill.isPaid ? (bill.paymentDate ?? bill.dueDate) : bill.dueDate
    }

    func points(
        scope: TrendScope,
        billTitle: String?,
        category: ExpenseCategory?,
        granularity: TrendGranularity,
        rangeMonths: Int
    ) -> [TrendPoint] {
        let now = Date()
        guard let start = calendar.date(byAdding: .month, value: -rangeMonths, to: now) else {
            return []
        }

        // 1. Scope filter
        var filtered = bills
        switch scope {
        case .everything:
            break
        case .bill:
            guard let t = billTitle, !t.isEmpty else { return [] }
            filtered = filtered.filter { $0.title.caseInsensitiveCompare(t) == .orderedSame }
        case .category:
            guard let c = category else { return [] }
            filtered = filtered.filter { $0.category == c }
        }

        // 2. Date range filter
        filtered = filtered.filter { effectiveDate(for: $0) >= start }

        // 3. Bucket
        var buckets: [Date: (amount: Double, count: Int)] = [:]
        for bill in filtered {
            let d = effectiveDate(for: bill)
            guard let bucketStart = startOfBucket(d, granularity: granularity) else { continue }
            var entry = buckets[bucketStart] ?? (0, 0)
            entry.amount += bill.amount
            entry.count  += 1
            buckets[bucketStart] = entry
        }

        // 4. Fill every bucket in the range (no gaps)
        guard let firstBucket = startOfBucket(start, granularity: granularity) else { return [] }
        var result: [TrendPoint] = []
        var cursor = firstBucket
        while cursor <= now {
            let entry = buckets[cursor] ?? (0, 0)
            result.append(TrendPoint(id: cursor, date: cursor, amount: entry.amount, count: entry.count))
            guard let next = advance(cursor, by: granularity) else { break }
            cursor = next
        }
        return result
    }

    private func startOfBucket(_ date: Date, granularity: TrendGranularity) -> Date? {
        switch granularity {
        case .day:   return calendar.startOfDay(for: date)
        case .week:  return calendar.dateInterval(of: .weekOfYear, for: date)?.start
        case .month: return calendar.dateInterval(of: .month, for: date)?.start
        case .year:  return calendar.dateInterval(of: .year, for: date)?.start
        }
    }

    private func advance(_ date: Date, by granularity: TrendGranularity) -> Date? {
        switch granularity {
        case .day:   return calendar.date(byAdding: .day,       value: 1, to: date)
        case .week:  return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .month: return calendar.date(byAdding: .month,     value: 1, to: date)
        case .year:  return calendar.date(byAdding: .year,      value: 1, to: date)
        }
    }
}

// MARK: - Trend View
struct BillTrendView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appCurrency) private var currency: AppCurrency
    @Query private var allBills: [Bill]

    @State private var scope: TrendScope
    @State private var granularity: TrendGranularity = .month
    @State private var selectedBillTitle: String?
    @State private var selectedCategory: ExpenseCategory?
    @State private var rangeMonths: Int = 12
    @State private var chartStyle: ChartStyle = .line
    @State private var showPaid: Bool = true
    @State private var showUnpaid: Bool = true

    enum ChartStyle: String, CaseIterable, Identifiable {
        case line = "Line"
        case bar  = "Bar"
        var id: String { rawValue }
        var icon: String { self == .line ? "chart.xyaxis.line" : "chart.bar.fill" }
    }

    init(initialBill: Bill? = nil, initialCategory: ExpenseCategory? = nil) {
        let billTitle = initialBill?.title
        let initialScope: TrendScope = {
            if initialBill != nil { return .bill }
            if initialCategory != nil { return .category }
            return .everything
        }()
        _scope = State(initialValue: initialScope)
        _selectedBillTitle = State(initialValue: billTitle)
        _selectedCategory = State(initialValue: initialCategory)
    }

    // MARK: - Derived data
    private var availableBillTitles: [String] {
        Array(Set(allBills.map { $0.title })).sorted()
    }

    private var availableCategories: [ExpenseCategory] {
        let used = Set(allBills.map { $0.category })
        return ExpenseCategory.allCases.filter { used.contains($0) }
    }

    private var sourceBills: [Bill] {
        var result = allBills
        if !showPaid   { result = result.filter { !$0.isPaid } }
        if !showUnpaid { result = result.filter { $0.isPaid } }
        return result
    }

    private var points: [TrendPoint] {
        TrendAnalytics(bills: sourceBills).points(
            scope: scope,
            billTitle: selectedBillTitle,
            category: selectedCategory,
            granularity: granularity,
            rangeMonths: rangeMonths
        )
    }

    private var totalAmount: Double { points.reduce(0) { $0 + $1.amount } }

    private var averageAmount: Double {
        let nonZero = points.filter { $0.amount > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return nonZero.reduce(0) { $0 + $1.amount } / Double(nonZero.count)
    }

    private var totalCount: Int { points.reduce(0) { $0 + $1.count } }
    private var peakPoint: TrendPoint? { points.max(by: { $0.amount < $1.amount }) }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    filterBar
                    if points.isEmpty || totalCount == 0 {
                        emptyState
                    } else {
                        kpiRow
                        chartCard
                        dataList
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 820, idealWidth: 920, minHeight: 640, idealHeight: 780)
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Bill Trend")
                    .font(.title2).fontWeight(.bold)
                Text(headerSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var headerSubtitle: String {
        switch scope {
        case .everything: return "All bills · last \(rangeMonths == 240 ? "24+" : "\(rangeMonths)") months"
        case .bill:       return selectedBillTitle ?? "Select a bill"
        case .category:   return selectedCategory?.rawValue ?? "Select a category"
        }
    }

    // MARK: - Filter Bar
    private var filterBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text("View")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $scope) {
                        ForEach(TrendScope.allCases) { s in
                            Label(s.rawValue, systemImage: s.icon).tag(s)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }

                Divider().frame(height: 22)

                HStack(spacing: 6) {
                    Text("Group by")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $granularity) {
                        ForEach(TrendGranularity.allCases) { g in
                            Text(g.rawValue).tag(g)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("Range")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $rangeMonths) {
                        Text("3M").tag(3)
                        Text("6M").tag(6)
                        Text("12M").tag(12)
                        Text("24M").tag(24)
                        Text("All").tag(240)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 80)
                }
            }

            HStack(spacing: 12) {
                if scope == .bill {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundStyle(.blue)
                        Picker("", selection: $selectedBillTitle) {
                            Text("Select a bill…").tag(String?.none)
                            ForEach(availableBillTitles, id: \.self) { title in
                                Text(title).tag(Optional(title))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                }

                if scope == .category {
                    HStack(spacing: 6) {
                        Image(systemName: "tag")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Picker("", selection: $selectedCategory) {
                            Text("Select a category…").tag(ExpenseCategory?.none)
                            ForEach(availableCategories) { c in
                                Label(c.rawValue, systemImage: c.iconName).tag(Optional(c))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                }

                Spacer()

                Toggle(isOn: $showPaid) {
                    Text("Paid").font(.system(size: 11))
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $showUnpaid) {
                    Text("Unpaid").font(.system(size: 11))
                }
                .toggleStyle(.checkbox)

                Divider().frame(height: 22)

                Picker("", selection: $chartStyle) {
                    ForEach(ChartStyle.allCases) { s in
                        Image(systemName: s.icon).tag(s)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 80)
            }
        }
        .padding(14)
        .background(RMDesign.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - KPI Row
    private var kpiRow: some View {
        HStack(spacing: 12) {
            TrendKPI(
                title: "Total",
                value: CurrencyFormatter.format(totalAmount, as: currency),
                icon: "banknote.fill",
                color: .blue
            )
            TrendKPI(
                title: "Average",
                value: CurrencyFormatter.format(averageAmount, as: currency),
                icon: "chart.line.uptrend.xyaxis",
                color: .green
            )
            TrendKPI(
                title: "Entries",
                value: "\(totalCount)",
                icon: "number.circle.fill",
                color: .purple
            )
            TrendKPI(
                title: "Peak",
                value: peakPoint.map { CurrencyFormatter.format($0.amount, as: currency) } ?? "—",
                subtitle: peakPoint.map { dateLabel($0.date) } ?? "",
                icon: "arrow.up.circle.fill",
                color: .orange
            )
        }
    }

    // MARK: - Chart Card
    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.blue.gradient)
                    .cornerRadius(7)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Amount over time")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Grouped by \(granularity.rawValue.lowercased())")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            chart
                .frame(height: 300)
        }
        .padding(16)
        .background(RMDesign.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var chart: some View {
        Chart {
            ForEach(points) { point in
                let yValue = CurrencyFormatter.convert(point.amount, to: currency)

                if chartStyle == .line {
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Amount", yValue)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.25), .blue.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Amount", yValue)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)

                    if point.amount > 0 {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Amount", yValue)
                        )
                        .foregroundStyle(.blue)
                        .symbolSize(40)
                    }
                } else {
                    BarMark(
                        x: .value("Date", point.date),
                        y: .value("Amount", yValue),
                        width: barWidth
                    )
                    .foregroundStyle(Color.blue.gradient)
                    .cornerRadius(4)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 8)) { value in
                AxisGridLine().foregroundStyle(.gray.opacity(0.15))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(axisDateLabel(date)).font(.system(size: 10))
                    }
                }
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
    }

    private var barWidth: MarkDimension {
        switch granularity {
        case .day:   return .fixed(6)
        case .week:  return .fixed(12)
        case .month: return .fixed(20)
        case .year:  return .fixed(30)
        }
    }

    // MARK: - Data List
    private var dataList: some View {
        let activePoints = points.filter { $0.count > 0 }.reversed()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.purple.gradient)
                    .cornerRadius(6)
                Text("Breakdown")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(activePoints.count) period\(activePoints.count == 1 ? "" : "s") with activity")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(activePoints)) { point in
                    HStack(spacing: 12) {
                        Text(dateLabel(point.date))
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 140, alignment: .leading)

                        Text("\(point.count) entr\(point.count == 1 ? "y" : "ies")")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)

                        GeometryReader { geo in
                            let maxAmount = points.map { $0.amount }.max() ?? 1
                            let fraction = maxAmount > 0 ? point.amount / maxAmount : 0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.blue.opacity(0.6))
                                .frame(width: max(2, geo.size.width * fraction), height: 6)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 16)

                        Text(CurrencyFormatter.format(point.amount, as: currency))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 130, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)

                    Divider().padding(.leading, 12)
                }
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.4))
            .cornerRadius(10)
        }
        .padding(16)
        .background(RMDesign.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: 4) {
                Text("No trend data")
                    .font(.system(size: 15, weight: .semibold))
                Text(emptyStateMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyStateMessage: String {
        switch scope {
        case .bill where selectedBillTitle == nil:
            return "Select a bill to view its trend over time."
        case .category where selectedCategory == nil:
            return "Select a category to view its spending trend."
        default:
            return "No bills in the selected range. Try widening the range or changing the filters."
        }
    }

    // MARK: - Helpers
    private func dateLabel(_ date: Date) -> String {
        switch granularity {
        case .day:   return date.formatted(.dateTime.month(.abbreviated).day().year())
        case .week:  return date.formatted(.dateTime.month(.abbreviated).day())
        case .month: return date.formatted(.dateTime.month(.wide).year())
        case .year:  return date.formatted(.dateTime.year())
        }
    }

    private func axisDateLabel(_ date: Date) -> String {
        switch granularity {
        case .day:   return date.formatted(.dateTime.month(.abbreviated).day())
        case .week:  return date.formatted(.dateTime.month(.abbreviated).day())
        case .month: return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        case .year:  return date.formatted(.dateTime.year())
        }
    }
}

// MARK: - KPI Card
private struct TrendKPI: View {
    let title: String
    let value: String
    var subtitle: String = ""
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 22, height: 22)
                    .background(color.opacity(0.12))
                    .cornerRadius(6)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
            }

            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RMDesign.cardBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
}