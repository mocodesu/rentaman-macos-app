import Foundation
import SwiftUI

// MARK: - Anomaly
struct Anomaly: Identifiable {
    let id: String
    let bill: Bill
    let kind: Kind

    enum Kind {
        case overLimit(limit: Double, overBy: Double)
        case categoryOutlier(average: Double, ratio: Double)

        var isOverLimit: Bool {
            if case .overLimit = self { return true }
            return false
        }
    }
}

// MARK: - Dashboard Analytics Engine
struct DashboardAnalytics {
    let bills: [Bill]
    let properties: [Property]

    private var calendar: Calendar { Calendar.current }
    private var now: Date { Date() }

    // MARK: - KPI 1: Unpaid Bills
    var unpaidBills: [Bill] {
        bills
            .filter { !$0.isPaid }
            .sorted { $0.dueDate < $1.dueDate }
    }

    var totalUnpaidAmount: Double {
        let total = unpaidBills.reduce(0.0) { $0 + $1.amount }
        return total.isFinite ? total : 0
    }

    // MARK: - KPI 2: Upcoming (Today + next 6 days = 7-day window)
    var upcomingBills: [Bill] {
        let startOfToday = calendar.startOfDay(for: now)
        guard let endDate = calendar.date(byAdding: .day, value: 7, to: startOfToday) else {
            return []
        }
        return unpaidBills.filter { bill in
            let due = calendar.startOfDay(for: bill.dueDate)
            return due >= startOfToday && due < endDate
        }
        .sorted { $0.dueDate < $1.dueDate }
    }

    var overdueBills: [Bill] {
        let startOfToday = calendar.startOfDay(for: now)
        return unpaidBills.filter { bill in
            calendar.startOfDay(for: bill.dueDate) < startOfToday
        }
        .sorted { $0.dueDate < $1.dueDate }
    }

    // MARK: - KPI 3: Spent This Month (paid) + Expected (unpaid)

    /// Amount actually PAID this month (attributed to `paymentDate`).
    /// Returns 0 at the start of a new month until the first bill is paid —
    /// never falls back to a previous month.
    var totalPaidThisMonth: Double {
        let currentMonth = calendar.component(.month, from: now)
        let currentYear  = calendar.component(.year, from: now)

        let total = bills
            .filter { bill in
                guard bill.isPaid else { return false }
                let d = bill.paymentDate ?? bill.dueDate
                return isSameMonth(d, month: currentMonth, year: currentYear)
            }
            .reduce(0.0) { $0 + $1.amount }

        return total.isFinite ? total : 0
    }

    /// Amount still expected this month — unpaid bills whose due date
    /// lands in the current month. This is what remains to be paid.
    var totalExpectedThisMonth: Double {
        let currentMonth = calendar.component(.month, from: now)
        let currentYear  = calendar.component(.year, from: now)

        let total = bills
            .filter { bill in
                guard !bill.isPaid else { return false }
                return isSameMonth(bill.dueDate, month: currentMonth, year: currentYear)
            }
            .reduce(0.0) { $0 + $1.amount }

        return total.isFinite ? total : 0
    }

    /// Total monthly commitment (paid + expected).
    /// Used for budget progress and chart labels. Never falls back to a
    /// previous month — always reflects the current calendar month only.
    var totalSpentThisMonth: Double {
        totalPaidThisMonth + totalExpectedThisMonth
    }

    /// Subtitle for the "Spent This Month" KPI. Shows the expected
    /// amount when nothing has been paid yet this month.
    func spentThisMonthLabel(currency: AppCurrency) -> String {
        let paid     = totalPaidThisMonth
        let expected = totalExpectedThisMonth
        let monthName = now.formatted(.dateTime.month(.wide).year())

        if paid == 0 && expected == 0 {
            return "No activity this month"
        }
        if paid == 0 {
            return "Expected: \(CurrencyFormatter.format(expected, as: currency))"
        }
        if expected == 0 {
            return "\(monthName) · All paid"
        }
        return "Expected: \(CurrencyFormatter.format(expected, as: currency)) remaining"
    }

    private func isSameMonth(_ date: Date, month: Int, year: Int) -> Bool {
        calendar.component(.month, from: date) == month &&
        calendar.component(.year, from: date) == year
    }

    // MARK: - KPI 4: Anomalies
    /// Combined anomaly detection:
    ///   1. **Over limit** — bills whose amount exceeds the user-set
    ///      `BillLimits` for that title, within the last 90 days.
    ///   2. **Category outlier** — bills in the last 90 days that are
    ///      >1.5× the average of the same category over the preceding
    ///      6 months.
    ///
    /// A bill that qualifies for both is reported once as an over-limit
    /// anomaly (user-set thresholds take precedence over statistical ones).
    var anomalyReports: [Anomaly] {
        guard let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: now),
              let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) else {
            return []
        }

        var reports: [Anomaly] = []
        var flaggedIds = Set<String>()

        // ── 1. Over-limit bills ──
        for bill in bills where bill.dueDate >= ninetyDaysAgo {
            guard let limit = BillLimits.shared.limit(for: bill.title) else { continue }
            guard bill.amount > limit else { continue }
            let overBy = bill.amount - limit
            reports.append(Anomaly(
                id: "\(bill.id)-limit",
                bill: bill,
                kind: .overLimit(limit: limit, overBy: overBy)
            ))
            flaggedIds.insert(bill.id)
        }

        // ── 2. Category outliers ──
        let grouped = Dictionary(grouping: bills, by: { $0.categoryRawValue })

        for (_, categoryBills) in grouped {
            let historical = categoryBills.filter {
                $0.dueDate >= sixMonthsAgo && $0.dueDate < ninetyDaysAgo
            }
            guard historical.count >= 2 else { continue }

            let sum = historical.reduce(0.0) { $0 + $1.amount }
            let average = sum / Double(historical.count)
            guard average.isFinite, average > 0 else { continue }

            for bill in categoryBills where bill.dueDate >= ninetyDaysAgo {
                guard !flaggedIds.contains(bill.id) else { continue }
                guard bill.amount > average * 1.5 else { continue }
                let ratio = bill.amount / average
                reports.append(Anomaly(
                    id: "\(bill.id)-outlier",
                    bill: bill,
                    kind: .categoryOutlier(average: average, ratio: ratio)
                ))
                flaggedIds.insert(bill.id)
            }
        }

        // Sort: over-limit first, then by due date (newest first).
        return reports.sorted { a, b in
            if a.kind.isOverLimit != b.kind.isOverLimit {
                return a.kind.isOverLimit
            }
            return a.bill.dueDate > b.bill.dueDate
        }
    }

    /// Backward-compatible list of flagged bills.
    var anomalies: [Bill] {
        anomalyReports.map { $0.bill }
    }

    /// Subtitle shown under the Anomalies KPI.
    var anomalySubtitle: String {
        guard !anomalyReports.isEmpty else { return "No issues detected" }
        let overLimitCount = anomalyReports.filter { $0.kind.isOverLimit }.count
        let outlierCount = anomalyReports.count - overLimitCount

        switch (overLimitCount, outlierCount) {
        case (0, _):
            return "\(outlierCount) unusually high"
        case (_, 0):
            return "\(overLimitCount) over limit"
        default:
            return "\(overLimitCount) over limit · \(outlierCount) unusual"
        }
    }

    // MARK: - Additional Stats
    var totalSpentThisYear: Double {
        let currentYear = calendar.component(.year, from: now)
        return bills
            .filter { calendar.component(.year, from: $0.dueDate) == currentYear }
            .reduce(0.0) { $0 + $1.amount }
    }

    var totalSpentLast30Days: Double {
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) else { return 0 }
        return bills
            .filter { bill in
                let effectiveDate = bill.isPaid ? (bill.paymentDate ?? bill.dueDate) : bill.dueDate
                return effectiveDate >= thirtyDaysAgo && effectiveDate <= now
            }
            .reduce(0.0) { $0 + $1.amount }
    }

    var totalBudget: Double {
        properties.reduce(0.0) { $0 + $1.monthlyBudget }
    }

    var budgetProgress: Double {
        guard totalBudget > 0 else { return 0 }
        return min(totalSpentThisMonth / totalBudget, 1.0)
    }

    // MARK: - Category Breakdown
    struct CategoryExpense: Identifiable {
        let id: String
        let category: ExpenseCategory
        let amount: Double
        var color: Color { category.color }
    }

    var expensesByCategory: [CategoryExpense] {
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        let sourceBills = bills.filter { bill in
            let effectiveDate = bill.isPaid ? (bill.paymentDate ?? bill.dueDate) : bill.dueDate
            return isSameMonth(effectiveDate, month: currentMonth, year: currentYear)
        }

        let grouped = Dictionary(grouping: sourceBills, by: { $0.category })
        return grouped.map { (category, categoryBills) in
            let total = categoryBills.reduce(0.0) { $0 + $1.amount }
            return CategoryExpense(
                id: category.rawValue,
                category: category,
                amount: total.isFinite ? total : 0
            )
        }.sorted { $0.amount > $1.amount }
    }

    var totalForCategoryChart: Double {
        expensesByCategory.reduce(0.0) { $0 + $1.amount }
    }
}