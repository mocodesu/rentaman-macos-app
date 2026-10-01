import SwiftUI
import SwiftData
import Charts

// MARK: - Income Stream
struct IncomeStream: Codable, Hashable, Identifiable {
    var id: String { "\(dayOfMonth)-\(amount)" }
    let dayOfMonth: Int
    let amount: Double        // stored in KSH
    var label: String
}

// MARK: - Cash Flow Analytics
struct CashFlowAnalytics {
    let bills: [Bill]
    let incomeStreams: [IncomeStream]
    private var calendar: Calendar { Calendar.current }

    struct DayPoint: Identifiable {
        let id: Int
        let day: Int
        let date: Date
        let income: Double
        let outflow: Double
        let balance: Double
        let balanceIfHeldBack: Double
    }

    struct Result {
        let points: [DayPoint]
        let totalIncome: Double
        let totalOutflow: Double
        let lowestBalance: DayPoint?
        let dangerDays: [DayPoint]
        let holdbackSuggestion: Double
        let holdbackNote: String
    }

    func simulate(referenceMonth: Date = Date()) -> Result {
        let cal = calendar
        guard let monthStart = cal.dateInterval(of: .month, for: referenceMonth)?.start,
              let monthEnd = cal.dateInterval(of: .month, for: referenceMonth)?.end else {
            return Result(points: [], totalIncome: 0, totalOutflow: 0,
                          lowestBalance: nil, dangerDays: [],
                          holdbackSuggestion: 0, holdbackNote: "")
        }

        let daysInMonth = cal.dateComponents([.day], from: monthStart, to: monthEnd).day ?? 30

        var billsByDay: [Int: [Bill]] = [:]
        for bill in bills {
            let d = effectiveDate(for: bill)
            guard d >= monthStart, d < monthEnd else { continue }
            let day = cal.component(.day, from: d)
            billsByDay[day, default: []].append(bill)
        }

        var incomeByDay: [Int: Double] = [:]
        for stream in incomeStreams {
            incomeByDay[stream.dayOfMonth, default: 0] += stream.amount
        }

        var points: [DayPoint] = []
        var running: Double = 0
        var totalIn: Double = 0
        var totalOut: Double = 0

        for day in 1...daysInMonth {
            let income = incomeByDay[day] ?? 0
            let outflow = (billsByDay[day] ?? []).reduce(0.0) { $0 + $1.amount }
            running += income - outflow
            totalIn += income
            totalOut += outflow

            guard let date = cal.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }

            points.append(DayPoint(
                id: day,
                day: day,
                date: date,
                income: income,
                outflow: outflow,
                balance: running,
                balanceIfHeldBack: 0
            ))
        }

        let lowest = points.min(by: { $0.balance < $1.balance })
        let danger = points.filter { $0.balance < 0 }

        let holdback: Double
        let note: String
        if let peakAfterPay = points.filter({ $0.income > 0 }).min(by: { $0.day < $1.day }),
           let low = lowest, low.balance < 0 {
            let shortfall = abs(low.balance)
            let safety = peakAfterPay.income * 0.05
            holdback = shortfall + safety
            note = "Hold back ~\(Int((holdback / max(peakAfterPay.income, 1)) * 100))% of your first payday so you never hit zero before the next one."
        } else if let low = lowest, low.balance >= 0 {
            holdback = 0
            note = "You're cash-flow positive this month. No holdback needed."
        } else {
            holdback = 0
            note = "Add income streams to see a recommendation."
        }

        let firstIncomeDay = incomeByDay.keys.sorted().first ?? 1
        let remainingHoldback = holdback
        var held = 0.0
        var points2: [DayPoint] = []
        var running2 = 0.0

        for p in points {
            var inc = p.income
            var extraOut = 0.0
            if p.day == firstIncomeDay && remainingHoldback > 0 {
                inc -= remainingHoldback
                held = remainingHoldback
            }
            let releaseStart = max(firstIncomeDay + 1, daysInMonth - 6)
            if p.day >= releaseStart && held > 0 {
                let releasePerDay = held / Double(max(1, daysInMonth - releaseStart + 1))
                extraOut = -releasePerDay
            }
            running2 += inc - p.outflow + (extraOut < 0 ? -extraOut : 0)
            points2.append(DayPoint(
                id: p.id,
                day: p.day,
                date: p.date,
                income: p.income,
                outflow: p.outflow,
                balance: p.balance,
                balanceIfHeldBack: running2
            ))
        }

        return Result(
            points: points2,
            totalIncome: totalIn,
            totalOutflow: totalOut,
            lowestBalance: lowest,
            dangerDays: danger,
            holdbackSuggestion: holdback,
            holdbackNote: note
        )
    }

    private func effectiveDate(for bill: Bill) -> Date {
        bill.isPaid ? (bill.paymentDate ?? bill.dueDate) : bill.dueDate
    }
}

// MARK: - Income Config (persisted)
@Observable
final class IncomeConfig {
    static let shared = IncomeConfig()
    private let key = "cashflow.incomeStreams"

    var streams: [IncomeStream] = []

    private init() {
        load()
        if streams.isEmpty {
            streams = [
                IncomeStream(dayOfMonth: 2, amount: 1100 * ExchangeRate.kshPerUsd, label: "Salary"),
                IncomeStream(dayOfMonth: 20, amount: 150 * ExchangeRate.kshPerUsd, label: "Top-up"),
            ]
            save()
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([IncomeStream].self, from: data) else { return }
        streams = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(streams) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func add(_ stream: IncomeStream) { streams.append(stream); save() }
    func remove(_ stream: IncomeStream) { streams.removeAll { $0.id == stream.id }; save() }
    func update(_ stream: IncomeStream) {
        if let i = streams.firstIndex(where: { $0.id == stream.id }) {
            streams[i] = stream
            save()
        }
    }
}

// MARK: - Day Group (collapsed consecutive identical days)
struct CashFlowDayGroup: Identifiable {
    let id: String
    let startDay: Int
    let endDay: Int
    let days: [CashFlowAnalytics.DayPoint]

    var isRange: Bool { endDay > startDay }
    var dayCount: Int { days.count }
    var balance: Double { days.first?.balance ?? 0 }
    var isDanger: Bool { balance < 0 }
    var totalIncome: Double { days.reduce(0) { $0 + $1.income } }
    var totalOutflow: Double { days.reduce(0) { $0 + $1.outflow } }

    var dayLabel: String {
        isRange ? "\(startDay)–\(endDay)" : "\(startDay)"
    }
}

// MARK: - View
struct CashFlowPlannerView: View {
    @Environment(\.appCurrency) private var currency: AppCurrency
    @Query(filter: #Predicate<Bill> { $0.isDeleted == false })
    private var allBills: [Bill]

    @State private var config = IncomeConfig.shared
    @State private var showIncomeEditor = false

    private var analytics: CashFlowAnalytics.Result {
        CashFlowAnalytics(bills: allBills, incomeStreams: config.streams).simulate()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if config.streams.isEmpty {
                emptyIncome
            } else {
                let result = analytics
                holdbackCard(result)
                balanceChart(result)
                dayByDayList(result)
            }
        }
        .sheet(isPresented: $showIncomeEditor) {
            IncomeEditorSheet(config: config, currency: currency)
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(RMDesign.accent)
                    .frame(width: 24, height: 24)
                    .background(RMDesign.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Cash Flow")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Daily balance through this month")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                showIncomeEditor = true
            } label: {
                Label("Income", systemImage: "banknote")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    // MARK: - Holdback
    private func holdbackCard(_ result: CashFlowAnalytics.Result) -> some View {
        let tint = result.holdbackSuggestion > 0 ? RMDesign.warning : RMDesign.success

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: result.holdbackSuggestion > 0 ? "shield.lefthalf.filled" : "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Holdback Recommendation")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(result.holdbackNote)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            if result.holdbackSuggestion > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(CurrencyFormatter.format(result.holdbackSuggestion, as: currency))
                        .font(.system(size: 28, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                    Text("to reserve on the 2nd")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                CashFlowStat(label: "Income",     value: CurrencyFormatter.format(result.totalIncome, as: currency),  color: RMDesign.success)
                CashFlowStat(label: "Bills",      value: CurrencyFormatter.format(result.totalOutflow, as: currency), color: RMDesign.danger)
                CashFlowStat(label: "Lowest day", value: result.lowestBalance.map { CurrencyFormatter.format($0.balance, as: currency) } ?? "—", color: (result.lowestBalance?.balance ?? 0) < 0 ? RMDesign.danger : RMDesign.accent)
                CashFlowStat(label: "Danger days", value: "\(result.dangerDays.count)", color: result.dangerDays.isEmpty ? RMDesign.success : RMDesign.warning)
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

    // MARK: - Chart
    private func balanceChart(_ result: CashFlowAnalytics.Result) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(RMDesign.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Daily Balance")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Your cash position through the month")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Chart {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(RMDesign.danger.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                ForEach(result.points) { p in
                    AreaMark(
                        x: .value("Day", p.day),
                        y: .value("Balance", CurrencyFormatter.convert(p.balance, to: currency))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [RMDesign.accent.opacity(0.20), RMDesign.accent.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Day", p.day),
                        y: .value("Balance", CurrencyFormatter.convert(p.balance, to: currency))
                    )
                    .foregroundStyle(RMDesign.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
                }

                ForEach(result.points) { p in
                    LineMark(
                        x: .value("Day", p.day),
                        y: .value("With Holdback", CurrencyFormatter.convert(p.balanceIfHeldBack, to: currency))
                    )
                    .foregroundStyle(RMDesign.warning)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 3]))
                    .interpolationMethod(.monotone)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 10)) { value in
                    AxisGridLine().foregroundStyle(RMDesign.dividerColor)
                    AxisValueLabel {
                        if let day = value.as(Int.self) {
                            Text("\(day)").font(.system(size: 10))
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
                            .font(.system(size: 10))
                        }
                    }
                }
            }
            .frame(height: 240)

            HStack(spacing: 16) {
                legend(color: RMDesign.accent,  label: "Current plan")
                legend(color: RMDesign.warning, label: "With holdback applied")
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(RMDesign.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(RMDesign.borderColor, lineWidth: 1)
        )
    }

    // MARK: - Day list (grouped)
    private func dayByDayList(_ result: CashFlowAnalytics.Result) -> some View {
        let groups = groupConsecutiveDays(result.points)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "list.number")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Day-by-Day")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Income and bills for each day")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(groups.count) segment\(groups.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    dayGroupRow(group)
                    if index < groups.count - 1 {
                        Divider().padding(.leading, 10)
                    }
                }
            }
            .background(RMDesign.fieldBackground.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
        }
        .padding(14)
        .background(RMDesign.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(RMDesign.borderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func dayGroupRow(_ group: CashFlowDayGroup) -> some View {
        HStack(spacing: 12) {
            // Day label (either single "5" or range "5–19")
            HStack(spacing: 4) {
                Text(group.dayLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .leading)

                if group.isRange {
                    Text("· \(group.dayCount)d")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .frame(width: 64, alignment: .leading)

            // Income
            if group.totalIncome > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(RMDesign.success)
                    Text("+\(CurrencyFormatter.format(group.totalIncome, as: currency))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(RMDesign.success)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(width: 130, alignment: .leading)
            } else {
                Color.clear.frame(width: 130, height: 1)
            }

            // Outflow
            if group.totalOutflow > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(RMDesign.danger)
                    Text("-\(CurrencyFormatter.format(group.totalOutflow, as: currency))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(RMDesign.danger)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(width: 130, alignment: .leading)
            } else {
                Color.clear.frame(width: 130, height: 1)
            }

            Spacer()

            HStack(spacing: 4) {
                if group.isDanger {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(RMDesign.danger)
                }
                Text(CurrencyFormatter.format(group.balance, as: currency))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(group.isDanger ? RMDesign.danger : .primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(group.isDanger ? RMDesign.danger.opacity(0.05) : Color.clear)
    }

    /// Collapse consecutive days that have the same balance and no activity.
    private func groupConsecutiveDays(_ points: [CashFlowAnalytics.DayPoint]) -> [CashFlowDayGroup] {
        var groups: [CashFlowDayGroup] = []
        var current: [CashFlowAnalytics.DayPoint] = []

        for point in points {
            if current.isEmpty {
                current.append(point)
                continue
            }
            let prev = current.last!
            let sameBalance = abs(point.balance - prev.balance) < 0.01
            let noActivity = point.income == 0 && point.outflow == 0
            if sameBalance && noActivity {
                current.append(point)
            } else {
                groups.append(makeGroup(current))
                current = [point]
            }
        }
        if !current.isEmpty {
            groups.append(makeGroup(current))
        }
        return groups
    }

    private func makeGroup(_ points: [CashFlowAnalytics.DayPoint]) -> CashFlowDayGroup {
        let start = points.first?.day ?? 0
        let end = points.last?.day ?? 0
        return CashFlowDayGroup(
            id: "\(start)-\(end)",
            startDay: start,
            endDay: end,
            days: points
        )
    }

    // MARK: - Empty
    private var emptyIncome: some View {
        VStack(spacing: 10) {
            Image(systemName: "banknote")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Add your income streams")
                .font(.system(size: 13, weight: .semibold))
            Text("Tell us when you get paid so we can plan around it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button {
                showIncomeEditor = true
            } label: {
                Label("Add Income", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(RMDesign.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(RMDesign.borderColor, lineWidth: 1)
        )
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Stat
private struct CashFlowStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.3)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RMDesign.fieldBackground.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
    }
}

// MARK: - Income Editor
struct IncomeEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let config: IncomeConfig
    let currency: AppCurrency

    @State private var streams: [IncomeStream] = []
    @State private var newDay: Int = 1
    @State private var newAmount: String = ""
    @State private var newLabel: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(RMDesign.success)
                Text("Income Streams")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("When do you get paid? Amounts are entered in \(currency.rawValue).")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    ForEach(streams) { stream in
                        HStack(spacing: 10) {
                            Text("Day \(stream.dayOfMonth)")
                                .font(.system(size: 12.5, weight: .semibold))
                                .frame(width: 60, alignment: .leading)
                            Text(stream.label)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(CurrencyFormatter.format(stream.amount, as: currency))
                                .font(.system(size: 12.5, weight: .semibold))
                                .monospacedDigit()
                            Button {
                                streams.removeAll { $0.id == stream.id }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(RMDesign.danger)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(10)
                        .background(RMDesign.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                                .stroke(RMDesign.borderColor, lineWidth: 1)
                        )
                    }

                    Divider().padding(.vertical, 2)

                    Text("Add a new stream")
                        .font(.system(size: 12, weight: .semibold))

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Day").font(.system(size: 10)).foregroundStyle(.secondary)
                            Picker("", selection: $newDay) {
                                ForEach(1...31, id: \.self) { d in Text("\(d)").tag(d) }
                            }
                            .labelsHidden()
                            .frame(width: 70)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Label").font(.system(size: 10)).foregroundStyle(.secondary)
                            TextField("Salary", text: $newLabel)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Amount (\(currency.rawValue))").font(.system(size: 10)).foregroundStyle(.secondary)
                            TextField("0.00", text: $newAmount)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                        Button {
                            addStream()
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(Double(newAmount) == nil || newLabel.isEmpty)
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    save()
                } label: {
                    Label("Save", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 620, height: 520)
        .background(RMDesign.pageBackground)
        .onAppear {
            streams = config.streams
        }
    }

    private func addStream() {
        guard let amount = Double(newAmount), amount > 0, !newLabel.isEmpty else { return }
        let ksh = CurrencyFormatter.toKsh(amount, from: currency)
        streams.append(IncomeStream(dayOfMonth: newDay, amount: ksh, label: newLabel))
        newAmount = ""
        newLabel = ""
    }

    private func save() {
        config.streams = streams
        config.save()
        dismiss()
    }
}