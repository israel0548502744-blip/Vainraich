import Foundation

public struct DebtBalance: Hashable, Sendable {
    public let debt: Debt
    public let paid: Decimal
    public let remaining: Decimal
    public let status: DebtStatus
    public let isOverdue: Bool
    public let lastPaymentDate: LocalDate?

    /// 0…1 share already paid.
    public var progress: Double {
        guard debt.originalAmount > 0 else { return 0 }
        return min(1, NSDecimalNumber(decimal: paid / debt.originalAmount).doubleValue)
    }
    public var isOpen: Bool { status == .open || status == .partiallyPaid }
}

public enum DebtCalculator {
    public static func balance(of debt: Debt, payments: [DebtPayment], today: LocalDate) -> DebtBalance {
        let mine = payments.filter { $0.debtID == debt.id }
        let paid = mine.reduce(Decimal(0)) { $0 + $1.amount }
        let remaining = max(0, debt.originalAmount - paid)
        let status: DebtStatus
        if let closed = debt.closedStatus {
            status = closed
        } else if remaining == 0 {
            status = .paid
        } else if paid > 0 {
            status = .partiallyPaid
        } else {
            status = .open
        }
        let open = status == .open || status == .partiallyPaid
        let overdue = open && (debt.dueDate.map { $0 < today } ?? false)
        return DebtBalance(debt: debt, paid: paid, remaining: open ? remaining : 0, status: status, isOverdue: overdue,
                           lastPaymentDate: mine.map(\.date).max())
    }

    public static func balances(_ data: FinanceData, today: LocalDate) -> [DebtBalance] {
        data.debts.map { balance(of: $0, payments: data.debtPayments, today: today) }
    }

    /// Records a (possibly partial) payment.
    ///
    /// Creates **both** the payment row and a completed account transaction, so the real balance moves
    /// only when money actually arrives/leaves (scenario B). Receivable → income; payable → expense.
    public static func recordPayment(
        debtID: UUID, amount: Decimal, date: LocalDate, accountID: UUID, notes: String = "", in data: FinanceData, today: LocalDate
    ) throws -> (payment: DebtPayment, transaction: FinanceTransaction) {
        guard let debt = data.debt(debtID) else { throw ValidationError.unknownAccount }
        guard data.account(accountID) != nil else { throw ValidationError.unknownAccount }
        guard amount > 0 else { throw ValidationError.nonPositiveAmount }
        let bal = balance(of: debt, payments: data.debtPayments, today: today)
        guard bal.isOpen else { throw ValidationError.debtClosed }
        guard amount <= bal.remaining else { throw ValidationError.paymentExceedsRemaining(remaining: bal.remaining) }

        let contactName = data.contact(debt.contactID)?.name ?? ""
        let isReceivable = debt.direction == .receivable
        let who = contactName.isEmpty ? "" : (isReceivable ? " מ" : " ל") + contactName
        let title = "תשלום\(who): \(debt.title)"
        let tx = FinanceTransaction(
            kind: isReceivable ? .income : .expense, status: .completed, amount: amount, accountID: accountID,
            categoryID: nil, contactID: debt.contactID,
            title: title, date: date, eventID: debt.eventID, source: .debtPayment,
            excludedFromReports: !debt.countsAsIncomeOrExpense
        )
        let payment = DebtPayment(debtID: debt.id, amount: amount, date: date, transactionID: tx.id, notes: notes)
        return (payment, tx)
    }

    /// Payment collection rate for receivables issued in `range`: collected ÷ originally owed.
    public static func collectionRate(_ data: FinanceData, range: DateRange?) -> Double? {
        let rec = data.debts.filter { $0.direction == .receivable && $0.closedStatus != .cancelled && (range?.contains($0.issuedDate) ?? true) }
        let owed = rec.reduce(Decimal(0)) { $0 + $1.originalAmount }
        guard owed > 0 else { return nil }
        let ids = Set(rec.map(\.id))
        let collected = data.debtPayments.filter { ids.contains($0.debtID) }.reduce(Decimal(0)) { $0 + $1.amount }
        return NSDecimalNumber(decimal: collected / owed).doubleValue
    }
}

// MARK: - Events

public struct EventFinancials: Hashable, Sendable {
    public let event: FinanceEvent
    /// Income actually received for this event (completed linked transactions).
    public let receivedIncome: Decimal
    /// Expenses actually paid for this event.
    public let paidExpense: Decimal
    /// Expected income not yet covered by any linked (completed or pending) transaction.
    public let outstandingIncome: Decimal
    public let outstandingExpense: Decimal
    public let paymentStatus: EventPaymentStatus
}

public enum EventCalculator {
    public static func financials(of event: FinanceEvent, transactions: [FinanceTransaction]) -> EventFinancials {
        let linked = transactions.filter { $0.eventID == event.id && $0.status != .cancelled }
        let received = linked.filter { $0.kind == .income && $0.status == .completed }.reduce(Decimal(0)) { $0 + $1.amount }
        let incomeCovered = linked.filter { $0.kind == .income }.reduce(Decimal(0)) { $0 + $1.amount }
        let paidExp = linked.filter { $0.kind == .expense && $0.status == .completed }.reduce(Decimal(0)) { $0 + $1.amount }
        let expenseCovered = linked.filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
        let expectedIncome = event.expectedIncome ?? 0
        let expectedExpense = event.expectedExpense ?? 0
        let status: EventPaymentStatus
        if expectedIncome <= 0 {
            status = .none
        } else if received >= expectedIncome {
            status = .paid
        } else if received > 0 {
            status = .partiallyPaid
        } else {
            status = .unpaid
        }
        return EventFinancials(
            event: event, receivedIncome: received, paidExpense: paidExp,
            outstandingIncome: max(0, expectedIncome - incomeCovered),
            outstandingExpense: max(0, expectedExpense - expenseCovered),
            paymentStatus: status
        )
    }

    /// Payment status for an event, also considering payments on a linked receivable.
    public static func paymentStatus(of event: FinanceEvent, in data: FinanceData, today: LocalDate) -> EventPaymentStatus {
        if let debt = data.debt(event.debtID) {
            switch DebtCalculator.balance(of: debt, payments: data.debtPayments, today: today).status {
            case .paid, .writtenOff: return .paid
            case .partiallyPaid: return .partiallyPaid
            case .open: return .unpaid
            case .cancelled: return .none
            }
        }
        return financials(of: event, transactions: data.transactions).paymentStatus
    }
}
