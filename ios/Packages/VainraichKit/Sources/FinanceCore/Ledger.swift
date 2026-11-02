import Foundation

/// Pure balance arithmetic. All rules about what moves real money live here.
public enum Ledger {
    /// Signed effect of one transaction on one account, ignoring status.
    public static func effect(of t: FinanceTransaction, on accountID: UUID) -> Decimal {
        switch t.kind {
        case .income:
            return t.accountID == accountID ? t.amount : 0
        case .expense:
            return t.accountID == accountID ? -t.amount : 0
        case .transfer:
            var e: Decimal = 0
            if t.accountID == accountID { e -= t.amount }
            if t.counterAccountID == accountID { e += t.amount }
            return e
        case .adjustment:
            guard t.accountID == accountID else { return 0 }
            return t.adjustmentIsNegative ? -t.amount : t.amount
        }
    }

    /// Accounts whose balance a transaction touches.
    public static func touchedAccounts(_ t: FinanceTransaction) -> [UUID] {
        if t.kind == .transfer, let c = t.counterAccountID { return [t.accountID, c] }
        return [t.accountID]
    }

    /// Current balance: opening balance + every **completed** transaction.
    /// Pending transactions are expectations and never change the real balance.
    public static func balance(of account: Account, transactions: [FinanceTransaction]) -> Decimal {
        var total = account.openingBalance
        for t in transactions where t.status == .completed {
            total += effect(of: t, on: account.id)
        }
        return total
    }

    public static func balances(accounts: [Account], transactions: [FinanceTransaction]) -> [UUID: Decimal] {
        var result: [UUID: Decimal] = [:]
        for a in accounts { result[a.id] = a.openingBalance }
        for t in transactions where t.status == .completed {
            for id in touchedAccounts(t) where result[id] != nil {
                result[id, default: 0] += effect(of: t, on: id)
            }
        }
        return result
    }

    /// Effect of a transaction on the user's *available* money (sum over available accounts).
    public static func availableEffect(of t: FinanceTransaction, availableIDs: Set<UUID>) -> Decimal {
        touchedAccounts(t).filter { availableIDs.contains($0) }.reduce(Decimal(0)) { $0 + effect(of: t, on: $1) }
    }
}

// MARK: - Validation

public enum ValidationError: Error, Equatable, Sendable {
    case emptyTitle
    case nonPositiveAmount
    case unknownAccount
    case transferNeedsDestination
    case transferToSameAccount
    case categoryNotAllowedOnTransfer
    case categoryKindMismatch
    case currencyMismatch
    case recurringOccurrenceMismatch
    case paymentExceedsRemaining(remaining: Decimal)
    case debtClosed
    case eventTimeOrder
    case invalidBillingDay
}

public extension FinanceTransaction {
    func validate(in data: FinanceData) throws {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw ValidationError.emptyTitle }
        if amount <= 0 { throw ValidationError.nonPositiveAmount }
        guard let account = data.account(accountID) else { throw ValidationError.unknownAccount }
        switch kind {
        case .transfer:
            guard let dest = counterAccountID else { throw ValidationError.transferNeedsDestination }
            guard dest != accountID else { throw ValidationError.transferToSameAccount }
            guard let destAccount = data.account(dest) else { throw ValidationError.unknownAccount }
            if categoryID != nil { throw ValidationError.categoryNotAllowedOnTransfer }
            if destAccount.currency != account.currency { throw ValidationError.currencyMismatch }
        case .income, .expense:
            if let c = data.category(categoryID) {
                let expected: FinanceCategory.Kind = kind == .income ? .income : .expense
                if c.kind != expected { throw ValidationError.categoryKindMismatch }
            }
        case .adjustment:
            break
        }
        if (recurringID == nil) != (occurrenceDate == nil) { throw ValidationError.recurringOccurrenceMismatch }
    }
}

public extension Account {
    func validate() throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw ValidationError.emptyTitle }
        if let d = billingDay, !(1...31).contains(d) { throw ValidationError.invalidBillingDay }
    }
}

public extension FinanceEvent {
    func validate() throws {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw ValidationError.emptyTitle }
        if let i = expectedIncome, i < 0 { throw ValidationError.nonPositiveAmount }
        if let e = expectedExpense, e < 0 { throw ValidationError.nonPositiveAmount }
        if let s = startTime, let e = endTime, e < s { throw ValidationError.eventTimeOrder }
    }
}
