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
        let day: Int                 // 1...31
        let date: Date
        let income: Double           // income received this day
        let outflow: Double          // bills due this day
        let balance: Double          // running balance at end of day
        let balanceIfHeldBack: Double // balance with holdback applied
    }

    struct Result {
        let points: [DayPoint]
        let totalIncome: Double
        let totalOutflow: Double
        let lowestBalance: DayPoint?
        let dangerDays: [DayPoint]      // days where balance < 0
        let holdbackSuggestion: Double  // how much to reserve from the 2nd
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

        // 1. Group bills by day-of-month (using effective date).
        var billsByDay: [Int: [Bill]] = [:]
        for bill in bills {
            let d = effectiveDate(for: bill)
            // Only bills in this reference month.
            guard d >= monthStart, d < monthEnd else { continue }
            let day = cal.component(.day, from: d)
            billsByDay[day, default: []].append(bill)
        }

        // 2. Group income by day-of-month.
        var incomeByDay: [Int: Double] = [:]
        for stream in incomeStreams {
            incomeByDay[stream.dayOfMonth, default: 0] += stream.amount
        }

        // 3. Walk day by day, accumulate balance.
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
                balanceIfHeldBack: 0   // filled in later
            ))
        }

        // 4. Find lowest balance and danger days.
        let lowest = points.min(by: { $0.balance < $1.balance })
        let danger = points.filter { $0.balance < 0 }

        // 5. Compute holdback suggestion.
        //    Logic: the gap between the biggest income (typically the 2nd)
        //    and the next income (typically the 20th) is where the user
        //    starves. Reserve enough to keep the balance ≥ 0 during that gap.
        let holdback: Double
        let note: String
        if let peakAfterPay = points.filter({ $0.income > 0 }).min(by: { $0.day < $1.day }),
           let low = lowest, low.balance < 0 {
            let shortfall = abs(low.balance)
            // Also account for a small safety margin (5% of income).
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

        // 6. Second pass — simulate with the holdback applied to the first payday.
        //    On the biggest payday, we withhold `holdback` and redistribute
        //    it evenly across the second half of the month (after the last income).
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
            // Redistribute the held amount across the last week of the month.
            let releaseStart = max(firstIncomeDay + 1, daysInMonth - 6)
            if p.day >= releaseStart && held > 0 {
                let releasePerDay = held / Double(max(1, daysInMonth - releaseStart + 1))
                extraOut = -releasePerDay   // effectively increases available cash
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
            // Sensible defaults: 1,100 USD on the 2nd, 150 USD on the 20th.
            // Stored in KSH internally.
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
            .padding(24)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(RMDesign.pageBackground)
        .sheet(isPresented: $showIncomeEditor) {
            IncomeEditorSheet(config: config, currency: currency)
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(alignment: .center) {
            RMPageHeader(
                icon: "calendar.badge.clock",
                title: "Cash Flow",
                subtitle: "Daily balance through this month"
            )
            Spacer()
            Button {
                showIncomeEditor = true
            } label: {
                Label("Income", systemImage: "banknote")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Holdback
    private func holdbackCard(_ result: CashFlowAnalytics.Result) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: result.holdbackSuggestion > 0 ? "shield.lefthalf.filled" : "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background((result.holdbackSuggestion > 0 ? Color.orange : Color.green).gradient)
                    .cornerRadius(9)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Holdback Recommendation")
                        .font(.system(size: 14, weight: .semibold))
                    Text(result.holdbackNote)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if result.holdbackSuggestion > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(CurrencyFormatter.format(result.holdbackSuggestion, as: currency))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                    Text("to reserve on the 2nd")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            // Small summary strip
            HStack(spacing: 12) {
                CashFlowStat(label: "Income",     value: CurrencyFormatter.format(result.totalIncome, as: currency),  color: .green)
                CashFlowStat(label: "Bills",      value: CurrencyFormatter.format(result.totalOutflow, as: currency), color: .red)
                CashFlowStat(label: "Lowest day", value: result.lowestBalance.map { CurrencyFormatter.format($0.balance, as: currency) } ?? "—", color: (result.lowestBalance?.balance ?? 0) < 0 ? .red : .blue)
                CashFlowStat(label: "Danger days", value: "\(result.dangerDays.count)", color: result.dangerDays.isEmpty ? .green : .orange)
            }
        }
        .padding(16)
        .background(RMDesign.cardBackground)
        .cornerRadius(RMDesign.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(Color.orange.opacity(result.holdbackSuggestion > 0 ? 0.25 : 0.1), lineWidth: 1)
        )
    }

    // MARK: - Chart
    private func balanceChart(_ result: CashFlowAnalytics.Result) -> some View {
        RMContentCard(
            title: "Daily Balance",
            icon: "chart.xyaxis.line",
            iconColor: .blue,
            subtitle: "Your cash position through the month"
        ) {
            Chart {
                // Zero line
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.red.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                // Current balance
                ForEach(result.points) { p in
                    AreaMark(
                        x: .value("Day", p.day),
                        y: .value("Balance", CurrencyFormatter.convert(p.balance, to: currency))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.25), Color.blue.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Day", p.day),
                        y: .value("Balance", CurrencyFormatter.convert(p.balance, to: currency))
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
                }

                // Balance WITH holdback applied
                ForEach(result.points) { p in
                    LineMark(
                        x: .value("Day", p.day),
                        y: .value("With Holdback", CurrencyFormatter.convert(p.balanceIfHeldBack, to: currency))
                    )
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5,lineCap: .round, dash: [4, 3]))
                    .interpolationMethod(.monotone)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 10)) { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.1))
                    AxisValueLabel {
                        if let day = value.as(Int.self) {
                            Text("\(day)").font(.system(size: 10))
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
                            .font(.system(size: 10))
                        }
                    }
                }
            }
            .frame(height: 260)

            HStack(spacing: 16) {
                legend(color: .blue,  label: "Current plan")
                legend(color: .orange, label: "With holdback applied")
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Day list
    private func dayByDayList(_ result: CashFlowAnalytics.Result) -> some View {
        RMContentCard(
            title: "Day-by-Day",
            icon: "list.number",
            iconColor: .purple,
            subtitle: "Income and bills for each day"
        ) {
            VStack(spacing: 0) {
                ForEach(result.points) { p in
                    let isDanger = p.balance < 0
                    HStack(spacing: 12) {
                        Text("\(p.day)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 26, alignment: .leading)

                        if p.income > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.green)
                                Text("+\(CurrencyFormatter.format(p.income, as: currency))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.green)
                                    .monospacedDigit()
                            }
                            .frame(width: 130, alignment: .leading)
                        } else {
                            Color.clear.frame(width: 130, height: 1)
                        }

                        if p.outflow > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red)
                                Text("-\(CurrencyFormatter.format(p.outflow, as: currency))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.red)
                                    .monospacedDigit()
                            }
                            .frame(width: 130, alignment: .leading)
                        } else {
                            Color.clear.frame(width: 130, height: 1)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            if isDanger {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.red)
                            }
                            Text(CurrencyFormatter.format(p.balance, as: currency))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(isDanger ? .red : .primary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(isDanger ? Color.red.opacity(0.06) : Color.clear)

                    if p.day < result.points.count {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.4))
            .cornerRadius(10)
        }
    }

    // MARK: - Empty
    private var emptyIncome: some View {
        VStack(spacing: 12) {
            Image(systemName: "banknote")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Add your income streams")
                .font(.system(size: 14, weight: .semibold))
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
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.3)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(NSColor.textBackgroundColor).opacity(0.4))
        .cornerRadius(8)
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
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("Income Streams")
                    .font(.title2).fontWeight(.bold)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("When do you get paid? Amounts are entered in \(currency.rawValue).")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    ForEach(streams) { stream in
                        HStack(spacing: 12) {
                            Text("Day \(stream.dayOfMonth)")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 60, alignment: .leading)
                            Text(stream.label)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(CurrencyFormatter.format(stream.amount, as: currency))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Button {
                                streams.removeAll { $0.id == stream.id }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                    }

                    Divider().padding(.vertical, 4)

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
                .padding(20)
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
            .padding(20)
        }
        .frame(width: 620, height: 520)
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
