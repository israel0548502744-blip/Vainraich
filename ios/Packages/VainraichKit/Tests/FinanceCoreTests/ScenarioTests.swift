import XCTest
@testable import FinanceCore

/// The five acceptance scenarios from the product spec (§9).
final class ScenarioTests: XCTestCase {
    let today = LocalDate(year: 2026, month: 11, day: 2)

    // Scenario A: bank 5,000 + cash 500 + Bit 200; expected income 1,500 and expenses 700.
    func testScenarioA_availableAndProjected() {
        let bank = Account(name: "בנק", type: .bank, openingBalance: 5_000, openingDate: today)
        let cash = Account(name: "מזומן", type: .cash, openingBalance: 500, openingDate: today)
        let bit = Account(name: "ביט", type: .bit, openingBalance: 200, openingDate: today)
        let data = FinanceData(accounts: [bank, cash, bit], transactions: [
            FinanceTransaction(kind: .income, status: .pending, amount: 1_500, accountID: bank.id, title: "הכנסה צפויה", date: today.adding(days: 5)),
            FinanceTransaction(kind: .expense, status: .pending, amount: 700, accountID: bank.id, title: "הוצאה צפויה", date: today.adding(days: 10)),
        ])
        let s = SummaryCalculator.make(data: data, period: .month(containing: today), today: today)
        XCTAssertEqual(s.available, 5_700)
        XCTAssertEqual(s.expectedIncome, 1_500)
        XCTAssertEqual(s.expectedExpenses, 700)
        XCTAssertEqual(s.projectedBalance, 6_500)
        // Expected money is never part of the actual balance.
        XCTAssertEqual(s.periodIncome, 0)
    }

    // Scenario B: someone owes 2,000 and pays 500.
    func testScenarioB_partialReceivablePayment() throws {
        let bank = Account(name: "בנק", type: .bank, openingBalance: 1_000, openingDate: today)
        let daniel = Contact(name: "דניאל")
        let debt = Debt(direction: .receivable, contactID: daniel.id, title: "הלוואה", originalAmount: 2_000, issuedDate: today, dueDate: today.adding(days: 30))
        var data = FinanceData(accounts: [bank], contacts: [daniel], debts: [debt])

        // Before payment: receivable is not money the user has.
        var s = SummaryCalculator.make(data: data, period: .month(containing: today), today: today)
        XCTAssertEqual(s.available, 1_000)
        XCTAssertEqual(s.receivablesOutstanding, 2_000)

        let (payment, tx) = try DebtCalculator.recordPayment(debtID: debt.id, amount: 500, date: today, accountID: bank.id, in: data, today: today)
        data.debtPayments.append(payment)
        data.transactions.append(tx)

        let bal = DebtCalculator.balance(of: debt, payments: data.debtPayments, today: today)
        XCTAssertEqual(bal.remaining, 1_500)
        XCTAssertEqual(bal.status, .partiallyPaid)
        s = SummaryCalculator.make(data: data, period: .month(containing: today), today: today)
        XCTAssertEqual(s.available, 1_500, "Actual balance grows only by the money actually received")
        XCTAssertEqual(s.receivablesOutstanding, 1_500)
    }

    func testScenarioB_overpaymentRejected() throws {
        let bank = Account(name: "בנק", type: .bank)
        let c = Contact(name: "x")
        let debt = Debt(direction: .receivable, contactID: c.id, title: "t", originalAmount: 100)
        let data = FinanceData(accounts: [bank], contacts: [c], debts: [debt])
        XCTAssertThrowsError(try DebtCalculator.recordPayment(debtID: debt.id, amount: 150, date: today, accountID: bank.id, in: data, today: today)) {
            XCTAssertEqual($0 as? ValidationError, .paymentExceedsRemaining(remaining: 100))
        }
    }

    // Scenario C: credit-card purchase of 300, then paying the bill.
    func testScenarioC_creditCardNoDoubleCounting() {
        let bank = Account(name: "בנק", type: .bank, openingBalance: 5_000, openingDate: today)
        let card = Account(name: "ויזה", type: .creditCard, openingBalance: 0, openingDate: today, billingDay: 10, paymentAccountID: bank.id)
        var data = FinanceData(accounts: [bank, card])
        data.transactions.append(FinanceTransaction(kind: .expense, amount: 300, accountID: card.id, categoryID: DefaultCategories.expense[0].id,
                                                    title: "סופר", date: today))
        var s = SummaryCalculator.make(data: data, period: .month(containing: today), today: today)
        XCTAssertEqual(s.periodExpenses, 300, "Purchase is an expense")
        XCTAssertEqual(s.creditCardLiability, 300, "…and a card liability")
        XCTAssertEqual(s.available, 5_000, "…but does not reduce the bank yet")
        // The forecast shows the bill on billing day, paid from the bank.
        let bill = s.forecast.items.first { if case .creditCardBill = $0.source { return true } else { return false } }
        XCTAssertEqual(bill?.amount, -300)
        XCTAssertEqual(bill?.date, LocalDate(year: 2026, month: 11, day: 10))

        // Pay the bill: a transfer, not an expense.
        data.transactions.append(FinanceTransaction(kind: .transfer, amount: 300, accountID: bank.id, counterAccountID: card.id,
                                                    title: "חיוב ויזה", date: today))
        s = SummaryCalculator.make(data: data, period: .month(containing: today), today: today)
        XCTAssertEqual(s.available, 4_700)
        XCTAssertEqual(s.creditCardLiability, 0)
        XCTAssertEqual(s.periodExpenses, 300, "Expense recorded once, not twice")
        XCTAssertFalse(s.forecast.items.contains { if case .creditCardBill = $0.source { return true } else { return false } })
    }

    // Scenario D: monthly recurring expense of 100.
    func testScenarioD_recurringNoDuplicates() {
        let bank = Account(name: "בנק", type: .bank, openingBalance: 1_000, openingDate: today.adding(months: -3))
        let rule = RecurringRule(kind: .expense, amount: 100, accountID: bank.id, title: "מנוי", frequency: .monthly, dayOfMonth: 5,
                                 startDate: LocalDate(year: 2026, month: 9, day: 1))
        var data = FinanceData(accounts: [bank], recurringRules: [rule])

        // Sep 5 and Oct 5 already paid.
        for m in [9, 10] {
            data.transactions.append(RecurrenceEngine.makeTransaction(for: rule, on: LocalDate(year: 2026, month: m, day: 5), status: .completed))
        }
        // Materializing again must not duplicate them.
        let created = RecurrenceEngine.materialize(rules: [rule], through: today, existing: data.transactions)
        XCTAssertTrue(created.isEmpty)

        let f = ForecastEngine.make(data: data, range: DateRange(start: today, end: LocalDate(year: 2027, month: 1, day: 31)), today: today)
        let recurring = f.items.filter { if case .recurring = $0.source { return true } else { return false } }
        XCTAssertEqual(recurring.map(\.date), [LocalDate(year: 2026, month: 11, day: 5), LocalDate(year: 2026, month: 12, day: 5), LocalDate(year: 2027, month: 1, day: 5)])
        XCTAssertTrue(recurring.allSatisfy { $0.amount == -100 })
        XCTAssertEqual(f.endingBalance, 800 - 300)

        // Once November is recorded (even as pending) it is counted once only.
        data.transactions.append(RecurrenceEngine.makeTransaction(for: rule, on: LocalDate(year: 2026, month: 11, day: 5), status: .pending))
        let f2 = ForecastEngine.make(data: data, range: DateRange(start: today, end: LocalDate(year: 2027, month: 1, day: 31)), today: today)
        XCTAssertEqual(f2.items.filter { $0.amount == -100 }.count, 3)
        XCTAssertEqual(f2.endingBalance, 500)
    }

    // Scenario E: event with expected income 1,500, unpaid.
    func testScenarioE_unpaidEventInForecastOnly() {
        let bank = Account(name: "בנק", type: .bank, openingBalance: 2_000, openingDate: today)
        let event = FinanceEvent(title: "צילום חתונה", date: today.adding(days: 13), expectedIncome: 1_500)
        var data = FinanceData(accounts: [bank], events: [event])
        var s = SummaryCalculator.make(data: data, period: .next(30, from: today), today: today)
        XCTAssertEqual(s.available, 2_000)
        XCTAssertEqual(s.expectedIncome, 1_500)
        XCTAssertEqual(s.projectedBalance, 3_500)
        XCTAssertEqual(EventCalculator.financials(of: event, transactions: data.transactions).paymentStatus, .unpaid)

        // Paid 1,000 so far → only 500 remains expected; actual grows by 1,000.
        data.transactions.append(FinanceTransaction(kind: .income, amount: 1_000, accountID: bank.id, title: "מקדמה", date: today, eventID: event.id))
        s = SummaryCalculator.make(data: data, period: .next(30, from: today), today: today)
        XCTAssertEqual(s.available, 3_000)
        XCTAssertEqual(s.expectedIncome, 500)
        XCTAssertEqual(s.projectedBalance, 3_500)
        XCTAssertEqual(EventCalculator.financials(of: event, transactions: data.transactions).paymentStatus, .partiallyPaid)
    }

    func testEventWithReceivableCountedOnce() {
        let bank = Account(name: "בנק", type: .bank, openingBalance: 0, openingDate: today)
        let david = Contact(name: "דוד")
        var event = FinanceEvent(title: "חתונה", date: today.adding(days: 5), contactID: david.id, expectedIncome: 1_500)
        let debt = Debt(direction: .receivable, contactID: david.id, title: "חתונה", originalAmount: 1_500, dueDate: today.adding(days: 7), eventID: event.id)
        event.debtID = debt.id
        let data = FinanceData(accounts: [bank], contacts: [david], events: [event], debts: [debt])
        let f = ForecastEngine.make(data: data, range: .next(30, from: today), today: today)
        XCTAssertEqual(f.expectedIncome, 1_500)
        XCTAssertEqual(f.items.count, 1)
        XCTAssertEqual(f.items.first?.confidence, .estimated)
        // Excluding receivables removes it entirely.
        let f2 = ForecastEngine.make(data: data, range: .next(30, from: today), today: today, options: ForecastOptions(includeReceivables: false))
        XCTAssertEqual(f2.expectedIncome, 0)
    }

    func testNegativeBalanceWarning() {
        let bank = Account(name: "בנק", type: .bank, openingBalance: 500, openingDate: today)
        let data = FinanceData(accounts: [bank], transactions: [
            FinanceTransaction(kind: .expense, status: .pending, amount: 800, accountID: bank.id, title: "שכר דירה", date: today.adding(days: 3)),
            FinanceTransaction(kind: .income, status: .pending, amount: 1_000, accountID: bank.id, title: "משכורת", date: today.adding(days: 8)),
        ])
        let f = ForecastEngine.make(data: data, range: .next(30, from: today), today: today)
        XCTAssertEqual(f.firstNegativeDay?.date, today.adding(days: 3))
        XCTAssertEqual(f.lowestDay?.projectedBalance, -300)
        XCTAssertEqual(f.endingBalance, 700)
    }

    func testOverduePendingAppearsOnFirstDay() {
        let bank = Account(name: "בנק", type: .bank, openingBalance: 100, openingDate: today.adding(days: -30))
        let data = FinanceData(accounts: [bank], transactions: [
            FinanceTransaction(kind: .expense, status: .pending, amount: 50, accountID: bank.id, title: "חוב ישן", date: today.adding(days: -10)),
        ])
        let f = ForecastEngine.make(data: data, range: .next(7, from: today), today: today)
        XCTAssertEqual(f.items.first?.date, today)
        XCTAssertEqual(f.items.first?.isOverdue, true)
        XCTAssertEqual(f.days.first?.projectedBalance, 50)
    }
}
