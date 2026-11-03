package com.vainraich.core

import java.time.LocalDate

/** Possible "this income is the payment for that event". Never applied without the user's approval. */
data class MatchSuggestion(val eventId: String, val transactionId: String, val score: Int, val reasons: List<String>)

data class PaymentQuestion(val event: FinanceEvent, val kind: Kind, val suggestions: List<MatchSuggestion>, val outstanding: Money) {
    enum class Kind {
        /** Found income that looks like the payment — confirm or reject. */
        POSSIBLE_MATCH,
        /** Event passed, expected income still open — was it paid? */
        UNPAID_AFTER_EVENT,
        /** Title says "אירוע" (or similar) but no amount — is it a paid event? */
        UNKNOWN_IF_PAID
    }
}

/**
 * Links events and income (user request): every event whose title contains "אירוע" or a paid-gig word,
 * or that has expected income, is checked against unlinked income from 14 days before to 45 days after.
 * Scored by amount, client, shared words (Hebrew-prefix aware) and timing. Always confirmed by the user.
 */
object EventMatcher {
    val keywords = listOf("אירוע", "אירועים", "חתונה", "חתונת", "בר מצווה", "בת מצווה", "ברית", "הופעה", "צילום", "צילומי", "הפקה", "כנס", "סדנה", "יום הולדת", "אירוסין", "חינה")
    private const val BEFORE = 14L
    private const val AFTER = 45L
    private const val MIN_SCORE = 30
    private val stop = setOf("של", "עם", "על", "את", "תשלום", "העברה", "הכנסה", "מאת", "עבור", "אירוע", "ביט", "bit")
    private val prefixes = setOf('מ', 'ב', 'ל', 'ו', 'ה', 'ש', 'כ')

    fun looksLikeIncomeEvent(title: String) = title.lowercase().let { t -> keywords.any { t.contains(it) } }

    fun isCandidate(e: FinanceEvent): Boolean {
        if (e.isIncomeEvent == false) return false
        return (e.expectedIncome?.isPos == true) || e.isIncomeEvent == true || looksLikeIncomeEvent(e.title)
    }

    fun words(s: String): Set<String> =
        s.lowercase().map { if (it.isLetterOrDigit()) it else ' ' }.joinToString("").split(' ')
            .filter { it.length >= 3 && it !in stop }.toSet()

    private fun stems(w: String): Set<String> = if (w.length >= 4 && w.first() in prefixes) setOf(w, w.drop(1)) else setOf(w)

    fun commonWords(a: Set<String>, b: Set<String>): Set<String> =
        a.filter { x -> val sx = stems(x); b.any { y -> stems(y).any { it in sx } } }.toSet()

    fun score(e: FinanceEvent, t: Transaction, outstanding: Money, data: FinanceData): Pair<Int, List<String>> {
        var s = 0
        val r = mutableListOf<String>()
        val expected = e.expectedIncome
        if (expected != null && expected.isPos) {
            when {
                outstanding.isPos && t.amount == outstanding -> { s += 50; r += "אותו סכום שנותר לגבות" }
                t.amount == expected -> { s += 45; r += "אותו סכום כמו ההכנסה הצפויה" }
                t.amount < expected && t.amount.multiply(4.toBigDecimal()) >= expected -> { s += 10; r += "יכול להיות תשלום חלקי או מקדמה" }
            }
        }
        e.contactId?.let { c ->
            if (t.contactId == c) { s += 35; r += "אותו לקוח" } else {
                val first = data.contact(c)?.name?.split(' ')?.firstOrNull().orEmpty()
                if (first.length >= 2 && (t.title + " " + t.notes).lowercase().contains(first.lowercase())) { s += 25; r += "שם הלקוח מופיע בתיאור" }
            }
        }
        val common = commonWords(words(e.title), words(t.title + " " + t.notes))
        if (common.isNotEmpty()) { s += 20; r += "מילים משותפות: ${common.sorted().joinToString(", ")}" }
        val days = e.date.daysUntil(t.date)
        if (days in 0..7) { s += 10; r += if (days == 0L) "התקבל ביום האירוע" else "התקבל $days ימים אחרי האירוע" }
        else if (days in -14..-1) { s += 5; r += "התקבל לפני האירוע (מקדמה?)" }
        if (t.categoryId == DefaultCategories.SELF_EMPLOYED_INCOME) s += 5
        return s to r
    }

    fun suggestions(data: FinanceData): Map<String, List<MatchSuggestion>> {
        val paymentTx = data.debtPayments.mapNotNull { it.transactionId }.toSet()
        val pool = data.transactions.filter { it.kind == TxKind.INCOME && it.status != TxStatus.CANCELLED && it.eventId == null && it.id !in paymentTx }
        val all = mutableListOf<MatchSuggestion>()
        for (e in data.events) {
            if (!isCandidate(e)) continue
            val f = Events.financials(e, data.transactions)
            val exp = e.expectedIncome
            if (exp != null && exp.isPos && f.receivedIncome >= exp) continue
            val rejected = e.rejectedTransactionIds.toSet()
            for (t in pool) {
                if (t.id in rejected) continue
                val d = e.date.daysUntil(t.date)
                if (d < -BEFORE || d > AFTER) continue
                val (s, reasons) = score(e, t, f.outstandingIncome, data)
                if (s >= MIN_SCORE) all += MatchSuggestion(e.id, t.id, s, reasons)
            }
        }
        val used = mutableSetOf<String>()
        val result = mutableMapOf<String, MutableList<MatchSuggestion>>()
        for (m in all.sortedWith(compareByDescending<MatchSuggestion> { it.score }.thenBy { it.transactionId })) {
            if (!used.add(m.transactionId)) continue
            result.getOrPut(m.eventId) { mutableListOf() } += m
        }
        return result
    }

    fun questions(data: FinanceData, today: LocalDate): List<PaymentQuestion> {
        val sugg = suggestions(data)
        val out = mutableListOf<PaymentQuestion>()
        for (e in data.events) {
            if (!isCandidate(e)) continue
            val f = Events.financials(e, data.transactions)
            val s = sugg[e.id].orEmpty()
            if (s.isNotEmpty()) { out += PaymentQuestion(e, PaymentQuestion.Kind.POSSIBLE_MATCH, s, f.outstandingIncome); continue }
            if (e.date.isAfter(today) || data.debt(e.debtId) != null) continue
            val exp = e.expectedIncome
            if (exp != null && exp.isPos) {
                if (f.outstandingIncome.isPos) out += PaymentQuestion(e, PaymentQuestion.Kind.UNPAID_AFTER_EVENT, emptyList(), f.outstandingIncome)
            } else if (e.isIncomeEvent == null && !f.receivedIncome.isPos) {
                out += PaymentQuestion(e, PaymentQuestion.Kind.UNKNOWN_IF_PAID, emptyList(), ZERO)
            }
        }
        return out.sortedWith(compareBy<PaymentQuestion> { it.kind.ordinal }.thenByDescending { it.event.date })
    }
}

// ======================= Filter & CSV =======================

data class TxFilter(
    val search: String = "",
    val kinds: Set<TxKind> = emptySet(),
    val statuses: Set<TxStatus> = emptySet(),
    val categoryIds: Set<String> = emptySet(),
    val accountIds: Set<String> = emptySet(),
    val range: DateRange? = null,
) {
    val isActive get() = kinds.isNotEmpty() || statuses.isNotEmpty() || categoryIds.isNotEmpty() || accountIds.isNotEmpty() || range != null

    fun matches(t: Transaction, data: FinanceData): Boolean {
        if (kinds.isNotEmpty() && t.kind !in kinds) return false
        if (statuses.isNotEmpty() && t.status !in statuses) return false
        if (categoryIds.isNotEmpty() && t.categoryId !in categoryIds) return false
        if (accountIds.isNotEmpty() && t.accountId !in accountIds && t.counterAccountId !in accountIds) return false
        if (range != null && t.date !in range) return false
        val q = search.trim()
        if (q.isNotEmpty()) {
            val hay = listOf(t.title, t.notes, data.category(t.categoryId)?.name, data.contact(t.contactId)?.name, data.account(t.accountId)?.name, t.amount.plain)
                .joinToString(" ") { it.orEmpty() }
            if (!hay.contains(q, ignoreCase = true)) return false
        }
        return true
    }

    fun apply(data: FinanceData) = data.transactions.filter { matches(it, data) }.sortedWith(compareByDescending<Transaction> { it.date }.thenByDescending { it.createdAt })
}

object Labels {
    fun kind(k: TxKind) = when (k) { TxKind.INCOME -> "הכנסה"; TxKind.EXPENSE -> "הוצאה"; TxKind.TRANSFER -> "העברה"; TxKind.ADJUSTMENT -> "עדכון יתרה" }
    fun status(s: TxStatus) = when (s) { TxStatus.PENDING -> "ממתין"; TxStatus.COMPLETED -> "בוצע"; TxStatus.CANCELLED -> "בוטל" }
    fun method(p: PaymentMethod) = when (p) {
        PaymentMethod.BANK_TRANSFER -> "העברה בנקאית"; PaymentMethod.CREDIT_CARD -> "כרטיס אשראי"; PaymentMethod.CASH -> "מזומן"
        PaymentMethod.BIT -> "ביט"; PaymentMethod.CHECK -> "צ׳ק"; PaymentMethod.STANDING_ORDER -> "הוראת קבע"; PaymentMethod.OTHER -> "אחר"
    }
    fun accountType(t: AccountType) = when (t) {
        AccountType.BANK -> "חשבון בנק"; AccountType.CASH -> "מזומן"; AccountType.BIT -> "ביט"
        AccountType.CREDIT_CARD -> "כרטיס אשראי"; AccountType.SAVINGS -> "חיסכון"; AccountType.OTHER -> "אחר"
    }
    fun debtStatus(s: DebtStatus) = when (s) {
        DebtStatus.OPEN -> "פתוח"; DebtStatus.PARTIALLY_PAID -> "שולם חלקית"; DebtStatus.PAID -> "שולם"
        DebtStatus.WRITTEN_OFF -> "נמחק"; DebtStatus.CANCELLED -> "בוטל"
    }
    fun eventPayment(s: EventPaymentStatus) = when (s) {
        EventPaymentStatus.NONE -> "ללא הכנסה"; EventPaymentStatus.UNPAID -> "לא שולם"
        EventPaymentStatus.PARTIALLY_PAID -> "שולם חלקית"; EventPaymentStatus.PAID -> "שולם"
    }
    fun confidence(c: Confidence) = when (c) { Confidence.CONFIRMED -> "מאושר"; Confidence.EXPECTED -> "צפוי"; Confidence.ESTIMATED -> "משוער" }
    fun frequency(f: Frequency, n: Int = 1) = when (f) {
        Frequency.DAILY -> if (n == 1) "כל יום" else "כל $n ימים"
        Frequency.WEEKLY -> if (n == 1) "כל שבוע" else if (n == 2) "כל שבועיים" else "כל $n שבועות"
        Frequency.MONTHLY -> if (n == 1) "כל חודש" else if (n == 2) "כל חודשיים" else "כל $n חודשים"
        Frequency.YEARLY -> if (n == 1) "כל שנה" else "כל $n שנים"
    }
    val months = listOf("ינואר", "פברואר", "מרץ", "אפריל", "מאי", "יוני", "יולי", "אוגוסט", "ספטמבר", "אוקטובר", "נובמבר", "דצמבר")
    val weekdayShort = listOf("א׳", "ב׳", "ג׳", "ד׳", "ה׳", "ו׳", "ש׳")
    val weekdayLong = listOf("ראשון", "שני", "שלישי", "רביעי", "חמישי", "שישי", "שבת")
    fun month(m: Int) = months[(m - 1).coerceIn(0, 11)]
}

object Csv {
    private fun esc(s: String) = if (s.any { it == ',' || it == '"' || it == '\n' }) "\"" + s.replace("\"", "\"\"") + "\"" else s

    /** UTF-8 with BOM (Excel shows Hebrew). Signed plain amounts. */
    fun transactions(list: List<Transaction>, data: FinanceData): String {
        val lines = mutableListOf("תאריך,תיאור,סוג,סטטוס,סכום,חשבון,לחשבון,קטגוריה,איש קשר,אמצעי תשלום,הערות")
        for (t in list.sortedBy { it.date }) {
            val signed = when (t.kind) {
                TxKind.INCOME, TxKind.TRANSFER -> t.amount
                TxKind.EXPENSE -> t.amount.negate()
                TxKind.ADJUSTMENT -> if (t.adjustmentIsNegative) t.amount.negate() else t.amount
            }
            lines += listOf(t.date.il, t.title, Labels.kind(t.kind), Labels.status(t.status), signed.plain,
                data.account(t.accountId)?.name.orEmpty(), data.account(t.counterAccountId)?.name.orEmpty(),
                data.category(t.categoryId)?.name.orEmpty(), data.contact(t.contactId)?.name.orEmpty(),
                t.paymentMethod?.let(Labels::method).orEmpty(), t.notes).joinToString(",") { esc(it) }
        }
        return "﻿" + lines.joinToString("\r\n") + "\r\n"
    }

    fun monthly(months: List<MonthSummary>): String =
        "﻿" + (listOf("חודש,הכנסות,הוצאות,תזרים נטו") + months.map { "%02d/%04d,%s,%s,%s".format(it.month, it.year, it.income.plain, it.expenses.plain, it.net.plain) })
            .joinToString("\r\n") + "\r\n"
}
