package com.vainraich.core

import kotlinx.serialization.json.Json
import java.io.File
import java.time.LocalDate

/** JSON (de)serialization of the whole data document. Unknown/missing fields are tolerated for forward/backward compatibility. */
object FinanceJson {
    val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
        encodeDefaults = true
        explicitNulls = false
        coerceInputValues = true
    }

    fun encode(d: FinanceData): String = json.encodeToString(FinanceData.serializer(), d)

    fun decode(s: String): FinanceData {
        val d = json.decodeFromString(FinanceData.serializer(), s)
        require(d.schemaVersion <= FinanceData.CURRENT_SCHEMA) { "newer schema" }
        return d
    }
}

/** Atomic file store (write to temp, then rename). */
class FileStore(val file: File) {
    fun exists() = file.exists()
    fun load(): FinanceData = FinanceJson.decode(file.readText(Charsets.UTF_8))
    fun save(d: FinanceData) {
        file.parentFile?.mkdirs()
        val tmp = File(file.parentFile, file.name + ".tmp")
        tmp.writeText(FinanceJson.encode(d), Charsets.UTF_8)
        if (!tmp.renameTo(file)) { file.delete(); tmp.renameTo(file) }
    }
    fun delete() { file.delete() }
}

/** Clearly-labelled demo data (isDemo = true). Never mixed with real data. */
object DemoData {
    fun make(today: LocalDate = LocalDate.now()): FinanceData {
        val start = today.minusMonths(3)
        val bank = Account(name = "עו״ש — הדגמה", type = AccountType.BANK, institution = "בנק לדוגמה", openingBalance = money(7850), openingDate = start, sortOrder = 0)
        val cash = Account(name = "מזומן", type = AccountType.CASH, openingBalance = money(650), openingDate = start, sortOrder = 1)
        val bit = Account(name = "ביט", type = AccountType.BIT, openingBalance = money(200), openingDate = start, sortOrder = 2)
        val card = Account(name = "ויזה — הדגמה", type = AccountType.CREDIT_CARD, institution = "חברת אשראי לדוגמה", openingDate = start,
            creditLimit = money(15000), billingDay = 10, paymentAccountId = bank.id, sortOrder = 3)
        val savings = Account(name = "חיסכון", type = AccountType.SAVINGS, openingBalance = money(12000), openingDate = start, sortOrder = 4)
        val daniel = Contact(name = "דניאל (הדגמה)")
        val david = Contact(name = "דוד (הדגמה)")
        val noa = Contact(name = "נועה (הדגמה)")
        fun e(i: Int) = DefaultCategories.expense[i].id
        fun inc(i: Int) = DefaultCategories.income[i].id
        val tx = mutableListOf<Transaction>()
        for (back in 0..2) {
            val m = today.startOfMonth().minusMonths(back.toLong())
            fun d(day: Int) = m.withDayClamped(day)
            val rows = listOf(
                Transaction(kind = TxKind.INCOME, amount = money(9400), accountId = bank.id, categoryId = inc(0), title = "משכורת", date = d(1), paymentMethod = PaymentMethod.BANK_TRANSFER, source = TxSource.DEMO),
                Transaction(kind = TxKind.EXPENSE, amount = money(3800), accountId = bank.id, categoryId = e(3), title = "שכר דירה", date = d(2), paymentMethod = PaymentMethod.STANDING_ORDER, source = TxSource.DEMO),
                Transaction(kind = TxKind.EXPENSE, amount = money("612.40"), accountId = card.id, categoryId = e(0), title = "שופרסל", date = d(4), paymentMethod = PaymentMethod.CREDIT_CARD, source = TxSource.DEMO),
                Transaction(kind = TxKind.EXPENSE, amount = money("289.90"), accountId = card.id, categoryId = e(2), title = "דלק", date = d(7), paymentMethod = PaymentMethod.CREDIT_CARD, source = TxSource.DEMO),
                Transaction(kind = TxKind.EXPENSE, amount = money(149), accountId = card.id, categoryId = e(5), title = "סלולר ואינטרנט", date = d(9), paymentMethod = PaymentMethod.CREDIT_CARD, source = TxSource.DEMO),
                Transaction(kind = TxKind.EXPENSE, amount = money(96), accountId = cash.id, categoryId = e(1), title = "קפה ומאפה", date = d(12), paymentMethod = PaymentMethod.CASH, source = TxSource.DEMO),
                Transaction(kind = TxKind.INCOME, amount = money(1200), accountId = bit.id, categoryId = inc(1), contactId = noa.id, title = "צילומי בר מצווה", date = d(14), paymentMethod = PaymentMethod.BIT, source = TxSource.DEMO),
                Transaction(kind = TxKind.TRANSFER, amount = money(1000), accountId = bit.id, counterAccountId = bank.id, title = "העברה מביט לבנק", date = d(15), paymentMethod = PaymentMethod.BIT, source = TxSource.DEMO),
                Transaction(kind = TxKind.EXPENSE, amount = money("438.70"), accountId = card.id, categoryId = e(0), title = "רמי לוי", date = d(18), paymentMethod = PaymentMethod.CREDIT_CARD, source = TxSource.DEMO),
                Transaction(kind = TxKind.EXPENSE, amount = money(320), accountId = bank.id, categoryId = e(4), title = "חשמל", date = d(20), paymentMethod = PaymentMethod.STANDING_ORDER, source = TxSource.DEMO),
                Transaction(kind = TxKind.EXPENSE, amount = money(180), accountId = card.id, categoryId = e(9), title = "קולנוע וארוחה", date = d(23), paymentMethod = PaymentMethod.CREDIT_CARD, source = TxSource.DEMO),
            )
            tx += rows.filter { !it.date.isAfter(today) }
            if (back < 2 && !d(10).isAfter(today))
                tx += Transaction(kind = TxKind.TRANSFER, amount = money(1670), accountId = bank.id, counterAccountId = card.id, title = "חיוב ויזה", date = d(10), paymentMethod = PaymentMethod.BANK_TRANSFER, source = TxSource.DEMO)
        }
        val wedding = FinanceEvent(title = "צילום חתונה", date = today.plusDays(9), startTime = TimeOfDay(18, 0), endTime = TimeOfDay(23, 30),
            location = "אולם הגן, ראשון לציון", contactId = david.id, expectedIncome = money(1500), expectedExpense = money(150), notes = "מקדמה עוד לא התקבלה")
        val shoot = FinanceEvent(title = "צילומי משפחה", date = today.minusDays(5), startTime = TimeOfDay(16, 0), location = "פארק הירקון", contactId = noa.id, expectedIncome = money(800))
        val party = FinanceEvent(title = "אירוע יום הולדת משפחת לוי", date = today.minusDays(3), startTime = TimeOfDay(19, 0))
        val meeting = FinanceEvent(title = "פגישה עם רואה חשבון", date = today.plusDays(3), startTime = TimeOfDay(10, 0), expectedExpense = money(350))
        // Income that looks like payment for events (to show matching): one for the family shoot, one "from Levi".
        tx += Transaction(kind = TxKind.INCOME, amount = money(800), accountId = bit.id, categoryId = inc(1), contactId = noa.id, title = "ביט מנועה", date = today.minusDays(4), paymentMethod = PaymentMethod.BIT, source = TxSource.DEMO)
        tx += Transaction(kind = TxKind.INCOME, amount = money(1100), accountId = bit.id, title = "ביט מלוי", date = today.minusDays(2), paymentMethod = PaymentMethod.BIT, source = TxSource.DEMO)

        val loan = Debt(direction = DebtDirection.RECEIVABLE, contactId = daniel.id, title = "הלוואה לרכב", originalAmount = money(2000),
            issuedDate = today.minusMonths(2), dueDate = today.plusDays(20), countsAsIncomeOrExpense = false)
        val loanTx = Transaction(kind = TxKind.INCOME, amount = money(500), accountId = bank.id, contactId = daniel.id, title = "תשלום מדניאל: הלוואה לרכב",
            date = today.minusDays(12), source = TxSource.DEBT_PAYMENT, excludedFromReports = true)
        tx += loanTx
        val owed = Debt(direction = DebtDirection.PAYABLE, contactId = noa.id, title = "חלק בהשכרת ציוד", originalAmount = money(450), issuedDate = today.minusDays(10), dueDate = today.plusDays(6))
        val overdue = Debt(direction = DebtDirection.RECEIVABLE, contactId = david.id, title = "יתרה מצילומי אירוסין", originalAmount = money(700), issuedDate = today.minusMonths(1), dueDate = today.minusDays(7))

        val gym = RecurringRule(kind = TxKind.EXPENSE, amount = money(100), accountId = card.id, categoryId = e(9), title = "מנוי חדר כושר",
            frequency = Frequency.MONTHLY, dayOfMonth = 15, startDate = today.minusMonths(2).startOfMonth(), paymentMethod = PaymentMethod.CREDIT_CARD, autoPost = true)
        val rent = RecurringRule(kind = TxKind.EXPENSE, amount = money(3800), accountId = bank.id, categoryId = e(3), title = "שכר דירה",
            frequency = Frequency.MONTHLY, dayOfMonth = 2, startDate = today.startOfMonth().plusMonths(1), paymentMethod = PaymentMethod.STANDING_ORDER)
        val salary = RecurringRule(kind = TxKind.INCOME, amount = money(9400), accountId = bank.id, categoryId = inc(0), title = "משכורת",
            frequency = Frequency.MONTHLY, dayOfMonth = 1, startDate = today.startOfMonth().plusMonths(1), paymentMethod = PaymentMethod.BANK_TRANSFER)

        val rules = listOf(gym, rent, salary)
        return FinanceData(
            accounts = listOf(bank, cash, bit, card, savings),
            transactions = tx + Recurrence.materialize(rules, today, tx),
            contacts = listOf(daniel, david, noa), recurringRules = rules,
            events = listOf(wedding, shoot, party, meeting), debts = listOf(loan, owed, overdue),
            debtPayments = listOf(DebtPayment(debtId = loan.id, amount = money(500), date = loanTx.date, transactionId = loanTx.id)),
            isDemo = true,
        )
    }
}
