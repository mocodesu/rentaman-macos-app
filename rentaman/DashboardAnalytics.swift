import Foundation
import SwiftUI

// MARK: - Dashboard Analytics Engine
/// Computes every KPI shown on the dashboard.
/// All calculations are defensive: safe with empty data, future dates, and NaN.
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
    
    // MARK: - KPI 2: Upcoming (Next 7 Days)
    var upcomingBills: [Bill] {
        guard let in7Days = calendar.date(byAdding: .day, value: 7, to: now) else { return [] }
        return unpaidBills.filter { bill in
            bill.dueDate >= now && bill.dueDate <= in7Days
        }
    }
    
    var overdueBills: [Bill] {
        unpaidBills.filter { $0.dueDate < now }
    }
    
    // MARK: - KPI 3: Spent This Month
    /// Sum of bills whose EFFECTIVE DATE falls in the current calendar month.
    ///
    /// Effective date rules:
    ///   - If a bill is PAID → use `paymentDate` (when money actually left your pocket)
    ///   - If a bill is UNPAID → use `dueDate` (the expected outlay)
    ///
    /// This ensures a bill paid in September for an October due date counts
    /// toward September spend — matching your real cash flow.
    var totalSpentThisMonth: Double {
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        
        let total = bills
            .filter { bill in
                let effectiveDate = bill.isPaid ? (bill.paymentDate ?? bill.dueDate) : bill.dueDate
                return isSameMonth(effectiveDate, month: currentMonth, year: currentYear)
            }
            .reduce(0.0) { $0 + $1.amount }
        
        return total.isFinite ? total : 0
    }
    
    /// Clarifying label — shows which month and whether paid or committed amounts
    /// are included.
    var spentThisMonthLabel: String {
        let totalBillsInMonth = bills.filter { bill in
            let effectiveDate = bill.isPaid ? (bill.paymentDate ?? bill.dueDate) : bill.dueDate
            let month = calendar.component(.month, from: now)
            let year = calendar.component(.year, from: now)
            return isSameMonth(effectiveDate, month: month, year: year)
        }
        
        if totalBillsInMonth.isEmpty {
            return "No activity this month"
        }
        
        let paidCount = totalBillsInMonth.filter { $0.isPaid }.count
        let unpaidCount = totalBillsInMonth.count - paidCount
        
        let monthName = now.formatted(.dateTime.month(.wide).year())
        
        if unpaidCount == 0 {
            return "\(monthName) · all paid"
        } else if paidCount == 0 {
            return "\(monthName) · expected"
        } else {
            return "\(monthName) · paid + committed"
        }
    }
    
    private func isSameMonth(_ date: Date, month: Int, year: Int) -> Bool {
        calendar.component(.month, from: date) == month &&
        calendar.component(.year, from: date) == year
    }
    
    // MARK: - KPI 4: Anomalies
    /// Flags bills in the last 90 days whose amount is > 1.5× the average
    /// of the same category over the preceding 6 months.
    var anomalies: [Bill] {
        var flagged: [Bill] = []
        guard let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: now),
              let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) else {
            return []
        }
        
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
                if bill.amount > average * 1.5 {
                    flagged.append(bill)
                }
            }
        }
        return flagged.sorted { $0.dueDate > $1.dueDate }
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
        
        // Use the same effective-date logic as the KPI
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