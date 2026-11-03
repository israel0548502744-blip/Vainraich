package com.vainraich.core

import java.time.LocalDate

// ======================= Ledger =======================

object Ledger {
    /** Signed effect of one transaction on one account (ignores status). */
    fun effect(t: Transaction, accountId: String): Money = when (t.kind) {
        TxKind.INCOME -> if (t.accountId == accountId) t.amount else ZERO
        TxKind.EXPENSE -> if (t.accountId == accountId) t.amount.negate() else ZERO
        TxKind.TRANSFER -> {
            var e = ZERO
            if (t.accountId == accountId) e -= t.amount
            if (t.counterAccountId == accountId) e += t.amount
            e
        }
        TxKind.ADJUSTMENT -> if (t.accountId == accountId) (if (t.adjustmentIsNegative) t.amount.negate() else t.amount) else ZERO
    }.m2()

    fun touched(t: Transaction): List<String> =
        if (t.kind == TxKind.TRANSFER && t.counterAccountId != null) listOf(t.accountId, t.counterAccountId) else listOf(t.accountId)

    /** Opening balance + every COMPLETED transaction. Pending never changes the real balance. */
    fun balance(a: Account, txs: List<Transaction>): Money =
        txs.filter { it.status == TxStatus.COMPLETED }.fold(a.openingBalance) { acc, t -> acc + effect(t, a.id) }.m2()

    fun balances(accounts: List<Account>, txs: List<Transaction>): Map<String, Money> {
        val r = accounts.associate { it.id to it.openingBalance }.toMutableMap()
        for (t in txs) if (t.status == TxStatus.COMPLETED) for (id in touched(t)) {
            r[id]?.let { r[id] = (it + effect(t, id)).m2() }
        }
        return r
    }

    fun availableEffect(t: Transaction, availableIds: Set<String>): Money =
        touched(t).filter { it in availableIds }.sumOfMoney { effect(t, it) }
}

// ======================= Validation =======================

sealed class ValidationError(val hebrew: String) : Exception(hebrew) {
    object EmptyTitle : ValidationError("יש למלא שם או תיאור.")
    object NonPositiveAmount : ValidationError("הסכום חייב להיות גדול מאפס.")
    object UnknownAccount : ValidationError("יש לבחור חשבון.")
    object TransferNeedsDestination : ValidationError("בהעברה יש לבחור לאיזה חשבון.")
    object TransferSameAccount : ValidationError("אי אפשר להעביר לאותו חשבון.")
    object CategoryOnTransfer : ValidationError("העברה בין חשבונות לא מקבלת קטגוריה.")
    object CategoryKindMismatch : ValidationError("הקטגוריה לא מתאימה לסוג התנועה.")
    object CurrencyMismatch : ValidationError("שני החשבונות צריכים להיות באותו מטבע.")
    object RecurringMismatch : ValidationError("שגיאה בקישור לתשלום הקבוע.")
    class PaymentExceedsRemaining(val remaining: Money) : ValidationError("הסכום גבוה מהיתרה לתשלום (${MoneyFormatter.format(remaining)}).")
    object DebtClosed : ValidationError("החוב כבר סגור.")
    object EventTimeOrder : ValidationError("שעת הסיום מוקדמת משעת ההתחלה.")
    object InvalidBillingDay : ValidationError("יום החיוב צריך להיות בין 1 ל־31.")
}

fun Transaction.validate(data: FinanceData) {
    if (title.isBlank()) throw ValidationError.EmptyTitle
    if (!amount.isPos) throw ValidationError.NonPositiveAmount
    val acc = data.account(accountId) ?: throw ValidationError.UnknownAccount
    when (kind) {
        TxKind.TRANSFER -> {
            val dest = counterAccountId ?: throw ValidationError.TransferNeedsDestination
            if (dest == accountId) throw ValidationError.TransferSameAccount
            val d = data.account(dest) ?: throw ValidationError.UnknownAccount
            if (categoryId != null) throw ValidationError.CategoryOnTransfer
            if (d.currency != acc.currency) throw ValidationError.CurrencyMismatch
        }
        TxKind.INCOME, TxKind.EXPENSE -> data.category(categoryId)?.let {
            val want = if (kind == TxKind.INCOME) CategoryKind.INCOME else CategoryKind.EXPENSE
            if (it.kind != want) throw ValidationError.CategoryKindMismatch
        }
        TxKind.ADJUSTMENT -> {}
    }
    if ((recurringId == null) != (occurrenceDate == null)) throw ValidationError.RecurringMismatch
}

fun Account.validate() {
    if (name.isBlank()) throw ValidationError.EmptyTitle
    billingDay?.let { if (it !in 1..31) throw ValidationError.InvalidBillingDay }
}

fun FinanceEvent.validate() {
    if (title.isBlank()) throw ValidationError.EmptyTitle
    if (expectedIncome?.isNeg == true || expectedExpense?.isNeg == true) throw ValidationError.NonPositiveAmount
    if (startTime != null && endTime != null && endTime < startTime) throw ValidationError.EventTimeOrder
}

// ======================= Recurrence =======================

object Recurrence {
    private const val MAX_ITER = 20_000

    /** Occurrences inside [range], honouring start, end and maxOccurrences (counted from the start). */
    fun occurrences(rule: RecurringRule, range: DateRange): List<LocalDate> {
        if (!rule.isActive) return emptyList()
        val hardEnd = minOf(range.end, rule.endDate ?: range.end)
        if (hardEnd.isBefore(rule.startDate)) return emptyList()
        val out = mutableListOf<LocalDate>()
        var count = 0
        val limit = rule.maxOccurrences ?: Int.MAX_VALUE
        var iter = 0
        val interval = maxOf(1, rule.interval)

        fun consider(d: LocalDate): Boolean {
            iter++
            if (iter > MAX_ITER || d.isAfter(hardEnd) || count >= limit) return false
            if (d.isBefore(rule.startDate)) return true
            count++
            if (!d.isBefore(range.start)) out += d
            return true
        }

        when (rule.frequency) {
            Frequency.DAILY -> { var n = 0L; while (consider(rule.startDate.plusDays(n * interval))) n++ }
            Frequency.WEEKLY -> {
                val days = (rule.weekdays.ifEmpty { listOf(rule.startDate.weekdaySun1) }).filter { it in 1..7 }.sorted()
                val weekStart = rule.startDate.startOfWeekSunday()
                var k = 0L
                outer@ while (k < MAX_ITER) {
                    val base = weekStart.plusWeeks(k * interval)
                    if (base.isAfter(hardEnd)) break
                    for (wd in days) if (!consider(base.plusDays((wd - 1).toLong()))) break@outer
                    k++
                }
            }
            Frequency.MONTHLY -> {
                val anchor = rule.dayOfMonth ?: rule.startDate.dayOfMonth
                var n = 0L
                while (consider(rule.startDate.startOfMonth().plusMonths(n * interval).withDayClamped(anchor))) n++
            }
            Frequency.YEARLY -> {
                val anchor = rule.dayOfMonth ?: rule.startDate.dayOfMonth
                var n = 0L
                while (consider(rule.startDate.startOfMonth().plusYears(n * interval).withDayClamped(anchor))) n++
            }
        }
        return out
    }

    /** Occurrences without a recorded transaction (any status) — prevents double counting. */
    fun unrecorded(rule: RecurringRule, range: DateRange, txs: List<Transaction>): List<LocalDate> {
        val recorded = txs.filter { it.recurringId == rule.id }.mapNotNull { it.occurrenceDate }.toSet()
        return occurrences(rule, range).filter { it !in recorded }
    }

    fun makeTransaction(rule: RecurringRule, date: LocalDate, status: TxStatus) = Transaction(
        kind = rule.kind, status = status, amount = rule.amount, accountId = rule.accountId,
        counterAccountId = if (rule.kind == TxKind.TRANSFER) rule.counterAccountId else null,
        categoryId = if (rule.kind == TxKind.TRANSFER) null else rule.categoryId, contactId = rule.contactId,
        title = rule.title, date = date, paymentMethod = rule.paymentMethod, recurringId = rule.id, occurrenceDate = date,
        source = TxSource.RECURRING,
    )

    /** Records each due occurrence up to [today] exactly once. Rules starting in the future are skipped. */
    fun materialize(rules: List<RecurringRule>, today: LocalDate, existing: List<Transaction>): List<Transaction> =
        rules.filter { it.isActive && !it.startDate.isAfter(today) }.flatMap { r ->
            unrecorded(r, DateRange(r.startDate, today), existing).map {
                makeTransaction(r, it, if (r.autoPost) TxStatus.COMPLETED else TxStatus.PENDING)
            }
        }

    fun next(rule: RecurringRule, onOrAfter: LocalDate): LocalDate? =
        occurrences(rule, DateRange(onOrAfter, onOrAfter.plusYears(2))).firstOrNull()

    fun monthlyEquivalent(r: RecurringRule): Money {
        val n = maxOf(1, r.interval).toBigDecimal()
        val mc = java.math.MathContext.DECIMAL64
        return when (r.frequency) {
            Frequency.DAILY -> r.amount.multiply(30.toBigDecimal()).divide(n, mc)
            Frequency.WEEKLY -> r.amount.multiply(maxOf(1, r.weekdays.size).toBigDecimal()).multiply(52.toBigDecimal()).divide(12.toBigDecimal(), mc).divide(n, mc)
            Frequency.MONTHLY -> r.amount.divide(n, mc)
            Frequency.YEARLY -> r.amount.divide(12.toBigDecimal(), mc).divide(n, mc)
        }.m2()
    }
}

// ======================= Debts =======================

data class DebtBalance(
    val debt: Debt, val paid: Money, val remaining: Money, val status: DebtStatus, val isOverdue: Boolean, val lastPayment: LocalDate?,
) {
    val isOpen get() = status == DebtStatus.OPEN || status == DebtStatus.PARTIALLY_PAID
    val progress: Float get() = if (debt.originalAmount.isPos) (paid.toDouble() / debt.originalAmount.toDouble()).toFloat().coerceIn(0f, 1f) else 0f
}

object Debts {
    fun balance(d: Debt, payments: List<DebtPayment>, today: LocalDate): DebtBalance {
        val mine = payments.filter { it.debtId == d.id }
        val paid = mine.sumOfMoney { it.amount }
        val remaining = (d.originalAmount - paid).max(ZERO).m2()
        val status = d.closedStatus ?: when {
            remaining.signum() == 0 -> DebtStatus.PAID
            paid.isPos -> DebtStatus.PARTIALLY_PAID
            else -> DebtStatus.OPEN
        }
        val open = status == DebtStatus.OPEN || status == DebtStatus.PARTIALLY_PAID
        val overdue = open && (d.dueDate?.isBefore(today) ?: false)
        return DebtBalance(d, paid, if (open) remaining else ZERO, status, overdue, mine.maxOfOrNull { it.date })
    }

    fun balances(data: FinanceData, today: LocalDate) = data.debts.map { balance(it, data.debtPayments, today) }

    /** Payment + a COMPLETED account transaction, so real money moves only when it actually arrives (scenario B). */
    fun recordPayment(debtId: String, amount: Money, date: LocalDate, accountId: String, notes: String, data: FinanceData, today: LocalDate): Pair<DebtPayment, Transaction> {
        val debt = data.debt(debtId) ?: throw ValidationError.UnknownAccount
        data.account(accountId) ?: throw ValidationError.UnknownAccount
        val amt = amount.m2()
        if (!amt.isPos) throw ValidationError.NonPositiveAmount
        val b = balance(debt, data.debtPayments, today)
        if (!b.isOpen) throw ValidationError.DebtClosed
        if (amt > b.remaining) throw ValidationError.PaymentExceedsRemaining(b.remaining)
        val receivable = debt.direction == DebtDirection.RECEIVABLE
        val name = data.contact(debt.contactId)?.name.orEmpty()
        val who = if (name.isEmpty()) "" else (if (receivable) " מ" else " ל") + name
        val tx = Transaction(
            kind = if (receivable) TxKind.INCOME else TxKind.EXPENSE, amount = amt, accountId = accountId, contactId = debt.contactId,
            title = "תשלום$who: ${debt.title}", date = date, eventId = debt.eventId, source = TxSource.DEBT_PAYMENT,
            excludedFromReports = !debt.countsAsIncomeOrExpense,
        )
        return DebtPayment(debtId = debt.id, amount = amt, date = date, transactionId = tx.id, notes = notes) to tx
    }

    fun collectionRate(data: FinanceData): Double? {
        val rec = data.debts.filter { it.direction == DebtDirection.RECEIVABLE && it.closedStatus != DebtStatus.CANCELLED }
        val owed = rec.sumOfMoney { it.originalAmount }
        if (!owed.isPos) return null
        val ids = rec.map { it.id }.toSet()
        val collected = data.debtPayments.filter { it.debtId in ids }.sumOfMoney { it.amount }
        return collected.toDouble() / owed.toDouble()
    }
}

// ======================= Events =======================

data class EventFinancials(
    val event: FinanceEvent, val receivedIncome: Money, val paidExpense: Money,
    val outstandingIncome: Money, val outstandingExpense: Money, val paymentStatus: EventPaymentStatus,
)

object Events {
    fun financials(e: FinanceEvent, txs: List<Transaction>): EventFinancials {
        val linked = txs.filter { it.eventId == e.id && it.status != TxStatus.CANCELLED }
        val received = linked.filter { it.kind == TxKind.INCOME && it.status == TxStatus.COMPLETED }.sumOfMoney { it.amount }
        val incomeCovered = linked.filter { it.kind == TxKind.INCOME }.sumOfMoney { it.amount }
        val paidExp = linked.filter { it.kind == TxKind.EXPENSE && it.status == TxStatus.COMPLETED }.sumOfMoney { it.amount }
        val expCovered = linked.filter { it.kind == TxKind.EXPENSE }.sumOfMoney { it.amount }
        val ei = e.expectedIncome ?: ZERO
        val ee = e.expectedExpense ?: ZERO
        val status = when {
            !ei.isPos -> EventPaymentStatus.NONE
            received >= ei -> EventPaymentStatus.PAID
            received.isPos -> EventPaymentStatus.PARTIALLY_PAID
            else -> EventPaymentStatus.UNPAID
        }
        return EventFinancials(e, received, paidExp, (ei - incomeCovered).max(ZERO).m2(), (ee - expCovered).max(ZERO).m2(), status)
    }

    fun paymentStatus(e: FinanceEvent, data: FinanceData, today: LocalDate): EventPaymentStatus {
        data.debt(e.debtId)?.let {
            return when (Debts.balance(it, data.debtPayments, today).status) {
                DebtStatus.PAID, DebtStatus.WRITTEN_OFF -> EventPaymentStatus.PAID
                DebtStatus.PARTIALLY_PAID -> EventPaymentStatus.PARTIALLY_PAID
                DebtStatus.OPEN -> EventPaymentStatus.UNPAID
                DebtStatus.CANCELLED -> EventPaymentStatus.NONE
            }
        }
        val f = financials(e, data.transactions)
        if (f.paymentStatus == EventPaymentStatus.NONE && f.receivedIncome.isPos) return EventPaymentStatus.PAID
        return f.paymentStatus
    }
}
