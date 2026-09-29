import Foundation
import SwiftUI

/// A struct to calculate all dashboard statistics defensively.
struct DashboardAnalytics {
    let bills: [Bill]
    
    // 1. Incoming & Unpaid Bills
    var unpaidBills: [Bill] {
        bills.filter { !$0.isPaid }.sorted { $0.dueDate < $1.dueDate }
    }
    
    var totalUnpaidAmount: Double {
        let total = unpaidBills.reduce(0.0) { $0 + $1.amount }
        return total.isFinite ? total : 0
    }
    
    var upcomingBills: [Bill] {
        let calendar = Calendar.current
        guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date()) else { return [] }
        return unpaidBills.filter { $0.dueDate <= nextWeek }
    }
    
    // 2. Monthly Budget vs Actual Spend (Current Month)
    var totalSpentThisMonth: Double {
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: Date())
        let currentYear = calendar.component(.year, from: Date())
        
        let total = bills.filter {
            let billMonth = calendar.component(.month, from: $0.dueDate)
            let billYear = calendar.component(.year, from: $0.dueDate)
            return billMonth == currentMonth && billYear == currentYear
        }.reduce(0.0) { $0 + $1.amount }
        
        return total.isFinite ? total : 0
    }
    
    // 3. Anomaly Detection (Defensive Logic)
    var anomalies: [Bill] {
        var flaggedBills: [Bill] = []
        let calendar = Calendar.current
        guard let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: Date()) else { return [] }
        
        let grouped = Dictionary(grouping: bills, by: { $0.categoryRawValue })
        
        for (_, categoryBills) in grouped {
            let historicalBills = categoryBills.filter { $0.dueDate < Date() && $0.dueDate >= sixMonthsAgo }
            guard historicalBills.count >= 3 else { continue }
            
            let totalHistorical = historicalBills.reduce(0.0) { $0 + $1.amount }
            guard totalHistorical.isFinite else { continue }
            let average = totalHistorical / Double(historicalBills.count)
            guard average.isFinite, average > 0 else { continue }
            
            for bill in categoryBills where bill.dueDate >= Date() {
                if bill.amount > (average * 1.5) {
                    flaggedBills.append(bill)
                }
            }
        }
        return flaggedBills
    }
    
    // 4. Data Preparation for Swift Charts
    struct CategoryExpense: Identifiable {
        let id: String
        let category: String
        let amount: Double
        let color: Color
    }
    
    var expensesByCategory: [CategoryExpense] {
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: Date())
        let currentYear = calendar.component(.year, from: Date())
        
        let thisMonthBills = bills.filter {
            let billMonth = calendar.component(.month, from: $0.dueDate)
            let billYear = calendar.component(.year, from: $0.dueDate)
            return billMonth == currentMonth && billYear == currentYear
        }
        
        let grouped = Dictionary(grouping: thisMonthBills, by: { $0.category })
        
        return grouped.map { (category, categoryBills) in
            let total = categoryBills.reduce(0.0) { $0 + $1.amount }
            return CategoryExpense(
                id: category.rawValue,
                category: category.rawValue,
                amount: total.isFinite ? total : 0,
                color: category.color
            )
        }.sorted { $0.amount > $1.amount }
    }
}
