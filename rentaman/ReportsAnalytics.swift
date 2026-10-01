import Foundation
import SwiftUI

// MARK: - Reports Analytics Engine
/// Computes every stat and chart shown in Reports.
/// All calculations use the SAME effective-date logic as Dashboard:
///   - Paid bills   → attributed to `paymentDate`
///   - Unpaid bills → attributed to `dueDate`
struct ReportsAnalytics {
    let bills: [Bill]
    let properties: [Property]

    private var calendar: Calendar { Calendar.current }
    private var now: Date { Date() }
    private var currentYear: Int { calendar.component(.year, from: now) }
    private var currentMonth: Int { calendar.component(.month, from: now) }

    // MARK: - Effective Date Helper
    private func effectiveDate(for bill: Bill) -> Date {
        if bill.isPaid {
            return bill.paymentDate ?? bill.dueDate
        }
        return bill.dueDate
    }

    // MARK: - Data Point Structs
    struct MonthPoint: Identifiable {
        let id: String
        let date: Date
        let amount: Double
    }

    struct CategoryPoint: Identifiable {
        let id: String
        let category: ExpenseCategory
        let amount: Double
    }

    struct PropertyPoint: Identifiable {
        let id: String
        let name: String
        let color: Color
        let amount: Double
    }

    struct BudgetPoint: Identifiable {
        let id: String
        let name: String
        let budget: Double
        let spent: Double
    }

    // MARK: - KPI: Total Spent This Year
    var totalSpentThisYear: Double {
        let total = bills
            .filter { calendar.component(.year, from: effectiveDate(for: $0)) == currentYear }
            .reduce(0.0) { $0 + $1.amount }
        return total.isFinite ? total : 0
    }

    // MARK: - KPI: Spent This Month (paid) + Expected (unpaid)

    /// Amount actually PAID this month (attributed to `paymentDate`).
    /// Returns 0 at the start of a new month until the first bill is paid —
    /// never falls back to a previous month.
    var totalPaidThisMonth: Double {
        let total = bills
            .filter { bill in
                guard bill.isPaid else { return false }
                let d = effectiveDate(for: bill)
                return calendar.component(.month, from: d) == currentMonth &&
                       calendar.component(.year, from: d) == currentYear
            }
            .reduce(0.0) { $0 + $1.amount }
        return total.isFinite ? total : 0
    }

    /// Amount still expected this month — unpaid bills whose due date
    /// lands in the current month. This is what remains to be paid.
    var totalExpectedThisMonth: Double {
        let total = bills
            .filter { bill in
                guard !bill.isPaid else { return false }
                return calendar.component(.month, from: bill.dueDate) == currentMonth &&
                       calendar.component(.year, from: bill.dueDate) == currentYear
            }
            .reduce(0.0) { $0 + $1.amount }
        return total.isFinite ? total : 0
    }

    /// Total monthly commitment (paid + expected).
    /// Never falls back to a previous month — always reflects the
    /// current calendar month only.
    var totalSpentThisMonth: Double {
        totalPaidThisMonth + totalExpectedThisMonth
    }

    /// Subtitle for the "Spent This Month" KPI. Shows the expected
    /// amount when nothing has been paid yet this month.
    func thisMonthLabel(currency: AppCurrency) -> String {
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

    // MARK: - KPI: Monthly Average (Last 12 Months)
    var averageMonthlySpend: Double {
        let trend = monthlyTrend
        let validAmounts = trend.map { $0.amount }.filter { $0.isFinite && $0 > 0 }
        guard !validAmounts.isEmpty else { return 0 }
        return validAmounts.reduce(0.0, +) / Double(validAmounts.count)
    }

    // MARK: - KPI: Properties Over Budget
    var propertiesOverBudget: [String] {
        budgetVsActual
            .filter { $0.budget > 0 && $0.spent > $0.budget }
            .map { $0.name }
    }

    // MARK: - Chart: Monthly Trend (Last 12 Months)
    var monthlyTrend: [MonthPoint] {
        var points: [MonthPoint] = []
        for offset in stride(from: -11, through: 0, by: 1) {
            guard let monthDate = calendar.date(byAdding: .month, value: offset, to: now) else { continue }
            let month = calendar.component(.month, from: monthDate)
            let year  = calendar.component(.year,  from: monthDate)

            let total = bills
                .filter {
                    let d = effectiveDate(for: $0)
                    return calendar.component(.month, from: d) == month &&
                           calendar.component(.year,  from: d) == year
                }
                .reduce(0.0) { $0 + $1.amount }

            let id = String(format: "%04d-%02d", year, month)
            points.append(MonthPoint(id: id, date: monthDate, amount: total.isFinite ? total : 0))
        }
        return points
    }

    // MARK: - Chart: Category Breakdown (Current Year)
    var categoryBreakdown: [CategoryPoint] {
        let yearBills = bills.filter {
            calendar.component(.year, from: effectiveDate(for: $0)) == currentYear
        }
        let grouped = Dictionary(grouping: yearBills, by: { $0.category })

        return grouped.map { (category, categoryBills) in
            CategoryPoint(
                id: category.rawValue,
                category: category,
                amount: categoryBills.reduce(0.0) { $0 + $1.amount }
            )
        }
        .filter { $0.amount > 0 }
        .sorted { $0.amount > $1.amount }
    }

    // MARK: - Chart: Property Comparison (Current Year)
    var propertyComparison: [PropertyPoint] {
        let yearBills = bills.filter {
            calendar.component(.year, from: effectiveDate(for: $0)) == currentYear
        }

        return properties.map { property in
            let total = yearBills
                .filter { $0.property?.id == property.id }
                .reduce(0.0) { $0 + $1.amount }
            return PropertyPoint(
                id: property.id,
                name: property.name,
                color: Color(hex: property.colorHex),
                amount: total.isFinite ? total : 0
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    // MARK: - Chart: Budget vs Actual
    // Uses current month if it has activity, otherwise falls back to the
    // most recent month with bills — so the chart still shows SOMETHING
    // on the 1st of a new month before any bills are logged.
    var budgetVsActual: [BudgetPoint] {
        let hasCurrentMonth = bills.contains {
            let d = effectiveDate(for: $0)
            return calendar.component(.month, from: d) == currentMonth &&
                   calendar.component(.year, from: d) == currentYear
        }

        let targetMonth: Int
        let targetYear: Int
        if hasCurrentMonth {
            targetMonth = currentMonth
            targetYear = currentYear
        } else if let recent = mostRecentBill() {
            targetMonth = calendar.component(.month, from: recent)
            targetYear = calendar.component(.year, from: recent)
        } else {
            return []
        }

        return properties.map { property in
            let spent = bills
                .filter { bill in
                    let d = effectiveDate(for: bill)
                    return bill.property?.id == property.id &&
                           calendar.component(.month, from: d) == targetMonth &&
                           calendar.component(.year, from: d) == targetYear
                }
                .reduce(0.0) { $0 + $1.amount }

            return BudgetPoint(
                id: property.id,
                name: property.name,
                budget: property.monthlyBudget,
                spent: spent.isFinite ? spent : 0
            )
        }
    }

    var budgetVsActualLabel: String {
        let hasCurrentMonth = bills.contains {
            let d = effectiveDate(for: $0)
            return calendar.component(.month, from: d) == currentMonth &&
                   calendar.component(.year, from: d) == currentYear
        }
        if hasCurrentMonth {
            return now.formatted(.dateTime.month(.wide).year())
        }
        guard let recent = mostRecentBill() else { return "No data" }
        return recent.formatted(.dateTime.month(.wide).year())
    }

    // MARK: - Chart: Top 10 Expenses (Current Year)
    var topExpenses: [Bill] {
        bills
            .filter { calendar.component(.year, from: effectiveDate(for: $0)) == currentYear }
            .sorted { $0.amount > $1.amount }
            .prefix(10)
            .map { $0 }
    }

    // MARK: - Additional Insights
    var totalBillsThisYear: Int {
        bills.filter {
            calendar.component(.year, from: effectiveDate(for: $0)) == currentYear
        }.count
    }

    var paidBillsThisYear: Int {
        bills.filter {
            $0.isPaid &&
            calendar.component(.year, from: effectiveDate(for: $0)) == currentYear
        }.count
    }

    var unpaidBillsThisYear: Int {
        bills.filter {
            !$0.isPaid &&
            calendar.component(.year, from: effectiveDate(for: $0)) == currentYear
        }.count
    }

    var paymentRate: Double {
        let total = totalBillsThisYear
        guard total > 0 else { return 0 }
        return Double(paidBillsThisYear) / Double(total)
    }

    // MARK: - Helpers
    private func mostRecentBill() -> Date? {
        bills.map { effectiveDate(for: $0) }.max()
    }
}