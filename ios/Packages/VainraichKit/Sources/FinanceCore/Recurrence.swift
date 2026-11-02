import Foundation

public enum RecurrenceEngine {
    /// Safety cap so a malformed rule can never loop forever.
    static let maxIterations = 20_000

    /// All occurrence dates of `rule` that fall inside `range` (inclusive), honouring
    /// `startDate`, `endDate`, `maxOccurrences` (counted from the start, not from the range).
    public static func occurrences(of rule: RecurringRule, in range: DateRange) -> [LocalDate] {
        guard rule.isActive else { return [] }
        let hardEnd = min(range.end, rule.endDate ?? range.end)
        guard hardEnd >= rule.startDate else { return [] }

        var result: [LocalDate] = []
        var count = 0
        let limit = rule.maxOccurrences ?? Int.max
        var iterations = 0

        func consider(_ d: LocalDate) -> Bool {
            // Returns false when generation should stop.
            iterations += 1
            if iterations > maxIterations || d > hardEnd || count >= limit { return false }
            if d < rule.startDate { return true }
            count += 1
            if d >= range.start { result.append(d) }
            return true
        }

        switch rule.frequency {
        case .daily:
            var n = 0
            while consider(rule.startDate.adding(days: n * rule.interval)) { n += 1 }

        case .weekly:
            let days = (rule.weekdays.isEmpty ? [rule.startDate.weekday] : rule.weekdays).filter { (1...7).contains($0) }.sorted()
            let weekStart = rule.startDate.startOfWeek()
            var k = 0
            outer: while true {
                let base = weekStart.adding(days: 7 * k * rule.interval)
                if base > hardEnd { break }
                for wd in days {
                    if !consider(base.adding(days: wd - 1)) { break outer }
                }
                k += 1
                if k > maxIterations { break }
            }

        case .monthly:
            let anchor = rule.dayOfMonth ?? rule.startDate.day
            var n = 0
            while true {
                let d = rule.startDate.startOfMonth.adding(months: n * rule.interval, preferredDay: anchor)
                if !consider(d) { break }
                n += 1
            }

        case .yearly:
            let anchor = rule.dayOfMonth ?? rule.startDate.day
            var n = 0
            while true {
                let d = LocalDate(year: rule.startDate.year + n * rule.interval, month: rule.startDate.month, day: anchor)
                if !consider(d) { break }
                n += 1
            }
        }
        return result
    }

    /// Occurrences in `range` that do **not** yet have a recorded transaction (any status).
    /// This is what prevents a recurring item from being counted twice (scenario D).
    public static func unrecordedOccurrences(of rule: RecurringRule, in range: DateRange, transactions: [FinanceTransaction]) -> [LocalDate] {
        let recorded = Set(transactions.compactMap { $0.recurringID == rule.id ? $0.occurrenceDate : nil })
        return occurrences(of: rule, in: range).filter { !recorded.contains($0) }
    }

    /// A transaction for one occurrence of the rule.
    public static func makeTransaction(for rule: RecurringRule, on date: LocalDate, status: TransactionStatus) -> FinanceTransaction {
        FinanceTransaction(
            kind: rule.kind, status: status, amount: rule.amount, accountID: rule.accountID,
            counterAccountID: rule.kind == .transfer ? rule.counterAccountID : nil,
            categoryID: rule.kind == .transfer ? nil : rule.categoryID, contactID: rule.contactID,
            title: rule.title, date: date, paymentMethod: rule.paymentMethod, recurringID: rule.id,
            occurrenceDate: date, source: .recurring
        )
    }

    /// Transactions to create so that every occurrence up to `today` is recorded.
    /// Auto-post rules become `.completed`; others become `.pending` (awaiting the user's confirmation).
    /// Never creates a second transaction for an occurrence that already has one.
    public static func materialize(rules: [RecurringRule], through today: LocalDate, existing: [FinanceTransaction]) -> [FinanceTransaction] {
        var created: [FinanceTransaction] = []
        for rule in rules where rule.isActive {
            let range = DateRange(start: rule.startDate, end: today)
            for d in unrecordedOccurrences(of: rule, in: range, transactions: existing) {
                created.append(makeTransaction(for: rule, on: d, status: rule.autoPost ? .completed : .pending))
            }
        }
        return created
    }

    /// Next occurrence on or after `date`, if any.
    public static func nextOccurrence(of rule: RecurringRule, onOrAfter date: LocalDate) -> LocalDate? {
        occurrences(of: rule, in: DateRange(start: date, end: date.adding(years: 2))).first
    }
}
