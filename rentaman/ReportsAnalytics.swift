import Foundation
import SwiftUI

/// Handles all calculations for the Reports view. Fully defensive against missing/empty data.
struct ReportsAnalytics {
    let bills: [Bill]
    let properties: [Property]
    
    // MARK: - Data Point Structs for Charts
    struct MonthPoint: Identifiable {
        let id = UUID()
        let date: Date
        let amount: Double
    }
    
    struct CategoryPoint: Identifiable {
        let id = UUID()
        let category: ExpenseCategory
        let amount: Double
    }
    
    struct PropertyPoint: Identifiable {
        let id = UUID()
        let name: String
        let color: Color
        let amount: Double
    }
    
    struct BudgetPoint: Identifiable {
        let id = UUID()
        let name: String
        let budget: Double
        let spent: Double
    }
    
    // MARK: - Date Helpers (Defensive)
    private var calendar: Calendar { Calendar.current }
    private var now: Date { Date() }
    private var currentYear: Int { calendar.component(.year, from: now) }
    private var currentMonth: Int { calendar.component(.month, from: now) }
    
    // MARK: - Monthly Trend (Last 12 Months)
    var monthlyTrend: [MonthPoint] {
        var points: [MonthPoint] = []
        for offset in stride(from: -11, through: 0, by: 1) {
            guard let monthDate = calendar.date(byAdding: .month, value: offset, to: now) else { continue }
            let month = calendar.component(.month, from: monthDate)
            let year = calendar.component(.year, from: monthDate)
            
            let total = bills.filter {
                calendar.component(.month, from: $0.dueDate) == month &&
                calendar.component(.year, from: $0.dueDate) == year
            }.reduce(0.0) { $0 + $1.amount }
            
            points.append(MonthPoint(date: monthDate, amount: total))
        }
        return points
    }
    
    // MARK: - Category Breakdown (Current Year)
    var categoryBreakdown: [CategoryPoint] {
        let yearBills = bills.filter { calendar.component(.year, from: $0.dueDate) == currentYear }
        let grouped = Dictionary(grouping: yearBills, by: { $0.category })
        
        return grouped.map { (category, bills) in
            CategoryPoint(category: category, amount: bills.reduce(0.0) { $0 + $1.amount })
        }.sorted { $0.amount > $1.amount }
    }
    
    // MARK: - Property Comparison (Current Year)
    var propertyComparison: [PropertyPoint] {
        let yearBills = bills.filter { calendar.component(.year, from: $0.dueDate) == currentYear }
        
        return properties.map { property in
            let total = yearBills
                .filter { $0.property?.id == property.id }
                .reduce(0.0) { $0 + $1.amount }
            return PropertyPoint(
                name: property.name,
                color: Color(hex: property.colorHex),
                amount: total
            )
        }.sorted { $0.amount > $1.amount }
    }
    
    // MARK: - Budget vs Actual (Current Month)
    var budgetVsActual: [BudgetPoint] {
        properties.map { property in
            let monthlySpent = bills.filter {
                $0.property?.id == property.id &&
                calendar.component(.month, from: $0.dueDate) == currentMonth &&
                calendar.component(.year, from: $0.dueDate) == currentYear
            }.reduce(0.0) { $0 + $1.amount }
            
            return BudgetPoint(
                name: property.name,
                budget: property.monthlyBudget,
                spent: monthlySpent
            )
        }
    }
    
    // MARK: - Top 10 Expenses (Current Year)
    var topExpenses: [Bill] {
        bills
            .filter { calendar.component(.year, from: $0.dueDate) == currentYear }
            .sorted { $0.amount > $1.amount }
            .prefix(10)
            .map { $0 }
    }
    
    // MARK: - Summary KPIs
    var totalSpentThisYear: Double {
        bills
            .filter { calendar.component(.year, from: $0.dueDate) == currentYear }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    var totalSpentThisMonth: Double {
        bills
            .filter {
                calendar.component(.month, from: $0.dueDate) == currentMonth &&
                calendar.component(.year, from: $0.dueDate) == currentYear
            }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    var averageMonthlySpend: Double {
        let trend = monthlyTrend
        guard !trend.isEmpty else { return 0 }
        return trend.reduce(0.0) { $0 + $1.amount } / Double(trend.count)
    }
    
    var paidVsUnpaidRatio: (paid: Double, unpaid: Double) {
        let yearBills = bills.filter { calendar.component(.year, from: $0.dueDate) == currentYear }
        let paid = yearBills.filter { $0.isPaid }.reduce(0.0) { $0 + $1.amount }
        let unpaid = yearBills.filter { !$0.isPaid }.reduce(0.0) { $0 + $1.amount }
        return (paid, unpaid)
    }
    
    // MARK: - Budget Health
    var propertiesOverBudget: [String] {
        budgetVsActual
            .filter { $0.budget > 0 && $0.spent > $0.budget }
            .map { $0.name }
    }
}
