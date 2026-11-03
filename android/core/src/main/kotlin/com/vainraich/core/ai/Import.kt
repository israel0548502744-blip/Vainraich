package com.vainraich.core.ai

import com.vainraich.core.*
import java.time.LocalDate

/** Free offline extractor working on text (PDF text layer, on-device OCR, pasted text). Always marked for review. */
class RuleBasedExtractor : DocumentExtractor {
    override val displayName = "זיהוי בסיסי במכשיר (ללא בינה מלאכותית)"
    override val capabilities = Capabilities(pdf = false, images = false, onDevice = true)

    override fun extract(input: DocInput): ExtractionResult {
        if (input !is DocInput.Text) throw AIError.unsupported(input.kindName)
        return parse(input.text)
    }

    companion object {
        private val dateRe = Regex("""(?<!\d)(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})(?!\d)""")
        private val amountRe = Regex("""(?<![\d/.])-?\d{1,3}(?:,\d{3})*\.\d{2}-?(?![\d/])|(?<![\d/.])-?\d+\.\d{2}-?(?![\d/])""")
        private val incomeWords = listOf("משכורת", "זיכוי", "הפקדה", "העברה מ", "קבלה", "החזר", "ריבית זכות", "מענק", "קצבה")
        private val cardWords = listOf("ויזה", "visa", "ישראכרט", "isracard", "מקס", "max it", "כאל", "cal ", "אמריקן", "american express", "דיינרס", "חיוב כרטיס", "כרטיסי אשראי")

        fun parse(text: String): ExtractionResult {
            val lines = text.lines().map { it.trim() }.filter { it.isNotEmpty() }
            val lowerAll = text.lowercase()
            val isCard = lowerAll.contains("פירוט") && cardWords.any { lowerAll.contains(it) }
            val rows = mutableListOf<ExtractedTx>()
            val balances = mutableListOf<ExtractedBalance>()
            var prevBalance: Money? = null
            for (line in lines) {
                val dates = dateRe.findAll(line).mapNotNull { DateText.israeli(it.value) }.toList()
                val amountMatches = amountRe.findAll(line).toList()
                val amounts = amountMatches.mapNotNull { MoneyText.parse(it.value) }
                val lower = line.lowercase()
                if (lower.contains("יתרה") && amounts.isNotEmpty() && dates.size <= 1) {
                    balances += ExtractedBalance(line.take(40), amounts.last(), dates.firstOrNull()); continue
                }
                val date = dates.firstOrNull() ?: continue
                if (amounts.isEmpty()) continue
                var desc = line
                (dateRe.findAll(line).toList() + amountMatches).sortedByDescending { it.range.first }.forEach { desc = desc.replaceRange(it.range, " ") }
                desc = desc.replace("₪", " ").split(Regex("\\s+")).filter { w -> w.isNotEmpty() && !w.all { it.isDigit() || it == '-' } }.joinToString(" ")
                var amount: Money
                var moneyIn: Boolean
                if (amounts.size >= 2) {
                    amount = amounts[amounts.size - 2]
                    val bal = amounts.last()
                    moneyIn = prevBalance?.let { bal >= it } ?: (!amount.isNeg && incomeWords.any { lower.contains(it) })
                    prevBalance = bal
                } else {
                    amount = amounts[0]
                    moneyIn = !amount.isNeg && incomeWords.any { lower.contains(it) } && !isCard
                }
                if (isCard && lower.contains("זיכוי")) moneyIn = true
                amount = amount.abs2()
                if (!amount.isPos) continue
                rows += ExtractedTx(date, desc.ifEmpty { "תנועה" }, amount, moneyIn,
                    isCardBillPayment = !isCard && !moneyIn && cardWords.any { lower.contains(it) },
                    isBit = Regex("""(^|\s)(ביט|bit)(\s|$)""").containsMatchIn(lower) || lower.contains("בביט"))
            }
            val warnings = mutableListOf("הנתונים זוהו ללא בינה מלאכותית — כדאי לעבור על כל שורה לפני האישור.")
            if (rows.isEmpty() && balances.isEmpty()) warnings += "לא זוהו תנועות או יתרות בטקסט."
            val kind = when { isCard -> DocumentKind.CARD_STATEMENT; rows.isEmpty() && balances.isNotEmpty() -> DocumentKind.BALANCE_CONFIRMATION; rows.isEmpty() -> DocumentKind.OTHER; else -> DocumentKind.BANK_STATEMENT }
            return ExtractionResult(kind, balances = balances, transactions = rows, warnings = warnings, producedBy = "זיהוי בסיסי במכשיר")
        }
    }
}

data class ImportCandidate(val include: Boolean, val transaction: Transaction, val duplicateOf: String?, val note: String?, val source: ExtractedTx)

data class BalanceSuggestion(val label: String, val amount: Money, val asOf: LocalDate?, val appBalance: Money) {
    val difference: Money get() = (amount - appBalance).m2()
}

data class ImportPlan(val targetAccountId: String, val candidates: List<ImportCandidate>, val balances: List<BalanceSuggestion>, val warnings: List<String>, val result: ExtractionResult)

/** Turns extracted rows into proposed transactions: card bills → transfers, duplicates unselected, category guesses, balance check. */
object ImportPlanner {
    private val keywords = listOf(
        listOf("מזון", "סופר", "שופרסל", "רמי לוי", "יוחננוף", "ויקטורי", "אושר עד", "מגה", "טיב טעם") to "מזון",
        listOf("מסעד", "קפה", "וולט", "wolt", "תן ביס", "מקדונלד", "פיצה", "בורגר") to "מסעדות",
        listOf("תחבורה", "דלק", "פז", "סונול", "דור אלון", "רב קו", "רכבת", "חניה", "פנגו", "סלופארק", "gett", "מונית") to "תחבורה",
        listOf("דיור", "שכר דירה", "שכירות", "ארנונה", "ועד בית", "משכנתא") to "דיור",
        listOf("חשבונות", "חשמל", "מים", "גז", "תאגיד") to "חשבונות",
        listOf("תקשורת", "סלקום", "פרטנר", "הוט", "בזק", "גולן", "פלאפון", "yes", "נטפליקס", "netflix", "spotify", "google", "apple.com") to "תקשורת",
        listOf("בריאות", "מכבי", "כללית", "מאוחדת", "לאומית", "סופר-פארם", "סופר פארם", "בית מרקחת") to "בריאות",
        listOf("קניות", "זארה", "h&m", "קסטרו", "עלי אקספרס", "aliexpress", "amazon", "אמזון", "איקאה") to "קניות",
        listOf("חינוך", "גן", "בית ספר", "חוג", "אוניברסיט") to "חינוך",
        listOf("פנאי", "קולנוע", "סינמה", "הופעה", "חדר כושר") to "פנאי",
        listOf("עמלה", "עמלות", "ריבית", "דמי ניהול") to "עמלות",
        listOf("משכורת", "שכר") to "משכורת",
        listOf("החזר", "ביטוח לאומי", "קצבה", "מס הכנסה") to "קצבאות",
    )

    fun guessCategory(hint: String?, description: String, kind: TxKind, data: FinanceData): String? {
        val want = if (kind == TxKind.INCOME) CategoryKind.INCOME else CategoryKind.EXPENSE
        val cats = data.categories.filter { it.kind == want && !it.isArchived }
        val text = ((hint ?: "") + " " + description).lowercase()
        cats.firstOrNull { text.contains(it.name.lowercase()) }?.let { return it.id }
        for ((words, frag) in keywords) if (words.any { text.contains(it) }) cats.firstOrNull { it.name.contains(frag) }?.let { return it.id }
        return null
    }

    fun externalId(r: ExtractedTx, accountId: String): String =
        "doc:${accountId.take(8)}:${r.date ?: "-"}:${r.amount.plain}:${if (r.moneyIn) "in" else "out"}:${r.description.lowercase().filter { !it.isWhitespace() }.take(40)}"

    fun plan(result: ExtractionResult, targetAccountId: String, data: FinanceData, today: LocalDate): ImportPlan {
        val warnings = result.warnings.toMutableList()
        val target = data.account(targetAccountId) ?: return ImportPlan(targetAccountId, emptyList(), emptyList(), listOf("החשבון שנבחר לא נמצא"), result)
        if (result.currency != target.currency) warnings += "המסמך במטבע ${result.currency} והחשבון במטבע ${target.currency} — בדוק את הסכומים."
        val isCard = target.type == AccountType.CREDIT_CARD
        val billCard = data.accounts.firstOrNull { it.type == AccountType.CREDIT_CARD && it.isActive && it.paymentAccountId == target.id }
            ?: data.accounts.firstOrNull { it.type == AccountType.CREDIT_CARD && it.isActive }
        val bitIds = data.accounts.filter { it.type == AccountType.BIT }.map { it.id }.toSet()
        val known = data.transactions.mapNotNull { it.externalId }.toSet()
        val seen = mutableSetOf<String>()
        val out = mutableListOf<ImportCandidate>()

        for (row in result.transactions) {
            if (!row.amount.isPos) continue
            var note: String? = null
            val date = row.date ?: result.statementDate ?: today
            if (row.date == null) note = "לא זוהה תאריך — נקבע ${date.il}"
            var kind = if (row.moneyIn) TxKind.INCOME else TxKind.EXPENSE
            var counter: String? = null
            var method: PaymentMethod? = if (isCard) PaymentMethod.CREDIT_CARD else null
            if (!isCard && row.isCardBillPayment && !row.moneyIn) {
                if (billCard != null) { kind = TxKind.TRANSFER; counter = billCard.id; note = "חיוב כרטיס אשראי — נרשם כהעברה ל${billCard.name} כדי שלא תיספר הוצאה כפולה" }
                else note = "נראה כמו חיוב כרטיס אשראי. כדאי להוסיף את הכרטיס כחשבון כדי למנוע ספירה כפולה."
            }
            if (row.isBit) method = PaymentMethod.BIT
            val ext = externalId(row, target.id)
            var tx = Transaction(kind = kind, status = if (date.isAfter(today)) TxStatus.PENDING else TxStatus.COMPLETED, amount = row.amount,
                accountId = target.id, counterAccountId = counter,
                categoryId = if (kind == TxKind.TRANSFER) null else guessCategory(row.categoryHint, row.description, kind, data),
                title = row.description.ifBlank { if (kind == TxKind.INCOME) "הכנסה" else "הוצאה" }, date = date, paymentMethod = method,
                notes = row.reference?.let { "אסמכתא: $it" } ?: "", source = TxSource.DOCUMENT_IMPORT, externalId = ext)
            var dup: String? = null
            if (ext in known) { dup = data.transactions.first { it.externalId == ext }.id; note = "כבר יובא בעבר" }
            else {
                val m = data.transactions.firstOrNull { t ->
                    t.status != TxStatus.CANCELLED && t.amount == row.amount && kotlin.math.abs(t.date.daysUntil(date)) <= 1 &&
                        (t.accountId == target.id || t.counterAccountId == target.id) && Ledger.effect(t, target.id).isNeg == !row.moneyIn
                }
                if (m != null) { dup = m.id; note = "דומה לתנועה קיימת: ${m.title} (${m.date.il})" }
                else if (row.isBit) data.transactions.firstOrNull { t -> t.accountId in bitIds && t.amount == row.amount && kotlin.math.abs(t.date.daysUntil(date)) <= 3 && t.status != TxStatus.CANCELLED }
                    ?.let { dup = it.id; tx = tx.copy(matchedTransactionId = it.id); note = "נראה שכבר נרשם בביט: ${it.title}" }
            }
            if (!seen.add(ext)) note = "מופיע פעמיים במסמך — בדוק אם זו אותה תנועה"
            out += ImportCandidate(dup == null, tx, dup, note, row)
        }
        val current = Ledger.balance(target, data.transactions)
        val sel = out.filter { it.include }.sumOfMoney { Ledger.effect(it.transaction, target.id) }
        val sugg = result.balances.map { b -> BalanceSuggestion(b.label, if (isCard && b.amount.isPos) b.amount.negate() else b.amount, b.asOf, (current + sel).m2()) }
        return ImportPlan(target.id, out, sugg, warnings, result)
    }

    fun adjustment(s: BalanceSuggestion, accountId: String, today: LocalDate): Transaction? {
        val diff = s.difference
        if (diff.signum() == 0) return null
        return Transaction(kind = TxKind.ADJUSTMENT, amount = diff.abs2(), adjustmentIsNegative = diff.isNeg, accountId = accountId,
            title = "התאמת יתרה לפי מסמך", date = s.asOf ?: today, notes = s.label, source = TxSource.DOCUMENT_IMPORT)
    }
}
