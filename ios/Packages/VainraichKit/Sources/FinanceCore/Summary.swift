import Foundation

/// The dashboard's numbers. Keeps actual, expected, receivable and liability money strictly apart.
public struct FinancialSummary: Sendable {
    /// Money available right now: sum of active accounts marked "available" (bank, cash, Bit by default).
    public var available: Decimal
    public var availableByType: [AccountType: Decimal]
    /// Outstanding credit-card debt (positive number).
    public var creditCardLiability: Decimal
    /// What the user still owes others (open payables).
    public var payablesOutstanding: Decimal
    /// What others still owe the user (open receivables). Never part of `available`.
    public var receivablesOutstanding: Decimal
    public var overdueReceivables: Decimal
    public var savings: Decimal

    /// Completed income/expense inside the period (transfers and adjustments excluded).
    public var periodIncome: Decimal
    public var periodExpenses: Decimal
    public var periodNetCashFlow: Decimal { periodIncome - periodExpenses }

    /// From the forecast for the same period (from today to the period end).
    public var expectedIncome: Decimal
    public var expectedExpenses: Decimal
    /// available + expectedIncome − expectedExpenses.
    public var projectedBalance: Decimal

    public var totalLiabilities: Decimal { creditCardLiability + payablesOutstanding }

    public var forecast: Forecast
}

public enum SummaryCalculator {
    public static func make(data: FinanceData, period: DateRange, today: LocalDate) -> FinancialSummary {
        let active = data.accounts.filter(\.isActive)
        let balances = Ledger.balances(accounts: data.accounts, transactions: data.transactions)

        var available: Decimal = 0
        var byType: [AccountType: Decimal] = [:]
        var card: Decimal = 0
        var savings: Decimal = 0
        for a in active {
            let b = balances[a.id] ?? 0
            if a.includeInAvailable {
                available += b
                byType[a.type, default: 0] += b
            }
            if a.type == .creditCard { card += max(0, -b) }
            if a.type == .savings { savings += b }
        }

        var receivables: Decimal = 0
        var overdue: Decimal = 0
        var payables: Decimal = 0
        for b in DebtCalculator.balances(data, today: today) where b.isOpen {
            switch b.debt.direction {
            case .receivable:
                receivables += b.remaining
                if b.isOverdue { overdue += b.remaining }
            case .payable:
                payables += b.remaining
            }
        }

        var income: Decimal = 0
        var expenses: Decimal = 0
        for t in data.transactions where t.countsInReports && period.contains(t.date) {
            if t.kind == .income { income += t.amount } else { expenses += t.amount }
        }

        let forecastRange = DateRange(start: today, end: max(period.end, today))
        let forecast = ForecastEngine.make(data: data, range: forecastRange, today: today)

        return FinancialSummary(
            available: available, availableByType: byType, creditCardLiability: card, payablesOutstanding: payables,
            receivablesOutstanding: receivables, overdueReceivables: overdue, savings: savings,
            periodIncome: income, periodExpenses: expenses,
            expectedIncome: forecast.expectedIncome, expectedExpenses: forecast.expectedExpenses,
            projectedBalance: forecast.endingBalance, forecast: forecast
        )
    }
}

// MARK: - Reports

public struct MonthKey: Hashable, Comparable, Sendable, Identifiable {
    public var year: Int
    public var month: Int
    public var id: Int { year * 100 + month }
    public init(year: Int, month: Int) { self.year = year; self.month = month }
    public init(_ d: LocalDate) { self.year = d.year; self.month = d.month }
    public var range: DateRange { DateRange.month(containing: LocalDate(year: year, month: month, day: 1)) }
    public func adding(months: Int) -> MonthKey { MonthKey(LocalDate(year: year, month: month, day: 1).adding(months: months)) }
    public static func < (l: MonthKey, r: MonthKey) -> Bool { l.id < r.id }
    /// "12/2026"
    public var label: String { String(format: "%02d/%04d", month, year) }
}

public struct MonthSummary: Hashable, Sendable, Identifiable {
    public var id: Int { month.id }
    public var month: MonthKey
    public var income: Decimal
    public var expenses: Decimal
    public var net: Decimal { income - expenses }
}

public struct BreakdownSlice: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var icon: String
    public var colorToken: String
    public var amount: Decimal
    public var share: Double
}

public enum ReportBuilder {
    public static func monthly(_ data: FinanceData, endingAt month: MonthKey, count: Int) -> [MonthSummary] {
        (0..<max(count, 1)).reversed().map { i in
            let m = month.adding(months: -i)
            var inc: Decimal = 0
            var exp: Decimal = 0
            for t in data.transactions where t.countsInReports && m.range.contains(t.date) {
                if t.kind == .income { inc += t.amount } else { exp += t.amount }
            }
            return MonthSummary(month: m, income: inc, expenses: exp)
        }
    }

    /// Category breakdown of completed income or expenses in a range.
    public static func byCategory(_ data: FinanceData, kind: TransactionKind, range: DateRange) -> [BreakdownSlice] {
        var totals: [UUID?: Decimal] = [:]
        for t in data.transactions where t.countsInReports && t.kind == kind && range.contains(t.date) {
            totals[t.categoryID, default: 0] += t.amount
        }
        let sum = totals.values.reduce(Decimal(0), +)
        return totals.map { (id, amount) in
            let c = data.category(id)
            return BreakdownSlice(id: id?.uuidString ?? "none", name: c?.name ?? "ללא קטגוריה", icon: c?.icon ?? "questionmark.circle",
                                  colorToken: c?.colorToken ?? "gray", amount: amount,
                                  share: sum > 0 ? NSDecimalNumber(decimal: amount / sum).doubleValue : 0)
        }.sorted { $0.amount > $1.amount }
    }

    /// Income by source (contact when known, otherwise category).
    public static func incomeBySource(_ data: FinanceData, range: DateRange) -> [BreakdownSlice] {
        var totals: [String: (String, Decimal)] = [:]
        for t in data.transactions where t.countsInReports && t.kind == .income && range.contains(t.date) {
            let key: String
            let name: String
            if let c = data.contact(t.contactID) {
                key = "c-\(c.id)"; name = c.name
            } else if let cat = data.category(t.categoryID) {
                key = "k-\(cat.id)"; name = cat.name
            } else {
                key = "none"; name = "אחר"
            }
            totals[key, default: (name, 0)].1 += t.amount
        }
        let sum = totals.values.reduce(Decimal(0)) { $0 + $1.1 }
        return totals.map { key, v in
            BreakdownSlice(id: key, name: v.0, icon: key.hasPrefix("c-") ? "person" : "tag", colorToken: "green", amount: v.1,
                           share: sum > 0 ? NSDecimalNumber(decimal: v.1 / sum).doubleValue : 0)
        }.sorted { $0.amount > $1.amount }
    }
}
