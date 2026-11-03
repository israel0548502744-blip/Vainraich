package com.vainraich.core

import java.time.LocalDate

enum class Confidence {
    /** Fixed amount & date entered by the user, known card bill. */
    CONFIRMED,
    /** Recurring rules, event budgets, debts the user owes. */
    EXPECTED,
    /** Depends on someone else (money owed to the user). */
    ESTIMATED
}

sealed class ForecastSource {
    data class Pending(val txId: String) : ForecastSource()
    data class Recurring(val ruleId: String, val date: LocalDate) : ForecastSource()
    data class EventIncome(val eventId: String) : ForecastSource()
    data class EventExpense(val eventId: String) : ForecastSource()
    data class Receivable(val debtId: String) : ForecastSource()
    data class Payable(val debtId: String) : ForecastSource()
    data class CardBill(val cardId: String) : ForecastSource()
}

data class ForecastItem(
    val id: String, val date: LocalDate, val title: String,
    /** Signed effect on available money. */
    val amount: Money, val confidence: Confidence, val source: ForecastSource, val isOverdue: Boolean,
)

data class ForecastDay(val date: LocalDate, val projected: Money, val confirmedOnly: Money, val inflow: Money, val outflow: Money)

data class Forecast(val range: DateRange, val starting: Money, val items: List<ForecastItem>, val days: List<ForecastDay>) {
    val ending: Money get() = days.lastOrNull()?.projected ?: starting
    val endingConfirmed: Money get() = days.lastOrNull()?.confirmedOnly ?: starting
    val expectedIncome: Money get() = items.filter { it.amount.isPos }.sumOfMoney { it.amount }
    val expectedExpenses: Money get() = items.filter { it.amount.isNeg }.sumOfMoney { it.amount.negate() }
    fun total(c: Confidence, positive: Boolean) = items.filter { it.confidence == c && (if (positive) it.amount.isPos else it.amount.isNeg) }.sumOfMoney { it.amount.abs() }
    val firstNegativeDay: ForecastDay? get() = days.firstOrNull { it.projected.isNeg }
    val lowestDay: ForecastDay? get() = days.minByOrNull { it.projected }
}

/**
 * Cash-flow forecast of available money (see ARCHITECTURE.md §4.8).
 * Expected money is never added to the starting (actual) balance; card purchases hit available money
 * only on the card's billing day; recurring occurrences already recorded are skipped.
 */
object ForecastEngine {
    fun make(data: FinanceData, requested: DateRange, today: LocalDate, includeReceivables: Boolean = data.settings.includeReceivablesInForecast,
             includePayables: Boolean = data.settings.includePayablesInForecast): Forecast {
        val range = DateRange(maxOf(requested.start, today), maxOf(requested.end, today))
        val active = data.accounts.filter { it.isActive }
        val availableIds = active.filter { it.includeInAvailable }.map { it.id }.toSet()
        val balances = Ledger.balances(data.accounts, data.transactions)
        val start = availableIds.sumOfMoney { balances[it] ?: ZERO }
        val items = mutableListOf<ForecastItem>()
        val cards = active.filter { it.type == AccountType.CREDIT_CARD }
        val cardIds = cards.map { it.id }.toSet()
        val cardFlows = mutableMapOf<String, MutableList<Pair<LocalDate, Money>>>()

        fun place(d: LocalDate) = if (d.isBefore(range.start)) range.start to true else d to false

        fun add(t: Transaction, id: String, c: Confidence, src: ForecastSource) {
            val (d, overdue) = place(t.date)
            if (d.isAfter(range.end)) return
            val eff = Ledger.availableEffect(t, availableIds)
            if (eff.signum() != 0) items += ForecastItem(id, d, t.title, eff, c, src, overdue)
            for (card in Ledger.touched(t)) if (card in cardIds) cardFlows.getOrPut(card) { mutableListOf() } += d to Ledger.effect(t, card)
        }

        for (t in data.transactions) if (t.status == TxStatus.PENDING) add(t, "tx-${t.id}", Confidence.CONFIRMED, ForecastSource.Pending(t.id))

        for (rule in data.recurringRules) {
            if (!rule.isActive || rule.startDate.isAfter(range.end)) continue
            val lookback = DateRange.of(maxOf(rule.startDate, today.minusDays(31)), range.end)
            for (d in Recurrence.unrecorded(rule, lookback, data.transactions)) {
                if (d.isBefore(today) && rule.autoPost) continue
                add(Recurrence.makeTransaction(rule, d, TxStatus.PENDING), "rec-${rule.id}-$d", Confidence.EXPECTED, ForecastSource.Recurring(rule.id, d))
            }
        }

        val hasAvailable = active.any { it.includeInAvailable }
        for (e in data.events) {
            val f = Events.financials(e, data.transactions)
            val (d, overdue) = place(e.date)
            if (d.isAfter(range.end) || !hasAvailable) continue
            if (e.debtId == null && f.outstandingIncome.isPos)
                items += ForecastItem("evi-${e.id}", d, e.title, f.outstandingIncome, Confidence.EXPECTED, ForecastSource.EventIncome(e.id), overdue)
            if (f.outstandingExpense.isPos)
                items += ForecastItem("eve-${e.id}", d, e.title, f.outstandingExpense.negate(), Confidence.EXPECTED, ForecastSource.EventExpense(e.id), overdue)
        }

        for (b in Debts.balances(data, today)) {
            if (!b.isOpen || !b.remaining.isPos) continue
            val due = b.debt.dueDate ?: continue
            val (d, overdue) = place(due)
            if (d.isAfter(range.end)) continue
            val name = data.contact(b.debt.contactId)?.name.orEmpty()
            val title = if (name.isEmpty()) b.debt.title else "$name · ${b.debt.title}"
            if (b.debt.direction == DebtDirection.RECEIVABLE && includeReceivables)
                items += ForecastItem("rcv-${b.debt.id}", d, title, b.remaining, Confidence.ESTIMATED, ForecastSource.Receivable(b.debt.id), overdue)
            if (b.debt.direction == DebtDirection.PAYABLE && includePayables)
                items += ForecastItem("pay-${b.debt.id}", d, title, b.remaining.negate(), Confidence.EXPECTED, ForecastSource.Payable(b.debt.id), overdue)
        }

        for (card in cards) {
            val day = card.billingDay ?: continue
            val payer = card.paymentAccountId ?: continue
            if (payer !in availableIds) continue
            var outstanding = (balances[card.id] ?: ZERO).negate().max(ZERO)
            val flows = (cardFlows[card.id] ?: mutableListOf()).sortedBy { it.first }.toMutableList()
            var bill = today.withDayClamped(day)
            if (bill.isBefore(today)) bill = today.startOfMonth().plusMonths(1).withDayClamped(day)
            var guard = 0
            while (!bill.isAfter(range.end) && guard++ < 60) {
                while (flows.isNotEmpty() && !flows.first().first.isAfter(bill)) outstanding -= flows.removeAt(0).second
                if (outstanding.isPos) {
                    items += ForecastItem("card-${card.id}-$bill", bill, "חיוב ${card.name}", outstanding.negate().m2(), Confidence.CONFIRMED, ForecastSource.CardBill(card.id), false)
                    outstanding = ZERO
                }
                bill = bill.startOfMonth().plusMonths(1).withDayClamped(day)
            }
        }

        items.sortWith(compareBy<ForecastItem>({ it.date }, { it.confidence }, { it.title }))
        val byDay = items.groupBy { it.date }
        var projected = start
        var confirmed = start
        val days = range.days.map { d ->
            val todays = byDay[d].orEmpty()
            val inflow = todays.filter { it.amount.isPos }.sumOfMoney { it.amount }
            val outflow = todays.filter { it.amount.isNeg }.sumOfMoney { it.amount.negate() }
            projected = (projected + inflow - outflow).m2()
            confirmed = (confirmed + todays.filter { it.confidence == Confidence.CONFIRMED }.sumOfMoney { it.amount }).m2()
            ForecastDay(d, projected, confirmed, inflow, outflow)
        }
        return Forecast(range, start, items, days)
    }
}

// ======================= Summary =======================

data class Summary(
    val available: Money, val availableByType: Map<AccountType, Money>, val creditCardLiability: Money,
    val payables: Money, val receivables: Money, val overdueReceivables: Money, val savings: Money,
    val periodIncome: Money, val periodExpenses: Money, val forecast: Forecast,
) {
    val periodNet: Money get() = (periodIncome - periodExpenses).m2()
    val expectedIncome: Money get() = forecast.expectedIncome
    val expectedExpenses: Money get() = forecast.expectedExpenses
    /** available + expected income − expected expenses. */
    val projected: Money get() = forecast.ending
    val liabilities: Money get() = (creditCardLiability + payables).m2()
}

object SummaryCalculator {
    fun make(data: FinanceData, period: DateRange, today: LocalDate): Summary {
        val balances = Ledger.balances(data.accounts, data.transactions)
        var available = ZERO; var card = ZERO; var savings = ZERO
        val byType = mutableMapOf<AccountType, Money>()
        for (a in data.accounts.filter { it.isActive }) {
            val b = balances[a.id] ?: ZERO
            if (a.includeInAvailable) { available += b; byType[a.type] = ((byType[a.type] ?: ZERO) + b).m2() }
            if (a.type == AccountType.CREDIT_CARD) card += b.negate().max(ZERO)
            if (a.type == AccountType.SAVINGS) savings += b
        }
        var rec = ZERO; var overdue = ZERO; var pay = ZERO
        for (b in Debts.balances(data, today)) if (b.isOpen) {
            if (b.debt.direction == DebtDirection.RECEIVABLE) { rec += b.remaining; if (b.isOverdue) overdue += b.remaining } else pay += b.remaining
        }
        var inc = ZERO; var exp = ZERO
        for (t in data.transactions) if (t.countsInReports && t.date in period) { if (t.kind == TxKind.INCOME) inc += t.amount else exp += t.amount }
        val f = ForecastEngine.make(data, DateRange(today, maxOf(period.end, today)), today)
        return Summary(available.m2(), byType, card.m2(), pay.m2(), rec.m2(), overdue.m2(), savings.m2(), inc.m2(), exp.m2(), f)
    }
}

// ======================= Reports =======================

data class MonthSummary(val year: Int, val month: Int, val income: Money, val expenses: Money) {
    val net: Money get() = (income - expenses).m2()
    val range: DateRange get() = DateRange.month(LocalDate.of(year, month, 1))
}

data class Slice(val id: String, val name: String, val icon: String, val colorToken: String, val amount: Money, val share: Double)

object Reports {
    fun monthly(data: FinanceData, endMonth: LocalDate, count: Int): List<MonthSummary> =
        (count - 1 downTo 0).map { i ->
            val m = endMonth.startOfMonth().minusMonths(i.toLong())
            val r = DateRange.month(m)
            var inc = ZERO; var exp = ZERO
            for (t in data.transactions) if (t.countsInReports && t.date in r) { if (t.kind == TxKind.INCOME) inc += t.amount else exp += t.amount }
            MonthSummary(m.year, m.monthValue, inc.m2(), exp.m2())
        }

    fun byCategory(data: FinanceData, kind: TxKind, range: DateRange): List<Slice> {
        val totals = data.transactions.filter { it.countsInReports && it.kind == kind && it.date in range }.groupBy { it.categoryId }
            .mapValues { (_, v) -> v.sumOfMoney { it.amount } }
        val sum = totals.values.sumMoney()
        return totals.map { (id, amt) ->
            val c = data.category(id)
            Slice(id ?: "none", c?.name ?: "ללא קטגוריה", c?.icon ?: "more", c?.colorToken ?: "gray", amt, if (sum.isPos) amt.toDouble() / sum.toDouble() else 0.0)
        }.sortedByDescending { it.amount }
    }

    fun incomeBySource(data: FinanceData, range: DateRange): List<Slice> {
        val totals = mutableMapOf<String, Pair<String, Money>>()
        for (t in data.transactions) if (t.countsInReports && t.kind == TxKind.INCOME && t.date in range) {
            val c = data.contact(t.contactId); val cat = data.category(t.categoryId)
            val (k, n) = when { c != null -> "c-${c.id}" to c.name; cat != null -> "k-${cat.id}" to cat.name; else -> "none" to "אחר" }
            totals[k] = n to ((totals[k]?.second ?: ZERO) + t.amount).m2()
        }
        val sum = totals.values.sumOfMoney { it.second }
        return totals.map { (k, v) -> Slice(k, v.first, if (k.startsWith("c-")) "person" else "tag", "green", v.second, if (sum.isPos) v.second.toDouble() / sum.toDouble() else 0.0) }
            .sortedByDescending { it.amount }
    }
}
