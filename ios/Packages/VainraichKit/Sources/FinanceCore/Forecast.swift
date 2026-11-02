import Foundation

/// How sure we are that a forecast item will happen.
public enum ForecastConfidence: String, Codable, CaseIterable, Sendable, Comparable {
    /// Entered by the user with a fixed amount and date (pending transactions, known card bill).
    case confirmed
    /// Planned / recurring (recurring rules, event budgets, debts the user owes).
    case expected
    /// Depends on someone else (money others owe the user).
    case estimated

    public static func < (l: Self, r: Self) -> Bool {
        let order: [Self] = [.confirmed, .expected, .estimated]
        return order.firstIndex(of: l)! < order.firstIndex(of: r)!
    }
}

public enum ForecastSource: Hashable, Sendable {
    case pendingTransaction(UUID)
    case recurring(ruleID: UUID, date: LocalDate)
    case eventIncome(UUID)
    case eventExpense(UUID)
    case receivable(UUID)
    case payable(UUID)
    case creditCardBill(cardID: UUID)
}

public struct ForecastItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var date: LocalDate
    public var title: String
    /// Signed effect on available money.
    public var amount: Decimal
    public var confidence: ForecastConfidence
    public var source: ForecastSource
    /// The underlying date had already passed (shown on the first forecast day).
    public var isOverdue: Bool
}

public struct ForecastDay: Hashable, Sendable, Identifiable {
    public var id: LocalDate { date }
    public var date: LocalDate
    /// Balance assuming everything in the forecast happens.
    public var projectedBalance: Decimal
    /// Balance counting only confirmed items.
    public var confirmedBalance: Decimal
    public var inflow: Decimal
    public var outflow: Decimal
}

public struct Forecast: Sendable {
    public var range: DateRange
    /// Actual available money right now (completed transactions only).
    public var startingBalance: Decimal
    public var items: [ForecastItem]
    public var days: [ForecastDay]

    public var endingBalance: Decimal { days.last?.projectedBalance ?? startingBalance }
    public var endingConfirmedBalance: Decimal { days.last?.confirmedBalance ?? startingBalance }
    public var expectedIncome: Decimal { items.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount } }
    public var expectedExpenses: Decimal { items.filter { $0.amount < 0 }.reduce(0) { $0 - $1.amount } }
    public func total(_ confidence: ForecastConfidence, sign: FloatingPointSign) -> Decimal {
        items.filter { $0.confidence == confidence && (sign == .plus ? $0.amount > 0 : $0.amount < 0) }
            .reduce(0) { $0 + $1.amount.magnitudeValue }
    }
    public var firstNegativeDay: ForecastDay? { days.first { $0.projectedBalance < 0 } }
    public var lowestDay: ForecastDay? { days.min { $0.projectedBalance < $1.projectedBalance } }
}

public struct ForecastOptions: Sendable {
    public var includeReceivables: Bool
    public var includePayables: Bool
    public init(includeReceivables: Bool = true, includePayables: Bool = true) {
        self.includeReceivables = includeReceivables
        self.includePayables = includePayables
    }
}

/// Builds the cash-flow forecast for the user's *available* money.
///
/// Rules (see ARCHITECTURE.md §4.8):
/// * Start = actual available balance (completed transactions only). Expected money is never added to it.
/// * Pending transactions are confirmed items; overdue ones appear on the first day.
/// * Recurring occurrences that already have a transaction are skipped (no duplicates).
/// * Event income counts only the part not covered by linked transactions, and is skipped when the event
///   has a linked receivable (the receivable is counted instead).
/// * Receivables are *estimated* and can be excluded. Debts without a due date are not placed on the timeline.
/// * Credit-card purchases do not touch available money; the card bill on its billing day does.
public enum ForecastEngine {
    public static func make(data: FinanceData, range requested: DateRange, today: LocalDate, options: ForecastOptions? = nil) -> Forecast {
        let opts = options ?? ForecastOptions(includeReceivables: data.settings.includeReceivablesInForecast,
                                              includePayables: data.settings.includePayablesInForecast)
        let range = DateRange(start: max(requested.start, today), end: max(requested.end, today))
        let active = data.accounts.filter(\.isActive)
        let availableIDs = Set(active.filter(\.includeInAvailable).map(\.id))
        let balances = Ledger.balances(accounts: data.accounts, transactions: data.transactions)
        let start = availableIDs.reduce(Decimal(0)) { $0 + (balances[$1] ?? 0) }

        var items: [ForecastItem] = []
        /// Future movements on credit cards (signed effect on the card), used to size upcoming bills.
        var cardFlows: [UUID: [(LocalDate, Decimal)]] = [:]
        let cards = active.filter { $0.type == .creditCard }
        let cardIDs = Set(cards.map(\.id))

        func place(_ d: LocalDate) -> (LocalDate, Bool) { d < range.start ? (range.start, true) : (d, false) }

        func add(_ t: FinanceTransaction, id: String, confidence: ForecastConfidence, source: ForecastSource) {
            let (d, overdue) = place(t.date)
            guard d <= range.end else { return }
            let eff = Ledger.availableEffect(of: t, availableIDs: availableIDs)
            if eff != 0 {
                items.append(ForecastItem(id: id, date: d, title: t.title, amount: eff, confidence: confidence, source: source, isOverdue: overdue))
            }
            for card in Ledger.touchedAccounts(t) where cardIDs.contains(card) {
                cardFlows[card, default: []].append((d, Ledger.effect(of: t, on: card)))
            }
        }

        // 1. Pending transactions.
        for t in data.transactions where t.status == .pending {
            add(t, id: "tx-\(t.id)", confidence: .confirmed, source: .pendingTransaction(t.id))
        }

        // 2. Recurring occurrences without a recorded transaction.
        for rule in data.recurringRules where rule.isActive {
            // Unrecorded past occurrences are surfaced as overdue on the first day.
            let lookback = DateRange(start: max(rule.startDate, today.adding(days: -31)), end: range.end)
            for d in RecurrenceEngine.unrecordedOccurrences(of: rule, in: lookback, transactions: data.transactions) {
                if d < today && rule.autoPost { continue } // will be auto-posted, already part of the balance flow
                let t = RecurrenceEngine.makeTransaction(for: rule, on: d, status: .pending)
                add(t, id: "rec-\(rule.id)-\(d.isoString)", confidence: .expected, source: .recurring(ruleID: rule.id, date: d))
            }
        }

        // 3. Events.
        let firstAvailable = active.first { $0.includeInAvailable }
        for event in data.events {
            let fin = EventCalculator.financials(of: event, transactions: data.transactions)
            let (d, overdue) = place(event.date)
            guard d <= range.end else { continue }
            if event.debtID == nil, fin.outstandingIncome > 0, firstAvailable != nil {
                items.append(ForecastItem(id: "evi-\(event.id)", date: d, title: event.title, amount: fin.outstandingIncome,
                                          confidence: .expected, source: .eventIncome(event.id), isOverdue: overdue))
            }
            if fin.outstandingExpense > 0, firstAvailable != nil {
                items.append(ForecastItem(id: "eve-\(event.id)", date: d, title: event.title, amount: -fin.outstandingExpense,
                                          confidence: .expected, source: .eventExpense(event.id), isOverdue: overdue))
            }
        }

        // 4. Debts with a due date.
        for bal in DebtCalculator.balances(data, today: today) where bal.isOpen && bal.remaining > 0 {
            guard let due = bal.debt.dueDate else { continue }
            let (d, overdue) = place(due)
            guard d <= range.end else { continue }
            let name = data.contact(bal.debt.contactID)?.name ?? ""
            switch bal.debt.direction {
            case .receivable where opts.includeReceivables:
                items.append(ForecastItem(id: "rcv-\(bal.debt.id)", date: d, title: name.isEmpty ? bal.debt.title : "\(name) · \(bal.debt.title)",
                                          amount: bal.remaining, confidence: .estimated, source: .receivable(bal.debt.id), isOverdue: overdue))
            case .payable where opts.includePayables:
                items.append(ForecastItem(id: "pay-\(bal.debt.id)", date: d, title: name.isEmpty ? bal.debt.title : "\(name) · \(bal.debt.title)",
                                          amount: -bal.remaining, confidence: .expected, source: .payable(bal.debt.id), isOverdue: overdue))
            default:
                break
            }
        }

        // 5. Credit-card bills on billing day, paid from the linked account.
        for card in cards {
            guard let day = card.billingDay, let payer = card.paymentAccountID, availableIDs.contains(payer) else { continue }
            var outstanding = max(0, -(balances[card.id] ?? 0)) // current card debt
            var flows = (cardFlows[card.id] ?? []).sorted { $0.0 < $1.0 }
            var billDate = LocalDate(year: today.year, month: today.month, day: day)
            if billDate < today { billDate = billDate.startOfMonth.adding(months: 1, preferredDay: day) }
            var guardCount = 0
            while billDate <= range.end && guardCount < 60 {
                guardCount += 1
                while let f = flows.first, f.0 <= billDate {
                    outstanding -= f.1 // purchases make the effect negative → debt grows
                    flows.removeFirst()
                }
                if outstanding > 0 {
                    items.append(ForecastItem(id: "card-\(card.id)-\(billDate.isoString)", date: billDate, title: "חיוב \(card.name)",
                                              amount: -outstanding, confidence: .confirmed, source: .creditCardBill(cardID: card.id), isOverdue: false))
                    outstanding = 0
                }
                billDate = billDate.startOfMonth.adding(months: 1, preferredDay: day)
            }
        }

        items.sort { ($0.date, $0.confidence, $0.title) < ($1.date, $1.confidence, $1.title) }

        // Daily series.
        var byDay: [LocalDate: [ForecastItem]] = [:]
        for i in items { byDay[i.date, default: []].append(i) }
        var projected = start
        var confirmed = start
        var days: [ForecastDay] = []
        for d in range.days {
            let todays = byDay[d] ?? []
            let inflow = todays.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
            let outflow = todays.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 - $1.amount }
            projected += inflow - outflow
            confirmed += todays.filter { $0.confidence == .confirmed }.reduce(Decimal(0)) { $0 + $1.amount }
            days.append(ForecastDay(date: d, projectedBalance: projected, confirmedBalance: confirmed, inflow: inflow, outflow: outflow))
        }
        return Forecast(range: range, startingBalance: start, items: items, days: days)
    }
}
