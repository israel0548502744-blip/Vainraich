package com.vainraich.core

import org.junit.Test
import java.time.LocalDate
import kotlin.test.*

class ScenarioTest {
    private val today = LocalDate.of(2026, 11, 2)

    @Test fun scenarioA_availableAndProjected() {
        val bank = Account(name = "בנק", type = AccountType.BANK, openingBalance = money(5000), openingDate = today)
        val cash = Account(name = "מזומן", type = AccountType.CASH, openingBalance = money(500), openingDate = today)
        val bit = Account(name = "ביט", type = AccountType.BIT, openingBalance = money(200), openingDate = today)
        val data = FinanceData(accounts = listOf(bank, cash, bit), transactions = listOf(
            Transaction(kind = TxKind.INCOME, status = TxStatus.PENDING, amount = money(1500), accountId = bank.id, title = "x", date = today.plusDays(5)),
            Transaction(kind = TxKind.EXPENSE, status = TxStatus.PENDING, amount = money(700), accountId = bank.id, title = "y", date = today.plusDays(10)),
        ))
        val s = SummaryCalculator.make(data, DateRange.month(today), today)
        assertEquals(money(5700), s.available)
        assertEquals(money(1500), s.expectedIncome)
        assertEquals(money(700), s.expectedExpenses)
        assertEquals(money(6500), s.projected)
        assertEquals(ZERO, s.periodIncome)
    }

    @Test fun scenarioB_partialPayment() {
        val bank = Account(name = "בנק", type = AccountType.BANK, openingBalance = money(1000), openingDate = today)
        val c = Contact(name = "דניאל")
        val debt = Debt(direction = DebtDirection.RECEIVABLE, contactId = c.id, title = "הלוואה", originalAmount = money(2000), issuedDate = today, dueDate = today.plusDays(30))
        var data = FinanceData(accounts = listOf(bank), contacts = listOf(c), debts = listOf(debt))
        assertEquals(money(1000), SummaryCalculator.make(data, DateRange.month(today), today).available)
        val (p, tx) = Debts.recordPayment(debt.id, money(500), today, bank.id, "", data, today)
        data = data.copy(debtPayments = listOf(p), transactions = listOf(tx))
        val b = Debts.balance(debt, data.debtPayments, today)
        assertEquals(money(1500), b.remaining)
        assertEquals(DebtStatus.PARTIALLY_PAID, b.status)
        val s = SummaryCalculator.make(data, DateRange.month(today), today)
        assertEquals(money(1500), s.available)
        assertEquals(money(1500), s.receivables)
        assertFailsWith<ValidationError.PaymentExceedsRemaining> { Debts.recordPayment(debt.id, money(1600), today, bank.id, "", data, today) }
    }

    @Test fun scenarioC_creditCard() {
        val bank = Account(name = "בנק", type = AccountType.BANK, openingBalance = money(5000), openingDate = today)
        val card = Account(name = "ויזה", type = AccountType.CREDIT_CARD, openingDate = today, billingDay = 10, paymentAccountId = bank.id)
        var data = FinanceData(accounts = listOf(bank, card), transactions = listOf(
            Transaction(kind = TxKind.EXPENSE, amount = money(300), accountId = card.id, categoryId = "e01", title = "סופר", date = today)))
        var s = SummaryCalculator.make(data, DateRange.month(today), today)
        assertEquals(money(300), s.periodExpenses)
        assertEquals(money(300), s.creditCardLiability)
        assertEquals(money(5000), s.available)
        val bill = s.forecast.items.first { it.source is ForecastSource.CardBill }
        assertEquals(money(-300), bill.amount)
        assertEquals(LocalDate.of(2026, 11, 10), bill.date)
        data = data.copy(transactions = data.transactions + Transaction(kind = TxKind.TRANSFER, amount = money(300), accountId = bank.id, counterAccountId = card.id, title = "חיוב", date = today))
        s = SummaryCalculator.make(data, DateRange.month(today), today)
        assertEquals(money(4700), s.available)
        assertEquals(ZERO, s.creditCardLiability)
        assertEquals(money(300), s.periodExpenses)
        assertTrue(s.forecast.items.none { it.source is ForecastSource.CardBill })
    }

    @Test fun scenarioD_recurringNoDuplicates() {
        val bank = Account(name = "בנק", type = AccountType.BANK, openingBalance = money(1000), openingDate = today.minusMonths(3))
        val rule = RecurringRule(kind = TxKind.EXPENSE, amount = money(100), accountId = bank.id, title = "מנוי", frequency = Frequency.MONTHLY, dayOfMonth = 5, startDate = LocalDate.of(2026, 9, 1))
        val paid = listOf(9, 10).map { Recurrence.makeTransaction(rule, LocalDate.of(2026, it, 5), TxStatus.COMPLETED) }
        var data = FinanceData(accounts = listOf(bank), recurringRules = listOf(rule), transactions = paid)
        assertTrue(Recurrence.materialize(listOf(rule), today, data.transactions).isEmpty())
        val f = ForecastEngine.make(data, DateRange(today, LocalDate.of(2027, 1, 31)), today)
        assertEquals(listOf(LocalDate.of(2026, 11, 5), LocalDate.of(2026, 12, 5), LocalDate.of(2027, 1, 5)), f.items.filter { it.source is ForecastSource.Recurring }.map { it.date })
        assertEquals(money(500), f.ending)
        data = data.copy(transactions = data.transactions + Recurrence.makeTransaction(rule, LocalDate.of(2026, 11, 5), TxStatus.PENDING))
        val f2 = ForecastEngine.make(data, DateRange(today, LocalDate.of(2027, 1, 31)), today)
        assertEquals(3, f2.items.count { it.amount == money(-100) })
        assertEquals(money(500), f2.ending)
    }

    @Test fun scenarioE_unpaidEventForecastOnly() {
        val bank = Account(name = "בנק", type = AccountType.BANK, openingBalance = money(2000), openingDate = today)
        val e = FinanceEvent(title = "צילום חתונה", date = today.plusDays(13), expectedIncome = money(1500))
        var data = FinanceData(accounts = listOf(bank), events = listOf(e))
        var s = SummaryCalculator.make(data, DateRange.next(30, today), today)
        assertEquals(money(2000), s.available)
        assertEquals(money(3500), s.projected)
        data = data.copy(transactions = listOf(Transaction(kind = TxKind.INCOME, amount = money(1000), accountId = bank.id, title = "מקדמה", date = today, eventId = e.id)))
        s = SummaryCalculator.make(data, DateRange.next(30, today), today)
        assertEquals(money(3000), s.available)
        assertEquals(money(500), s.expectedIncome)
        assertEquals(money(3500), s.projected)
    }

    @Test fun futureStartRuleNotMaterialized() {
        val bank = Account(name = "b", type = AccountType.BANK, openingDate = today)
        val r = RecurringRule(kind = TxKind.INCOME, amount = money(9400), accountId = bank.id, title = "משכורת", frequency = Frequency.MONTHLY, dayOfMonth = 1, startDate = LocalDate.of(2026, 12, 1))
        assertTrue(Recurrence.materialize(listOf(r), today, emptyList()).isEmpty())
        val data = FinanceData(accounts = listOf(bank), recurringRules = listOf(r))
        assertTrue(ForecastEngine.make(data, DateRange.next(20, today), today).items.isEmpty())
        assertEquals(1, ForecastEngine.make(data, DateRange.next(40, today), today).items.size)
    }

    @Test fun negativeWarning() {
        val bank = Account(name = "b", type = AccountType.BANK, openingBalance = money(500), openingDate = today)
        val data = FinanceData(accounts = listOf(bank), transactions = listOf(
            Transaction(kind = TxKind.EXPENSE, status = TxStatus.PENDING, amount = money(800), accountId = bank.id, title = "a", date = today.plusDays(3)),
            Transaction(kind = TxKind.INCOME, status = TxStatus.PENDING, amount = money(1000), accountId = bank.id, title = "b", date = today.plusDays(8))))
        val f = ForecastEngine.make(data, DateRange.next(30, today), today)
        assertEquals(today.plusDays(3), f.firstNegativeDay?.date)
        assertEquals(money(-300), f.lowestDay?.projected)
    }
}

class CoreTest {
    private val today = LocalDate.of(2026, 11, 2)

    @Test fun moneyParsing() {
        assertEquals(money("1234.50"), MoneyText.parse("1,234.50"))
        assertEquals(money(1234), MoneyText.parse("₪ 1,234"))
        assertEquals(money(-120), MoneyText.parse("120.00-"))
        assertEquals(money("-99.90"), MoneyText.parse("(99.90)"))
        assertEquals(money("12.5"), MoneyText.parse("12,5"))
        assertEquals(money("1234.56"), MoneyText.parse("1.234,56"))
        assertNull(MoneyText.parse("abc"))
    }

    @Test fun moneyFormatting() {
        assertEquals("₪1,500", MoneyFormatter.format(money(1500)))
        assertEquals("₪1,234,567.50", MoneyFormatter.format(money("1234567.5")))
        assertEquals("-₪300", MoneyFormatter.format(money(-300)))
        assertEquals("+₪300", MoneyFormatter.format(money(300), showPlus = true))
        assertEquals("₪12.5K", MoneyFormatter.compact(money(12500)))
    }

    @Test fun dates() {
        assertEquals(LocalDate.of(2026, 12, 15), DateText.israeli("15/12/26"))
        assertNull(DateText.israeli("31/02/2026"))
        assertEquals(1, LocalDate.of(2026, 11, 1).weekdaySun1)
        assertEquals("15/12/2026", LocalDate.of(2026, 12, 15).il)
    }

    @Test fun recurrenceRules() {
        val r = RecurringRule(kind = TxKind.EXPENSE, amount = money(1), accountId = "a", title = "x", frequency = Frequency.MONTHLY, dayOfMonth = 31, startDate = LocalDate.of(2027, 1, 1))
        assertEquals(listOf(31, 28, 31, 30), Recurrence.occurrences(r, DateRange(LocalDate.of(2027, 1, 1), LocalDate.of(2027, 4, 30))).map { it.dayOfMonth })
        val w = RecurringRule(kind = TxKind.EXPENSE, amount = money(1), accountId = "a", title = "x", frequency = Frequency.WEEKLY, interval = 2, weekdays = listOf(1, 4), startDate = LocalDate.of(2026, 11, 1))
        assertEquals(listOf(1, 4, 15, 18, 29), Recurrence.occurrences(w, DateRange(LocalDate.of(2026, 11, 1), LocalDate.of(2026, 11, 30))).map { it.dayOfMonth })
        val m = RecurringRule(kind = TxKind.EXPENSE, amount = money(1), accountId = "a", title = "x", frequency = Frequency.MONTHLY, startDate = LocalDate.of(2026, 1, 10), maxOccurrences = 3)
        assertEquals(listOf(LocalDate.of(2026, 3, 10)), Recurrence.occurrences(m, DateRange(LocalDate.of(2026, 3, 1), LocalDate.of(2028, 1, 1))))
    }

    @Test fun transfersAndAdjustmentsNotIncome() {
        val a = Account(name = "a", type = AccountType.BANK, openingBalance = money(100), openingDate = today)
        val b = Account(name = "b", type = AccountType.SAVINGS, openingDate = today)
        val data = FinanceData(accounts = listOf(a, b), transactions = listOf(
            Transaction(kind = TxKind.TRANSFER, amount = money(40), accountId = a.id, counterAccountId = b.id, title = "t", date = today),
            Transaction(kind = TxKind.ADJUSTMENT, amount = money(5), adjustmentIsNegative = true, accountId = a.id, title = "adj", date = today)))
        val s = SummaryCalculator.make(data, DateRange.month(today), today)
        assertEquals(money(55), s.available)
        assertEquals(money(40), s.savings)
        assertEquals(ZERO, s.periodIncome)
    }

    @Test fun validation() {
        val a = Account(name = "a", type = AccountType.BANK)
        val d = FinanceData(accounts = listOf(a))
        assertFails { Transaction(kind = TxKind.EXPENSE, amount = ZERO, accountId = a.id, title = "x", date = today).validate(d) }
        assertFails { Transaction(kind = TxKind.TRANSFER, amount = money(1), accountId = a.id, title = "x", date = today).validate(d) }
        assertFails { Transaction(kind = TxKind.INCOME, amount = money(1), accountId = a.id, categoryId = "e01", title = "x", date = today).validate(d) }
    }

    @Test fun jsonRoundTripAndDemo() {
        val demo = DemoData.make(today)
        assertTrue(demo.isDemo)
        val back = FinanceJson.decode(FinanceJson.encode(demo))
        assertEquals(demo, back)
        assertTrue(FinanceJson.encode(demo).contains("\"amount\": \"9400.00\""))
        for (t in demo.transactions) t.validate(demo)
        // Old files without new fields still load.
        val minimal = """{"accounts":[{"id":"x","name":"n","type":"bank"}]}"""
        assertEquals("n", FinanceJson.decode(minimal).accounts.first().name)
    }

    @Test fun filterAndCsv() {
        val bank = Account(name = "לאומי", type = AccountType.BANK)
        val data = FinanceData(accounts = listOf(bank), transactions = listOf(
            Transaction(kind = TxKind.EXPENSE, amount = money(50), accountId = bank.id, categoryId = "e01", title = "שופרסל, \"דיל\"", date = today)))
        assertEquals(1, TxFilter(search = "מזון").apply(data).size)
        val csv = Csv.transactions(data.transactions, data)
        assertTrue(csv.startsWith("﻿"))
        assertTrue(csv.contains("-50.00"))
        assertTrue(csv.contains("\"שופרסל, \"\"דיל\"\"\""))
    }
}

class EventMatchingTest {
    private val today = LocalDate.of(2026, 12, 20)
    private val bank = Account(name = "בנק", type = AccountType.BANK, openingDate = LocalDate.of(2026, 1, 1))

    @Test fun matchByAmountAndClient() {
        val david = Contact(name = "דוד")
        val e = FinanceEvent(title = "צילום חתונה", date = LocalDate.of(2026, 12, 15), contactId = david.id, expectedIncome = money(1500))
        val pay = Transaction(kind = TxKind.INCOME, amount = money(1500), accountId = bank.id, title = "העברה מדוד", date = LocalDate.of(2026, 12, 17))
        val salary = Transaction(kind = TxKind.INCOME, amount = money(9400), accountId = bank.id, title = "משכורת", date = LocalDate.of(2026, 12, 16))
        val q = EventMatcher.questions(FinanceData(accounts = listOf(bank), transactions = listOf(pay, salary), contacts = listOf(david), events = listOf(e)), today)
        assertEquals(1, q.size)
        assertEquals(PaymentQuestion.Kind.POSSIBLE_MATCH, q[0].kind)
        assertEquals(listOf(pay.id), q[0].suggestions.map { it.transactionId })
    }

    @Test fun eventWordWithHebrewPrefix() {
        val e = FinanceEvent(title = "אירוע בר מצווה לוי", date = LocalDate.of(2026, 12, 10))
        val pay = Transaction(kind = TxKind.INCOME, amount = money(2000), accountId = bank.id, title = "ביט מלוי", date = LocalDate.of(2026, 12, 11))
        val q = EventMatcher.questions(FinanceData(accounts = listOf(bank), transactions = listOf(pay), events = listOf(e)), today)
        assertEquals(pay.id, q.first().suggestions.first().transactionId)
    }

    @Test fun askAndRejectAndAnswerNo() {
        val e = FinanceEvent(title = "אירוע בגן", date = LocalDate.of(2026, 12, 1))
        assertEquals(PaymentQuestion.Kind.UNKNOWN_IF_PAID, EventMatcher.questions(FinanceData(accounts = listOf(bank), events = listOf(e)), today).first().kind)
        assertTrue(EventMatcher.questions(FinanceData(accounts = listOf(bank), events = listOf(e.copy(isIncomeEvent = false))), today).isEmpty())
        assertTrue(EventMatcher.questions(FinanceData(accounts = listOf(bank), events = listOf(FinanceEvent(title = "רופא", date = LocalDate.of(2026, 12, 1)))), today).isEmpty())
        val e2 = FinanceEvent(title = "אירוע חברה", date = LocalDate.of(2026, 12, 5), expectedIncome = money(3000))
        val pay = Transaction(kind = TxKind.INCOME, amount = money(3000), accountId = bank.id, title = "תשלום", date = LocalDate.of(2026, 12, 8))
        val rejected = FinanceData(accounts = listOf(bank), transactions = listOf(pay), events = listOf(e2.copy(rejectedTransactionIds = listOf(pay.id))))
        assertEquals(PaymentQuestion.Kind.UNPAID_AFTER_EVENT, EventMatcher.questions(rejected, today).first().kind)
        val linked = FinanceData(accounts = listOf(bank), transactions = listOf(pay.copy(eventId = e2.id)), events = listOf(e2))
        assertTrue(EventMatcher.questions(linked, today).isEmpty())
    }
}
