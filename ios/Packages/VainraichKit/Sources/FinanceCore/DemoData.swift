import Foundation

/// Clearly-labelled demonstration data. `isDemo` is always true and the app shows a permanent
/// "מצב הדגמה" banner while it is loaded. Never mixed with the user's real data.
public enum DemoData {
    public static func make(today: LocalDate = .today()) -> FinanceData {
        let bank = Account(name: "עו״ש — הדגמה", type: .bank, institution: "בנק לדוגמה", openingBalance: 7_850, openingDate: today.adding(months: -3), sortOrder: 0)
        let cash = Account(name: "מזומן", type: .cash, openingBalance: 650, openingDate: today.adding(months: -3), sortOrder: 1)
        let bit = Account(name: "ביט", type: .bit, openingBalance: 200, openingDate: today.adding(months: -3), sortOrder: 2)
        let card = Account(name: "ויזה — הדגמה", type: .creditCard, institution: "חברת אשראי לדוגמה", openingBalance: 0,
                           openingDate: today.adding(months: -3), creditLimit: 15_000, billingDay: 10, paymentAccountID: bank.id, sortOrder: 3)
        let savings = Account(name: "חיסכון", type: .savings, openingBalance: 12_000, openingDate: today.adding(months: -3), sortOrder: 4)

        let daniel = Contact(name: "דניאל (הדגמה)")
        let david = Contact(name: "דוד (הדגמה)")
        let noa = Contact(name: "נועה (הדגמה)")

        let cat = DefaultCategories.self
        func e(_ i: Int) -> UUID { cat.expense[i].id }
        func inc(_ i: Int) -> UUID { cat.income[i].id }

        var tx: [FinanceTransaction] = []
        // Three months of history.
        for back in 0..<3 {
            let m = today.startOfMonth.adding(months: -back)
            func day(_ d: Int) -> LocalDate { LocalDate(year: m.year, month: m.month, day: d) }
            let ok: (LocalDate) -> Bool = { $0 <= today }
            let rows: [FinanceTransaction] = [
                FinanceTransaction(kind: .income, amount: 9_400, accountID: bank.id, categoryID: inc(0), title: "משכורת", date: day(1), paymentMethod: .bankTransfer, source: .demo),
                FinanceTransaction(kind: .expense, amount: 3_800, accountID: bank.id, categoryID: e(3), title: "שכר דירה", date: day(2), paymentMethod: .standingOrder, source: .demo),
                FinanceTransaction(kind: .expense, amount: 612.40, accountID: card.id, categoryID: e(0), title: "שופרסל", date: day(4), paymentMethod: .creditCard, source: .demo),
                FinanceTransaction(kind: .expense, amount: 289.90, accountID: card.id, categoryID: e(2), title: "דלק", date: day(7), paymentMethod: .creditCard, source: .demo),
                FinanceTransaction(kind: .expense, amount: 149, accountID: card.id, categoryID: e(5), title: "סלולר ואינטרנט", date: day(9), paymentMethod: .creditCard, source: .demo),
                FinanceTransaction(kind: .expense, amount: 96, accountID: cash.id, categoryID: e(1), title: "קפה ומאפה", date: day(12), paymentMethod: .cash, source: .demo),
                FinanceTransaction(kind: .income, amount: 1_200, accountID: bit.id, categoryID: inc(1), contactID: noa.id, title: "צילומי בר מצווה", date: day(14), paymentMethod: .bit, source: .demo),
                FinanceTransaction(kind: .transfer, amount: 1_000, accountID: bit.id, counterAccountID: bank.id, title: "העברה מביט לבנק", date: day(15), paymentMethod: .bit, source: .demo),
                FinanceTransaction(kind: .expense, amount: 438.70, accountID: card.id, categoryID: e(0), title: "רמי לוי", date: day(18), paymentMethod: .creditCard, source: .demo),
                FinanceTransaction(kind: .expense, amount: 320, accountID: bank.id, categoryID: e(4), title: "חשמל", date: day(20), paymentMethod: .standingOrder, source: .demo),
                FinanceTransaction(kind: .expense, amount: 180, accountID: card.id, categoryID: e(9), title: "קולנוע וארוחה", date: day(23), paymentMethod: .creditCard, source: .demo),
            ]
            tx.append(contentsOf: rows.filter { ok($0.date) })
            // Card bill for the previous month's purchases (transfer, not an expense).
            let bill = FinanceTransaction(kind: .transfer, amount: 1_670, accountID: bank.id, counterAccountID: card.id,
                                          title: "חיוב ויזה", date: day(10), paymentMethod: .bankTransfer, source: .demo)
            if back < 2 && ok(bill.date) { tx.append(bill) }
        }

        let wedding = FinanceEvent(title: "צילום חתונה", date: today.adding(days: 9), startTime: TimeOfDay(hour: 18, minute: 0),
                                   endTime: TimeOfDay(hour: 23, minute: 30), location: "אולם הגן, ראשון לציון", contactID: david.id,
                                   expectedIncome: 1_500, expectedExpense: 150, notes: "מקדמה עוד לא התקבלה")
        let shoot = FinanceEvent(title: "צילומי משפחה", date: today.adding(days: -5), startTime: TimeOfDay(hour: 16, minute: 0),
                                 location: "פארק הירקון", contactID: noa.id, expectedIncome: 800)
        let meeting = FinanceEvent(title: "פגישה עם רואה חשבון", date: today.adding(days: 3), startTime: TimeOfDay(hour: 10, minute: 0),
                                   expectedExpense: 350)
        // Event already paid in full.
        tx.append(FinanceTransaction(kind: .income, amount: 800, accountID: bit.id, categoryID: inc(1), contactID: noa.id, title: "צילומי משפחה",
                                     date: today.adding(days: -4), paymentMethod: .bit, eventID: shoot.id, source: .demo))

        let loan = Debt(direction: .receivable, contactID: daniel.id, title: "הלוואה לרכב", originalAmount: 2_000,
                        issuedDate: today.adding(months: -2), dueDate: today.adding(days: 20), countsAsIncomeOrExpense: false)
        let loanPaymentTx = FinanceTransaction(kind: .income, amount: 500, accountID: bank.id, contactID: daniel.id, title: "תשלום מדניאל: הלוואה לרכב",
                                               date: today.adding(days: -12), source: .debtPayment, excludedFromReports: true)
        tx.append(loanPaymentTx)
        let loanPayment = DebtPayment(debtID: loan.id, amount: 500, date: loanPaymentTx.date, transactionID: loanPaymentTx.id)
        let owed = Debt(direction: .payable, contactID: noa.id, title: "חלק בהשכרת ציוד", originalAmount: 450,
                        issuedDate: today.adding(days: -10), dueDate: today.adding(days: 6))
        let overdue = Debt(direction: .receivable, contactID: david.id, title: "יתרה מצילומי אירוסין", originalAmount: 700,
                           issuedDate: today.adding(months: -1), dueDate: today.adding(days: -7))

        let gym = RecurringRule(kind: .expense, amount: 100, accountID: card.id, categoryID: e(9), title: "מנוי חדר כושר",
                                frequency: .monthly, dayOfMonth: 15, startDate: today.adding(months: -2).startOfMonth, paymentMethod: .creditCard, autoPost: true)
        let rent = RecurringRule(kind: .expense, amount: 3_800, accountID: bank.id, categoryID: e(3), title: "שכר דירה",
                                 frequency: .monthly, dayOfMonth: 2, startDate: today.startOfMonth.adding(months: 1), paymentMethod: .standingOrder)
        let salary = RecurringRule(kind: .income, amount: 9_400, accountID: bank.id, categoryID: inc(0), title: "משכורת",
                                   frequency: .monthly, dayOfMonth: 1, startDate: today.startOfMonth.adding(months: 1), paymentMethod: .bankTransfer)

        var data = FinanceData(
            accounts: [bank, cash, bit, card, savings], transactions: tx, contacts: [daniel, david, noa],
            recurringRules: [gym, rent, salary], events: [wedding, shoot, meeting], debts: [loan, owed, overdue],
            debtPayments: [loanPayment], isDemo: true
        )
        data.transactions += RecurrenceEngine.materialize(rules: data.recurringRules, through: today, existing: data.transactions)
        return data
    }
}
