import Foundation
import SwiftUI

// MARK: - Reports Analytics Engine
/// Computes every stat and chart shown in Reports.
/// All calculations use the SAME effective-date logic as Dashboard:
///   - Paid bills   → attributed to `paymentDate`
///   - Unpaid bills → attributed to `dueDate`
/// This matches real cash flow instead of accrual accounting.
struct ReportsAnalytics {
    let bills: [Bill]
    let properties: [Property]
    
    private var calendar: Calendar { Calendar.current }
    private var now: Date { Date() }
    private var currentYear: Int { calendar.component(.year, from: now) }
    private var currentMonth: Int { calendar.component(.month, from: now) }
    
    // MARK: - Effective Date Helper
    /// The date that determines which period a bill belongs to for cash-flow purposes.
    /// - Paid → paymentDate (or dueDate as fallback)
    /// - Unpaid → dueDate
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
    
    // MARK: - KPI: Total Spent This Month
    var totalSpentThisMonth: Double {
        let thisMonth = bills
            .filter {
                let d = effectiveDate(for: $0)
                return calendar.component(.month, from: d) == currentMonth &&
                       calendar.component(.year, from: d) == currentYear
            }
            .reduce(0.0) { $0 + $1.amount }
        
        if thisMonth > 0 { return thisMonth }
        return mostRecentMonthTotal()
    }
    
    var thisMonthLabel: String {
        let monthBills = bills.filter {
            let d = effectiveDate(for: $0)
            return calendar.component(.month, from: d) == currentMonth &&
                   calendar.component(.year, from: d) == currentYear
        }
        
        if !monthBills.isEmpty {
            let paidCount = monthBills.filter { $0.isPaid }.count
            let unpaidCount = monthBills.count - paidCount
            let monthName = now.formatted(.dateTime.month(.wide).year())
            
            if unpaidCount == 0 { return "\(monthName) · all paid" }
            if paidCount == 0 { return "\(monthName) · expected" }
            return "\(monthName) · paid + committed"
        }
        
        guard let recent = mostRecentBill() else { return "No activity yet" }
        return recent.formatted(.dateTime.month(.wide).year())
    }
    
    private func mostRecentBill() -> Date? {
        bills.map { effectiveDate(for: $0) }.max()
    }
    
    private func mostRecentMonthTotal() -> Double {
        guard let recent = mostRecentBill() else { return 0 }
        let month = calendar.component(.month, from: recent)
        let year = calendar.component(.year, from: recent)
        return bills
            .filter {
                let d = effectiveDate(for: $0)
                return calendar.component(.month, from: d) == month &&
                       calendar.component(.year, from: d) == year
            }
            .reduce(0.0) { $0 + $1.amount }
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
            let year = calendar.component(.year, from: monthDate)
            
            let total = bills
                .filter {
                    let d = effectiveDate(for: $0)
                    return calendar.component(.month, from: d) == month &&
                           calendar.component(.year, from: d) == year
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
    
    // MARK: - Chart: Budget vs Actual (Current Month with fallback)
    var budgetVsActual: [BudgetPoint] {
        // Determine target month based on effective dates
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
}