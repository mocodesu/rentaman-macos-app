import SwiftUI
import SwiftData
import Charts

// MARK: - Trend Direction
enum BillTrendDirection {
    case rising, stable, falling

    var icon: String {
        switch self {
        case .rising:  return "arrow.up.right"
        case .stable:  return "arrow.right"
        case .falling: return "arrow.down.right"
        }
    }

    var label: String {
        switch self {
        case .rising:  return "Rising"
        case .stable:  return "Stable"
        case .falling: return "Falling"
        }
    }

    var color: Color {
        switch self {
        case .rising:  return .red
        case .stable:  return .secondary
        case .falling: return .green
        }
    }
}

// MARK: - Analytics
struct BillImpactAnalytics {
    let bills: [Bill]
    let windowMonths: Int
    let limits: [String: Double]
    private var calendar: Calendar { Calendar.current }

    struct Item: Identifiable {
        let id: String
        let title: String
        let category: ExpenseCategory
        let monthlyAverage: Double
        let peak: Double
        let totalSpent: Double
        let occurrences: Int
        let isRecurring: Bool
        let trendPercent: Double
        let trend: BillTrendDirection
        let limit: Double?
        let advice: [Advice]
        let share: Double                 // 0...1 of total monthly spend
    }

    struct Advice: Identifiable {
        let id: String
        let severity: Severity
        let text: String

        enum Severity {
            case critical, warning, tip, good

            var icon: String {
                switch self {
                case .critical: return "exclamationmark.octagon.fill"
                case .warning:  return "exclamationmark.triangle.fill"
                case .tip:      return "lightbulb.fill"
                case .good:     return "checkmark.seal.fill"
                }
            }
            var color: Color {
                switch self {
                case .critical: return .red
                case .warning:  return .orange
                case .tip:      return .blue
                case .good:     return .green
                }
            }
        }
    }

    // MARK: - Main computation
    func analyze() -> (items: [Item], totalMonthly: Double) {
        let now = Date()
        guard let start = calendar.date(byAdding: .month, value: -windowMonths, to: now) else {
            return ([], 0)
        }

        // Filter to effective-date range
        let inRange = bills.filter {
            let d = effectiveDate(for: $0)
            return d >= start && d <= now
        }
        guard !inRange.isEmpty else { return ([], 0) }

        // Determine active months (any bill in that calendar month)
        var activeMonths: Set<String> = []
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        for bill in inRange {
            activeMonths.insert(fmt.string(from: effectiveDate(for: bill)))
        }
        let activeMonthCount = max(activeMonths.count, 1)

        // Group by lowercased title
        let grouped = Dictionary(grouping: inRange) { $0.title.lowercased() }

        var raw: [Item] = []
        for (key, group) in grouped {
            guard let first = group.first else { continue }
            let total = group.reduce(0.0) { $0 + $1.amount }
            let peak = group.map { $0.amount }.max() ?? 0
            let monthly = total / Double(activeMonthCount)
            let recurring = group.allSatisfy { $0.isRecurring }

            // Trend: last 3 months vs prior 3 months
            let (trendPct, direction) = computeTrend(for: group, now: now)

            let limit = limits[key]

            raw.append(Item(
                id: key,
                title: first.title,
                category: first.category,
                monthlyAverage: monthly,
                peak: peak,
                totalSpent: total,
                occurrences: group.count,
                isRecurring: recurring,
                trendPercent: trendPct,
                trend: direction,
                limit: limit,
                advice: [],       // filled in below
                share: 0          // filled in below
            ))
        }

        let grandTotal = raw.reduce(0.0) { $0 + $1.monthlyAverage }
        raw = raw.map { item in
            var copy = item
            let share = grandTotal > 0 ? item.monthlyAverage / grandTotal : 0
            let advice = generateAdvice(for: item, allItems: raw)
            copy = Item(
                id: item.id, title: item.title, category: item.category,
                monthlyAverage: item.monthlyAverage, peak: item.peak,
                totalSpent: item.totalSpent, occurrences: item.occurrences,
                isRecurring: item.isRecurring, trendPercent: item.trendPercent,
                trend: item.trend, limit: item.limit,
                advice: advice, share: share
            )
            return copy
        }

        // Sort by monthly cost descending
        return (raw.sorted { $0.monthlyAverage > $1.monthlyAverage }, grandTotal)
    }

    // MARK: - Trend
    private func computeTrend(for group: [Bill], now: Date) -> (Double, BillTrendDirection) {
        guard let sixAgo = calendar.date(byAdding: .month, value: -6, to: now),
              let threeAgo = calendar.date(byAdding: .month, value: -3, to: now)
        else { return (0, .stable) }

        let recent = group.filter {
            let d = effectiveDate(for: $0)
            return d >= threeAgo && d <= now
        }
        let prior = group.filter {
            let d = effectiveDate(for: $0)
            return d >= sixAgo && d < threeAgo
        }

        // Need at least 1 bill on each side to compute a meaningful trend.
        guard !recent.isEmpty, !prior.isEmpty else { return (0, .stable) }

        let recentAvg = recent.reduce(0.0) { $0 + $1.amount } / Double(recent.count)
        let priorAvg  = prior.reduce(0.0) { $0 + $1.amount } / Double(prior.count)
        guard priorAvg > 0 else { return (0, .stable) }

        let pct = ((recentAvg - priorAvg) / priorAvg) * 100

        let dir: BillTrendDirection
        if pct > 8       { dir = .rising }
        else if pct < -8 { dir = .falling }
        else             { dir = .stable }

        return (pct, dir)
    }

    // MARK: - Advice engine
    private func generateAdvice(for item: Item, allItems: [Item]) -> [Advice] {
        var advice: [Advice] = []

        // 1. Limit status
        if let limit = item.limit {
            if item.peak > limit * 1.10 {
                let over = item.peak - limit
                advice.append(Advice(
                    id: "limit-critical",
                    severity: .critical,
                    text: "Peak hit \(CurrencyFormatter.format(item.peak, as: .ksh)) — \(CurrencyFormatter.format(over, as: .ksh)) over your \(CurrencyFormatter.format(limit, as: .ksh)) limit. Renegotiate or cut."
                ))
            } else if item.peak > limit {
                advice.append(Advice(
                    id: "limit-warning",
                    severity: .warning,
                    text: "Went over your \(CurrencyFormatter.format(limit, as: .ksh)) limit by \(CurrencyFormatter.format(item.peak - limit, as: .ksh)). Keep an eye on it."
                ))
            } else {
                let headroom = limit - item.peak
                advice.append(Advice(
                    id: "limit-good",
                    severity: .good,
                    text: "Within your limit — \(CurrencyFormatter.format(headroom, as: .ksh)) headroom under \(CurrencyFormatter.format(limit, as: .ksh))."
                ))
            }
        } else if item.monthlyAverage > 3_000 {
            advice.append(Advice(
                id: "no-limit",
                severity: .tip,
                text: "No limit set. This bill costs \(CurrencyFormatter.format(item.monthlyAverage, as: .ksh))/month — consider capping it."
            ))
        }

        // 2. Trend
        if item.trend == .rising && abs(item.trendPercent) > 12 {
            advice.append(Advice(
                id: "trend-rising",
                severity: .warning,
                text: "Up \(Int(item.trendPercent))% vs the previous 3 months. Investigate what changed."
            ))
        } else if item.trend == .falling && abs(item.trendPercent) > 12 {
            advice.append(Advice(
                id: "trend-falling",
                severity: .good,
                text: "Down \(abs(Int(item.trendPercent)))% vs the previous 3 months. Whatever you changed, keep doing it."
            ))
        }

        // 3. Share of total spend
        if item.share > 0.30 {
            advice.append(Advice(
                id: "share-dominant",
                severity: .warning,
                text: "This single bill is \(Int(item.share * 100))% of your monthly spending. Any reduction here has the biggest impact."
            ))
        }

        // 4. Same-category siblings
        let siblings = allItems.filter {
            $0.category == item.category && $0.id != item.id && $0.monthlyAverage > 500
        }
        if siblings.count >= 2 {
            let names = siblings.prefix(3).map { $0.title }.joined(separator: ", ")
            advice.append(Advice(
                id: "category-cluster",
                severity: .tip,
                text: "You have \(siblings.count + 1) bills in \(item.category.rawValue) (\(names)). Can any be consolidated?"
            ))
        }

        // 5. Recurring + stable = candidate to pre-pay / lock in
        if item.isRecurring && item.trend == .stable && item.occurrences >= 6 {
            advice.append(Advice(
                id: "stable-recurring",
                severity: .tip,
                text: "Stable recurring cost. Ask the vendor for an annual or bulk discount."
            ))
        }

        // 6. Non-recurring + high = shop around
        if !item.isRecurring && item.monthlyAverage > 5_000 {
            advice.append(Advice(
                id: "variable-shop",
                severity: .tip,
                text: "Variable, high-cost bill. Try comparing 2–3 alternatives — potential savings are meaningful."
            ))
        }

        return advice
    }

    private func effectiveDate(for bill: Bill) -> Date {
        bill.isPaid ? (bill.paymentDate ?? bill.dueDate) : bill.dueDate
    }
}

// MARK: - Main View
struct BillImpactView: View {
    @Environment(\.appCurrency) private var currency: AppCurrency
    @Environment(\.dismiss) private var dismiss
    @Query private var allBills: [Bill]

    @State private var window: ImpactWindow = .twelve
    @State private var selectedCategory: ExpenseCategory? = nil
    @State private var limitEditorTarget: String? = nil

    enum ImpactWindow: Int, CaseIterable, Identifiable {
        case three = 3, six = 6, twelve = 12
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .three:  return "3M"
            case .six:    return "6M"
            case .twelve: return "12M"
            }
        }
    }

    private var analysis: (items: [BillImpactAnalytics.Item], totalMonthly: Double) {
        let a = BillImpactAnalytics(
            bills: allBills,
            windowMonths: window.rawValue,
            limits: BillLimits.shared.limits
        )
        let result = a.analyze()
        if let cat = selectedCategory {
            return (result.items.filter { $0.category == cat }, result.totalMonthly)
        }
        return result
    }

    private var availableCategories: [ExpenseCategory] {
        let used = Set(allBills.map { $0.category })
        return ExpenseCategory.allCases.filter { used.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    filterBar

                    let result = analysis
                    if result.items.isEmpty {
                        emptyState
                    } else {
                        summaryPanel(result)
                        if let top = result.items.first {
                            topBurnerCard(top, total: result.totalMonthly)
                        }
                        actionPanel(result)
                        listHeader
                        billList(result)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 860, idealWidth: 960, minHeight: 640, idealHeight: 800)
        .sheet(item: Binding(
            get: { limitEditorTarget.map { LimitTarget(title: $0) } },
            set: { limitEditorTarget = $0?.title }
        )) { target in
            BillLimitEditor(
                title: target.title,
                currentLimit: BillLimits.shared.limit(for: target.title),
                currency: currency,
                onSave: { newLimit in
                    BillLimits.shared.setLimit(newLimit, for: target.title)
                    limitEditorTarget = nil
                },
                onCancel: { limitEditorTarget = nil }
            )
        }
    }

    struct LimitTarget: Identifiable {
        let title: String
        var id: String { title }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bill Impact")
                    .font(.title2).fontWeight(.bold)
                Text("What's eating your money — and what to do about it")
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

    // MARK: - Filter bar
    private var filterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("Window")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("", selection: $window) {
                    ForEach(ImpactWindow.allCases) { w in
                        Text(w.label).tag(w)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            HStack(spacing: 6) {
                Text("Category")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedCategory) {
                    Text("All").tag(ExpenseCategory?.none)
                    ForEach(availableCategories) { c in
                        Label(c.rawValue, systemImage: c.iconName).tag(Optional(c))
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }

            Spacer()
        }
    }

    // MARK: - Summary
    private func summaryPanel(_ r: (items: [BillImpactAnalytics.Item], totalMonthly: Double)) -> some View {
        let overLimit = r.items.filter { item in
            guard let limit = item.limit else { return false }
            return item.peak > limit
        }.count
        let rising = r.items.filter { $0.trend == .rising }.count

        return HStack(spacing: 12) {
            ImpactStat(
                icon: "banknote.fill", color: .blue,
                label: "Monthly total",
                value: CurrencyFormatter.format(r.totalMonthly, as: currency)
            )
            ImpactStat(
                icon: "list.number", color: .purple,
                label: "Distinct bills",
                value: "\(r.items.count)"
            )
            ImpactStat(
                icon: overLimit > 0 ? "exclamationmark.octagon.fill" : "checkmark.seal.fill",
                color: overLimit > 0 ? .red : .green,
                label: "Over limit",
                value: overLimit > 0 ? "\(overLimit) bill\(overLimit == 1 ? "" : "s")" : "None"
            )
            ImpactStat(
                icon: "arrow.up.right", color: rising > 0 ? .orange : .green,
                label: "Rising trend",
                value: rising > 0 ? "\(rising)" : "None"
            )
        }
    }

    // MARK: - Top burner
    private func topBurnerCard(_ item: BillImpactAnalytics.Item, total: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.orange.gradient)
                    .cornerRadius(7)
                Text("Top Burner")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(item.share * 100))% of monthly spend")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(6)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: item.category.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.category.color)
                Text(item.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Text(CurrencyFormatter.format(item.monthlyAverage, as: currency))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("/mo")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let first = item.advice.first {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: first.severity.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(first.severity.color)
                    Text(first.text)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(first.severity.color.opacity(0.08))
                .cornerRadius(8)
            }
        }
        .padding(16)
        .background(RMDesign.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Action panel
    private func actionPanel(_ r: (items: [BillImpactAnalytics.Item], totalMonthly: Double)) -> some View {
        // Collect all critical & warning advice, cap to 4
        var actions: [(String, BillImpactAnalytics.Advice)] = []
        for item in r.items {
            for adv in item.advice where adv.severity == .critical || adv.severity == .warning {
                actions.append((item.title, adv))
            }
            if actions.count >= 4 { break }
        }
        guard !actions.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.red.gradient)
                        .cornerRadius(7)
                    Text("What to do")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(actions.count) action\(actions.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 6) {
                    ForEach(actions, id: \.1.id) { title, adv in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: adv.severity.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(adv.severity.color)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text(adv.text)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(adv.severity.color.opacity(0.06))
                        .cornerRadius(8)
                    }
                }
            }
            .padding(16)
            .background(RMDesign.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.08), lineWidth: 1)
            )
        )
    }

    // MARK: - List header
    private var listHeader: some View {
        HStack {
            Text("All Bills Ranked by Cost")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Text("Tap a bill to set a limit")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - List
    private func billList(_ r: (items: [BillImpactAnalytics.Item], totalMonthly: Double)) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(r.items.enumerated()), id: \.element.id) { idx, item in
                BillImpactRow(
                    rank: idx + 1,
                    item: item,
                    currency: currency,
                    onTapLimit: { limitEditorTarget = item.title }
                )
            }
        }
    }

    // MARK: - Empty
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Not enough data")
                .font(.system(size: 14, weight: .semibold))
            Text("Add bills to see which ones are eating your budget.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(60)
    }
}

// MARK: - Row
private struct BillImpactRow: View {
    let rank: Int
    let item: BillImpactAnalytics.Item
    let currency: AppCurrency
    let onTapLimit: () -> Void

    @State private var isHovered = false

    private var isOverLimit: Bool {
        guard let limit = item.limit else { return false }
        return item.peak > limit
    }

    private var limitProgress: Double {
        guard let limit = item.limit, limit > 0 else { return 0 }
        return min(item.peak / limit, 1.4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: rank, title, amount, trend
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Image(systemName: item.category.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.category.color)
                    .frame(width: 26, height: 26)
                    .background(item.category.color.opacity(0.12))
                    .cornerRadius(7)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if isOverLimit {
                            Text("OVER LIMIT")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.red.gradient)
                                .cornerRadius(4)
                        }
                    }
                    Text("\(item.occurrences) bills · \(Int(item.share * 100))% of spend")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Trend badge
                HStack(spacing: 3) {
                    Image(systemName: item.trend.icon)
                        .font(.system(size: 9, weight: .bold))
                    Text(item.trend.label)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(item.trend.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(item.trend.color.opacity(0.1))
                .cornerRadius(5)

                // Amount
                VStack(alignment: .trailing, spacing: 1) {
                    Text(CurrencyFormatter.format(item.monthlyAverage, as: currency))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("/ month")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 120, alignment: .trailing)
            }

            // Limit bar
            HStack(spacing: 8) {
                Button(action: onTapLimit) {
                    HStack(spacing: 4) {
                        Image(systemName: item.limit != nil ? "pencil.circle.fill" : "plus.circle")
                            .font(.system(size: 10, weight: .semibold))
                        Text(item.limit != nil
                             ? "Limit \(CurrencyFormatter.format(item.limit!, as: currency))"
                             : "Set limit")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(item.limit != nil ? (isOverLimit ? .red : .blue) : .blue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        (item.limit != nil ? (isOverLimit ? Color.red : Color.blue) : Color.blue)
                            .opacity(0.1)
                    )
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)

                if item.limit != nil {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gray.opacity(0.15))
                                .frame(height: 5)
                            Capsule()
                                .fill(isOverLimit ? Color.red.gradient : Color.blue.gradient)
                                .frame(width: geo.size.width * limitProgress, height: 5)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 10)

                    Text("Peak \(CurrencyFormatter.format(item.peak, as: currency))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize()
                } else {
                    Spacer()
                }
            }

            // Advice (first 2)
            if !item.advice.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.advice.prefix(2)) { adv in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: adv.severity.icon)
                                .font(.system(size: 9))
                                .foregroundStyle(adv.severity.color)
                                .frame(width: 12)
                            Text(adv.text)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(isHovered ? Color.blue.opacity(0.04) : RMDesign.cardBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isOverLimit ? Color.red.opacity(0.3) : Color.gray.opacity(0.08),
                        lineWidth: isOverLimit ? 1.2 : 1)
        )
        .onHover { hover in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hover }
        }
    }
}

// MARK: - Stat pill
private struct ImpactStat: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
            }
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RMDesign.cardBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Limit editor
private struct BillLimitEditor: View {
    let title: String
    let currentLimit: Double?
    let currency: AppCurrency
    let onSave: (Double?) -> Void
    let onCancel: () -> Void

    @State private var amountText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gauge.medium")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Set Spending Limit")
                    .font(.title3).fontWeight(.bold)
                Spacer()
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Maximum amount (\(currency.rawValue))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(currency.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amountText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .onChange(of: amountText) { _, newValue in
                                let filtered = newValue.filter { "0123456789.".contains($0) }
                                if filtered != newValue { amountText = filtered }
                            }
                    }
                    .padding(10)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }

                Text("Applies to every bill titled \"\(title)\" — past, present, and future.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            Divider()

            HStack {
                if currentLimit != nil {
                    Button("Remove Limit", role: .destructive) {
                        onSave(nil)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    if let v = Double(amountText), v > 0 {
                        let ksh = CurrencyFormatter.toKsh(v, from: currency)
                        onSave(ksh)
                    }
                } label: {
                    Label("Save", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(Double(amountText) == nil)
            }
            .padding(20)
        }
        .frame(width: 440)
        .onAppear {
            if let current = currentLimit {
                let display = CurrencyFormatter.convert(current, to: currency)
                amountText = String(format: "%.2f", display)
            }
        }
    }
}