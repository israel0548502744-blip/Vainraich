import XCTest
@testable import FinanceCore

final class EventMatchingTests: XCTestCase {
    let today = LocalDate(year: 2026, month: 12, day: 20)
    let bank = Account(name: "בנק", type: .bank, openingBalance: 0, openingDate: LocalDate(year: 2026, month: 1, day: 1))

    func testKeywordDetection() {
        XCTAssertTrue(EventMatcher.looksLikeIncomeEvent("אירוע משפחת כהן"))
        XCTAssertTrue(EventMatcher.looksLikeIncomeEvent("צילום חתונה"))
        XCTAssertFalse(EventMatcher.looksLikeIncomeEvent("רופא שיניים"))
    }

    func testMatchesIncomeByAmountAndClientAndAsksForConfirmation() {
        let david = Contact(name: "דוד")
        let event = FinanceEvent(title: "צילום חתונה", date: LocalDate(year: 2026, month: 12, day: 15), contactID: david.id, expectedIncome: 1500)
        let pay = FinanceTransaction(kind: .income, amount: 1500, accountID: bank.id, title: "העברה מדוד", date: LocalDate(year: 2026, month: 12, day: 17))
        let unrelated = FinanceTransaction(kind: .income, amount: 9400, accountID: bank.id, title: "משכורת", date: LocalDate(year: 2026, month: 12, day: 16))
        let data = FinanceData(accounts: [bank], transactions: [pay, unrelated], contacts: [david], events: [event])

        let q = EventMatcher.questions(data: data, today: today)
        XCTAssertEqual(q.count, 1)
        XCTAssertEqual(q[0].kind, .possibleMatch)
        XCTAssertEqual(q[0].suggestions.map(\.transactionID), [pay.id], "Salary is not offered")
        XCTAssertTrue(q[0].suggestions[0].reasons.contains("אותו סכום שנותר לגבות"))
        // Nothing is linked automatically.
        XCTAssertNil(data.transactions.first { $0.id == pay.id }?.eventID)
    }

    func testEventWordWithoutAmountMatchesByWords() {
        let event = FinanceEvent(title: "אירוע בר מצווה לוי", date: LocalDate(year: 2026, month: 12, day: 10))
        let pay = FinanceTransaction(kind: .income, amount: 2000, accountID: bank.id, title: "ביט מלוי", date: LocalDate(year: 2026, month: 12, day: 11))
        let data = FinanceData(accounts: [bank], transactions: [pay], events: [event])
        let q = EventMatcher.questions(data: data, today: today)
        XCTAssertEqual(q.first?.kind, .possibleMatch)
        XCTAssertEqual(q.first?.suggestions.first?.transactionID, pay.id)
    }

    func testPastEventWithoutIncomeAsksIfPaid() {
        let event = FinanceEvent(title: "אירוע בגן אירועים", date: LocalDate(year: 2026, month: 12, day: 1))
        let data = FinanceData(accounts: [bank], events: [event])
        XCTAssertEqual(EventMatcher.questions(data: data, today: today).first?.kind, .unknownIfPaid)

        var answeredNo = event
        answeredNo.isIncomeEvent = false
        XCTAssertTrue(EventMatcher.questions(data: FinanceData(accounts: [bank], events: [answeredNo]), today: today).isEmpty)

        // Future event is not asked about yet.
        let future = FinanceEvent(title: "אירוע", date: today.adding(days: 5))
        XCTAssertTrue(EventMatcher.questions(data: FinanceData(accounts: [bank], events: [future]), today: today).isEmpty)
        // Non-event appointments are never asked about.
        let dentist = FinanceEvent(title: "רופא שיניים", date: LocalDate(year: 2026, month: 12, day: 1))
        XCTAssertTrue(EventMatcher.questions(data: FinanceData(accounts: [bank], events: [dentist]), today: today).isEmpty)
    }

    func testUnpaidAfterEventAndRejection() {
        let event = FinanceEvent(title: "אירוע חברה", date: LocalDate(year: 2026, month: 12, day: 5), expectedIncome: 3000)
        let pay = FinanceTransaction(kind: .income, amount: 3000, accountID: bank.id, title: "תשלום", date: LocalDate(year: 2026, month: 12, day: 8))
        var data = FinanceData(accounts: [bank], transactions: [pay], events: [event])
        XCTAssertEqual(EventMatcher.questions(data: data, today: today).first?.kind, .possibleMatch)

        // User says "this is not the payment" → never suggested again, back to asking whether it was paid.
        data.events[0].rejectedTransactionIDs = [pay.id]
        let q = EventMatcher.questions(data: data, today: today)
        XCTAssertEqual(q.first?.kind, .unpaidAfterEvent)
        XCTAssertEqual(q.first?.outstanding, 3000)

        // Once linked and paid in full, nothing is asked.
        data.events[0].rejectedTransactionIDs = nil
        data.transactions[0].eventID = event.id
        XCTAssertTrue(EventMatcher.questions(data: data, today: today).isEmpty)
    }

    func testTransactionOfferedForBestEventOnly() {
        let c = Contact(name: "נועה")
        let e1 = FinanceEvent(title: "צילומי משפחה", date: LocalDate(year: 2026, month: 12, day: 1), contactID: c.id, expectedIncome: 800)
        let e2 = FinanceEvent(title: "אירוע אחר", date: LocalDate(year: 2026, month: 12, day: 2), expectedIncome: 800)
        let pay = FinanceTransaction(kind: .income, amount: 800, accountID: bank.id, contactID: c.id, title: "נועה", date: LocalDate(year: 2026, month: 12, day: 3))
        let data = FinanceData(accounts: [bank], transactions: [pay], contacts: [c], events: [e1, e2])
        let s = EventMatcher.suggestions(data: data, today: today)
        XCTAssertEqual(s[e1.id]?.count, 1)
        XCTAssertNil(s[e2.id])
    }

    func testOldDataWithoutNewFieldsStillDecodes() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"x","date":"2026-12-01","location":"","notes":""}"#
        let e = try JSONDecoder().decode(FinanceEvent.self, from: Data(json.utf8))
        XCTAssertNil(e.isIncomeEvent)
        XCTAssertNil(e.rejectedTransactionIDs)
    }
}
