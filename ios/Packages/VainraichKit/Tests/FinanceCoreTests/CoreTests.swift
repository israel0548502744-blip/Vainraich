import XCTest
@testable import FinanceCore

final class LocalDateTests: XCTestCase {
    func testDayNumberRoundTrip() {
        for n in stride(from: -50_000, through: 50_000, by: 997) {
            XCTAssertEqual(LocalDate(dayNumber: n).dayNumber, n)
        }
        XCTAssertEqual(LocalDate(year: 1970, month: 1, day: 1).dayNumber, 0)
    }

    func testWeekday() {
        XCTAssertEqual(LocalDate(year: 2026, month: 11, day: 1).weekday, 1) // Sunday
        XCTAssertEqual(LocalDate(year: 2026, month: 11, day: 7).weekday, 7) // Saturday
        XCTAssertEqual(LocalDate(year: 2026, month: 11, day: 4).startOfWeek(), LocalDate(year: 2026, month: 11, day: 1))
    }

    func testAddMonthsClamps() {
        let jan31 = LocalDate(year: 2027, month: 1, day: 31)
        XCTAssertEqual(jan31.adding(months: 1), LocalDate(year: 2027, month: 2, day: 28))
        XCTAssertEqual(LocalDate(year: 2028, month: 1, day: 31).adding(months: 1), LocalDate(year: 2028, month: 2, day: 29))
        XCTAssertEqual(LocalDate(year: 2026, month: 1, day: 15).adding(months: -2), LocalDate(year: 2025, month: 11, day: 15))
    }

    func testParsingAndFormatting() {
        XCTAssertEqual(LocalDate(israeli: "15/12/2026"), LocalDate(year: 2026, month: 12, day: 15))
        XCTAssertEqual(LocalDate(israeli: "1.2.26"), LocalDate(year: 2026, month: 2, day: 1))
        XCTAssertNil(LocalDate(israeli: "31/02/2026"))
        XCTAssertEqual(LocalDate(iso: "2026-12-15")?.description, "15/12/2026")
        XCTAssertEqual(LocalDate(flexible: "2026-12-15"), LocalDate(flexible: "15/12/2026"))
    }
}

final class MoneyTests: XCTestCase {
    func testParseMoney() {
        XCTAssertEqual(Decimal.parseMoney("1,234.50"), Decimal(string: "1234.50"))
        XCTAssertEqual(Decimal.parseMoney("₪ 1,234"), 1234)
        XCTAssertEqual(Decimal.parseMoney("-120.00"), -120)
        XCTAssertEqual(Decimal.parseMoney("120.00-"), -120)
        XCTAssertEqual(Decimal.parseMoney("(99.90)"), Decimal(string: "-99.90"))
        XCTAssertEqual(Decimal.parseMoney("12,5"), Decimal(string: "12.5"))
        XCTAssertEqual(Decimal.parseMoney("1.234,56"), Decimal(string: "1234.56"))
        XCTAssertEqual(Decimal.parseMoney("0.1"), Decimal(string: "0.1"))
        XCTAssertNil(Decimal.parseMoney("abc"))
        XCTAssertNil(Decimal.parseMoney(""))
    }

    func testNoFloatingPointDrift() {
        var total: Decimal = 0
        for _ in 0..<10 { total += Decimal(string: "0.1")! }
        XCTAssertEqual(total, 1)
    }

    func testFormatting() {
        XCTAssertEqual(MoneyFormatter.format(1500), "₪1,500")
        XCTAssertEqual(MoneyFormatter.format(Decimal(string: "1234567.5")!), "₪1,234,567.50")
        XCTAssertEqual(MoneyFormatter.format(-300), "-₪300")
        XCTAssertEqual(MoneyFormatter.format(300, showPlus: true), "+₪300")
        XCTAssertEqual(MoneyFormatter.format(Decimal(string: "0.005")!), "₪0.01")
        XCTAssertEqual(MoneyFormatter.compact(12_500), "₪12.5K")
        XCTAssertEqual(Decimal(string: "1234.5")!.plainString, "1234.50")
        XCTAssertEqual(Decimal(-7).plainString, "-7.00")
    }

    func testDecimalStringCodableRoundTrip() throws {
        let t = FinanceTransaction(kind: .expense, amount: Decimal(string: "1234.56")!, accountID: UUID(), title: "x", date: LocalDate(year: 2026, month: 1, day: 1))
        let json = try JSONEncoder().encode(t)
        XCTAssertTrue(String(data: json, encoding: .utf8)!.contains("\"1234.56\""))
        let back = try JSONDecoder().decode(FinanceTransaction.self, from: json)
        XCTAssertEqual(back.amount, Decimal(string: "1234.56"))
    }
}

final class LedgerTests: XCTestCase {
    let today = LocalDate(year: 2026, month: 11, day: 2)

    func testPendingAndCancelledDoNotMoveBalance() {
        let bank = Account(name: "b", type: .bank, openingBalance: 100)
        let txs = [
            FinanceTransaction(kind: .expense, status: .pending, amount: 30, accountID: bank.id, title: "p", date: today),
            FinanceTransaction(kind: .expense, status: .cancelled, amount: 40, accountID: bank.id, title: "c", date: today),
            FinanceTransaction(kind: .income, amount: 10, accountID: bank.id, title: "i", date: today),
        ]
        XCTAssertEqual(Ledger.balance(of: bank, transactions: txs), 110)
    }

    func testAdjustmentAndTransfer() {
        let a = Account(name: "a", type: .bank, openingBalance: 100)
        let b = Account(name: "b", type: .savings, openingBalance: 0)
        let txs = [
            FinanceTransaction(kind: .transfer, amount: 40, accountID: a.id, counterAccountID: b.id, title: "t", date: today),
            FinanceTransaction(kind: .adjustment, amount: 5, adjustmentIsNegative: true, accountID: a.id, title: "adj", date: today),
        ]
        let bal = Ledger.balances(accounts: [a, b], transactions: txs)
        XCTAssertEqual(bal[a.id], 55)
        XCTAssertEqual(bal[b.id], 40)
        // Transfers and adjustments are not income or expense.
        let data = FinanceData(accounts: [a, b], transactions: txs)
        let s = SummaryCalculator.make(data: data, period: .month(containing: today), today: today)
        XCTAssertEqual(s.periodIncome, 0)
        XCTAssertEqual(s.periodExpenses, 0)
        XCTAssertEqual(s.available, 55, "Savings excluded from available by default")
        XCTAssertEqual(s.savings, 40)
    }

    func testValidation() {
        let a = Account(name: "a", type: .bank)
        let data = FinanceData(accounts: [a])
        XCTAssertThrowsError(try FinanceTransaction(kind: .expense, amount: 0, accountID: a.id, title: "x", date: today).validate(in: data))
        XCTAssertThrowsError(try FinanceTransaction(kind: .transfer, amount: 1, accountID: a.id, title: "x", date: today).validate(in: data))
        XCTAssertThrowsError(try FinanceTransaction(kind: .transfer, amount: 1, accountID: a.id, counterAccountID: a.id, title: "x", date: today).validate(in: data))
        XCTAssertThrowsError(try FinanceTransaction(kind: .income, amount: 1, accountID: a.id, categoryID: DefaultCategories.expense[0].id, title: "x", date: today).validate(in: data))
        XCTAssertNoThrow(try FinanceTransaction(kind: .income, amount: 1, accountID: a.id, categoryID: DefaultCategories.income[0].id, title: "x", date: today).validate(in: data))
    }

    func testInactiveAccountExcluded() {
        let a = Account(name: "a", type: .bank, openingBalance: 100, isActive: false)
        let b = Account(name: "b", type: .cash, openingBalance: 20)
        let s = SummaryCalculator.make(data: FinanceData(accounts: [a, b]), period: .day(today), today: today)
        XCTAssertEqual(s.available, 20)
    }
}

final class RecurrenceTests: XCTestCase {
    let acc = UUID()

    func testMonthlyLastDayClamping() {
        let r = RecurringRule(kind: .expense, amount: 1, accountID: acc, title: "x", frequency: .monthly, dayOfMonth: 31, startDate: LocalDate(year: 2027, month: 1, day: 1))
        let dates = RecurrenceEngine.occurrences(of: r, in: DateRange(start: LocalDate(year: 2027, month: 1, day: 1), end: LocalDate(year: 2027, month: 4, day: 30)))
        XCTAssertEqual(dates.map(\.description), ["31/01/2027", "28/02/2027", "31/03/2027", "30/04/2027"])
    }

    func testWeeklyWithWeekdaysAndInterval() {
        // Every two weeks on Sunday and Wednesday starting Sun 1/11/2026.
        let r = RecurringRule(kind: .expense, amount: 1, accountID: acc, title: "x", frequency: .weekly, interval: 2, weekdays: [1, 4],
                              startDate: LocalDate(year: 2026, month: 11, day: 1))
        let dates = RecurrenceEngine.occurrences(of: r, in: DateRange(start: LocalDate(year: 2026, month: 11, day: 1), end: LocalDate(year: 2026, month: 11, day: 30)))
        XCTAssertEqual(dates.map(\.day), [1, 4, 15, 18, 29])
    }

    func testEndDateAndMaxOccurrences() {
        let start = LocalDate(year: 2026, month: 1, day: 10)
        let r = RecurringRule(kind: .expense, amount: 1, accountID: acc, title: "x", frequency: .monthly, startDate: start, maxOccurrences: 3)
        let all = RecurrenceEngine.occurrences(of: r, in: DateRange(start: start, end: start.adding(years: 2)))
        XCTAssertEqual(all.count, 3)
        // Range starting after the first occurrences still respects the global count.
        let later = RecurrenceEngine.occurrences(of: r, in: DateRange(start: LocalDate(year: 2026, month: 3, day: 1), end: start.adding(years: 2)))
        XCTAssertEqual(later, [LocalDate(year: 2026, month: 3, day: 10)])

        let e = RecurringRule(kind: .expense, amount: 1, accountID: acc, title: "x", frequency: .daily, startDate: start, endDate: start.adding(days: 4))
        XCTAssertEqual(RecurrenceEngine.occurrences(of: e, in: DateRange(start: start, end: start.adding(days: 100))).count, 5)
    }

    func testYearlyLeapDay() {
        let r = RecurringRule(kind: .income, amount: 1, accountID: acc, title: "x", frequency: .yearly, startDate: LocalDate(year: 2028, month: 2, day: 29))
        let d = RecurrenceEngine.occurrences(of: r, in: DateRange(start: LocalDate(year: 2028, month: 1, day: 1), end: LocalDate(year: 2030, month: 12, day: 31)))
        XCTAssertEqual(d.map(\.description), ["29/02/2028", "28/02/2029", "28/02/2030"])
    }

    func testAutoPostMaterializesCompleted() {
        let r = RecurringRule(kind: .expense, amount: 50, accountID: acc, title: "x", frequency: .monthly, startDate: LocalDate(year: 2026, month: 9, day: 1), autoPost: true)
        let made = RecurrenceEngine.materialize(rules: [r], through: LocalDate(year: 2026, month: 11, day: 2), existing: [])
        XCTAssertEqual(made.count, 3)
        XCTAssertTrue(made.allSatisfy { $0.status == .completed && $0.recurringID == r.id })
        XCTAssertTrue(RecurrenceEngine.materialize(rules: [r], through: LocalDate(year: 2026, month: 11, day: 2), existing: made).isEmpty)
    }
}

final class ReportAndFilterTests: XCTestCase {
    let today = LocalDate(year: 2026, month: 11, day: 2)

    func testMonthlyReportExcludesTransfersAndLoans() {
        let bank = Account(name: "b", type: .bank)
        let card = Account(name: "c", type: .creditCard)
        let data = FinanceData(accounts: [bank, card], transactions: [
            FinanceTransaction(kind: .income, amount: 1000, accountID: bank.id, title: "salary", date: LocalDate(year: 2026, month: 10, day: 1)),
            FinanceTransaction(kind: .expense, amount: 200, accountID: card.id, title: "food", date: LocalDate(year: 2026, month: 10, day: 3)),
            FinanceTransaction(kind: .transfer, amount: 200, accountID: bank.id, counterAccountID: card.id, title: "bill", date: LocalDate(year: 2026, month: 10, day: 10)),
            FinanceTransaction(kind: .income, amount: 500, accountID: bank.id, title: "loan back", date: LocalDate(year: 2026, month: 10, day: 12), excludedFromReports: true),
        ])
        let months = ReportBuilder.monthly(data, endingAt: MonthKey(today), count: 2)
        XCTAssertEqual(months.map(\.month.month), [10, 11])
        XCTAssertEqual(months[0].income, 1000)
        XCTAssertEqual(months[0].expenses, 200)
        XCTAssertEqual(months[0].net, 800)
    }

    func testFilterAndSearch() {
        let bank = Account(name: "לאומי", type: .bank)
        let food = DefaultCategories.expense[0]
        let data = FinanceData(accounts: [bank], transactions: [
            FinanceTransaction(kind: .expense, amount: 50, accountID: bank.id, categoryID: food.id, title: "שופרסל דיל", date: today),
            FinanceTransaction(kind: .income, status: .pending, amount: 900, accountID: bank.id, title: "לקוח", date: today),
        ])
        XCTAssertEqual(TransactionFilter(searchText: "שופרסל").apply(to: data).count, 1)
        XCTAssertEqual(TransactionFilter(searchText: "מזון").apply(to: data).count, 1, "Search includes category name")
        XCTAssertEqual(TransactionFilter(statuses: [.pending]).apply(to: data).first?.title, "לקוח")
        XCTAssertEqual(TransactionFilter(categoryIDs: [food.id]).apply(to: data).count, 1)
        XCTAssertEqual(TransactionFilter(dateRange: .day(today.adding(days: 1))).apply(to: data).count, 0)
    }

    func testCSVEscapingAndBOM() {
        let bank = Account(name: "b", type: .bank)
        let data = FinanceData(accounts: [bank], transactions: [
            FinanceTransaction(kind: .expense, amount: 10, accountID: bank.id, title: "a, \"b\"", date: today),
        ])
        let csv = CSVExporter.transactions(data.transactions, data: data)
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
        XCTAssertTrue(csv.contains("\"a, \"\"b\"\"\""))
        XCTAssertTrue(csv.contains("-10.00"))
    }

    func testCollectionRate() {
        let c = Contact(name: "x")
        let d1 = Debt(direction: .receivable, contactID: c.id, title: "a", originalAmount: 1000)
        let data = FinanceData(contacts: [c], debts: [d1], debtPayments: [DebtPayment(debtID: d1.id, amount: 250, date: today)])
        XCTAssertEqual(DebtCalculator.collectionRate(data, range: nil)!, 0.25, accuracy: 0.0001)
    }

    func testOverdueReceivable() {
        let c = Contact(name: "x")
        let d = Debt(direction: .receivable, contactID: c.id, title: "a", originalAmount: 100, dueDate: today.adding(days: -1))
        XCTAssertTrue(DebtCalculator.balance(of: d, payments: [], today: today).isOverdue)
        var closed = d
        closed.closedStatus = .writtenOff
        let b = DebtCalculator.balance(of: closed, payments: [], today: today)
        XCTAssertFalse(b.isOverdue)
        XCTAssertEqual(b.remaining, 0)
    }
}

final class PersistenceAndDemoTests: XCTestCase {
    func testRoundTripDemoData() throws {
        let demo = DemoData.make(today: LocalDate(year: 2026, month: 11, day: 2))
        XCTAssertTrue(demo.isDemo)
        let data = try FinanceFileStore.encode(demo)
        let back = try FinanceFileStore.decode(data)
        XCTAssertEqual(back, demo)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = FinanceFileStore(url: dir.appendingPathComponent("finance.json"))
        try store.save(demo)
        XCTAssertEqual(try store.load(), demo)
        try store.delete()
        XCTAssertFalse(store.exists())
    }

    func testDemoDataIsConsistent() throws {
        let today = LocalDate(year: 2026, month: 11, day: 2)
        let demo = DemoData.make(today: today)
        for t in demo.transactions { XCTAssertNoThrow(try t.validate(in: demo), t.title) }
        let s = SummaryCalculator.make(data: demo, period: .month(containing: today), today: today)
        XCTAssertGreaterThan(s.available, 0)
        XCTAssertGreaterThan(s.receivablesOutstanding, 0)
    }
}
