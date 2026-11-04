package com.vainraich.core.ai

import com.vainraich.core.*
import kotlinx.serialization.json.*
import java.math.BigDecimal
import java.time.LocalDate

// ---------------- Chat with the user's own AI provider ----------------

enum class ChatRole { USER, ASSISTANT }

data class ChatMessage(val role: ChatRole, val text: String)

/** A provider that can hold a conversation (all remote providers). */
interface ChatProvider {
    val displayName: String
    fun chat(system: String, messages: List<ChatMessage>): String
}

/**
 * Something the assistant suggests recording. Nothing is saved until the user taps "confirm" —
 * the assistant never changes data on its own.
 */
sealed class ProposedAction {
    abstract val summary: String

    data class AddTransaction(
        val kind: TxKind, val amount: Money, val title: String, val date: LocalDate?,
        val category: String?, val account: String?, val person: String?,
    ) : ProposedAction() {
        override val summary get() = "${Labels.kind(kind)} ${amount.ils()} — $title" + (date?.let { " · ${it.il}" } ?: "")
    }

    data class AddDebt(val direction: DebtDirection, val person: String, val amount: Money, val title: String, val dueDate: LocalDate?) : ProposedAction() {
        override val summary get() = (if (direction == DebtDirection.RECEIVABLE) "חוב חדש: $person חייב/ת לי " else "חוב חדש: אני חייב ל$person ") +
            amount.ils() + " — $title" + (dueDate?.let { " · עד ${it.il}" } ?: "")
    }

    data class AddCharge(val person: String, val amount: Money, val reason: String) : ProposedAction() {
        override val summary get() = "הוספת ${amount.ils()} לחוב של $person" + (if (reason.isNotBlank()) " — $reason" else "")
    }

    data class DebtPayment(val person: String, val amount: Money, val date: LocalDate?, val account: String?) : ProposedAction() {
        override val summary get() = "רישום תשלום ${amount.ils()} מ/ל$person" + (date?.let { " · ${it.il}" } ?: "")
    }

    data class AddEvent(val title: String, val date: LocalDate, val expectedIncome: Money?, val person: String?) : ProposedAction() {
        override val summary get() = "אירוע: $title · ${date.il}" + (expectedIncome?.let { " · הכנסה צפויה ${it.ils()}" } ?: "")
    }
}

data class AssistantReply(val text: String, val actions: List<ProposedAction>)

private fun Money.ils() = MoneyFormatter.format(this)

object Assistant {
    /** Keeps requests small enough for free tiers. */
    const val MAX_TRANSACTIONS = 80
    const val MAX_HISTORY = 16

    val examples = listOf(
        "כמה כסף יש לי באמת עכשיו?",
        "מה צפוי לי עד סוף החודש?",
        "מי חייב לי כסף?",
        "על מה הוצאתי הכי הרבה החודש?",
        "רשום הוצאה של 50 ₪ על דלק",
        "דוד חייב לי עוד 80 ₪ על הדפסה",
    )

    fun systemPrompt(data: FinanceData, today: LocalDate): String = """
You are the personal-finance assistant inside the Android app "הכספים שלי" of one Israeli user.
Always answer in Hebrew, short and simple (the user likes explanations "like for a 3rd-grader"). Use ₪ and dates as DD/MM/YYYY.

Rules:
- Use ONLY the data snapshot below. If something is not in the data, say you don't know — never invent numbers.
- Keep actual money (in accounts now) separate from expected money, money owed to the user and money the user owes.
- Credit-card purchases are already expenses on the purchase date; the card bill paid from the bank is a transfer, not a new expense.
- Pending items are not real money yet.
- You are not a licensed financial adviser: give general, practical guidance only, no specific investment/securities recommendations.
- You cannot change anything yourself. When the user asks to record/add/update something, propose it with action tags (below) and say "לחץ אישור כדי לשמור". Never claim it was saved.
- If an amount or person is missing for an action, ask a short question instead of guessing.

Action tags — put each on its own line at the end of your answer, JSON inside, numbers without ₪, dates YYYY-MM-DD:
<action>{"type":"expense","amount":50,"title":"דלק","date":"${today}","category":"תחבורה ורכב","account":"<account name or omit>","person":"<optional>"}</action>
<action>{"type":"income","amount":900,"title":"צילום בר מצווה","date":"${today}","category":"עבודה עצמאית ואירועים","person":"<optional>"}</action>
<action>{"type":"new_debt","direction":"owed_to_me" or "i_owe","person":"דוד","amount":120,"title":"הדפסה","due":"YYYY-MM-DD or omit"}</action>
<action>{"type":"add_to_debt","person":"דוד","amount":80,"reason":"הדפסה נוספת"}</action>   (increase an existing open debt)
<action>{"type":"debt_payment","person":"דוד","amount":120,"date":"${today}","account":"<optional>"}</action>   (a payment that was received/paid on a debt)
<action>{"type":"event","title":"אירוע חתונה כהן","date":"YYYY-MM-DD","expected_income":2500,"person":"<optional>"}</action>

=== DATA SNAPSHOT ===
${context(data, today)}
""".trim()

    /** Plain-text snapshot of the user's finances for the model. */
    fun context(data: FinanceData, today: LocalDate): String = buildString {
        if (data.isDemo) appendLine("!!! DEMO DATA — not the user's real money. Mention this if asked about numbers.")
        appendLine("Today: ${today.il} (${today.dayOfWeek})")
        val month = SummaryCalculator.make(data, DateRange.month(today), today)
        val next30 = ForecastEngine.make(data, DateRange.next(30, today), today)
        appendLine()
        appendLine("## Totals")
        appendLine("Available now (bank+cash+Bit, actual): ${month.available.ils()}")
        appendLine("Credit-card debt not yet charged to bank: ${month.creditCardLiability.ils()}")
        appendLine("Owed to me (open receivables): ${month.receivables.ils()} (overdue ${month.overdueReceivables.ils()})")
        appendLine("I owe (open payables): ${month.payables.ils()}")
        appendLine("Savings: ${month.savings.ils()}")
        appendLine("Next 30 days: expected in ${next30.expectedIncome.ils()}, expected out ${next30.expectedExpenses.ils()}, projected balance on ${next30.range.end.il}: ${next30.ending.ils()}")
        next30.days.firstOrNull { it.projected.isNeg }?.let { appendLine("WARNING: projected balance goes negative on ${it.date.il}") }

        appendLine()
        appendLine("## Accounts (name | type | balance)")
        val balances = Ledger.balances(data.accounts, data.transactions)
        data.accounts.filter { it.isActive }.forEach { a ->
            appendLine("${a.name} | ${Labels.accountType(a.type)} | ${(balances[a.id] ?: ZERO).ils()}" + (if (!a.includeInAvailable) " | not in available" else "") +
                (a.billingDay?.let { " | card billed on day $it" } ?: ""))
        }

        appendLine()
        appendLine("## Last 3 months (income / expenses)")
        for (i in 0..2) {
            val m = today.minusMonths(i.toLong())
            val r = DateRange.month(m)
            val txs = data.transactions.filter { it.countsInReports && it.date in r }
            val inc = txs.filter { it.kind == TxKind.INCOME }.sumOfMoney { it.amount }
            val exp = txs.filter { it.kind == TxKind.EXPENSE }.sumOfMoney { it.amount }
            appendLine("%02d/%04d: in ${inc.ils()} / out ${exp.ils()}".format(m.monthValue, m.year))
        }
        val monthTx = data.transactions.filter { it.countsInReports && it.kind == TxKind.EXPENSE && it.date in DateRange.month(today) }
        if (monthTx.isNotEmpty()) {
            appendLine("This month's expenses by category: " + monthTx.groupBy { data.category(it.categoryId)?.name ?: "ללא קטגוריה" }
                .mapValues { (_, l) -> l.sumOfMoney { it.amount } }.entries.sortedByDescending { it.value }.joinToString("; ") { "${it.key} ${it.value.ils()}" })
        }

        val debts = data.debts.map { Debts.balance(it, data.debtPayments, today) }.filter { it.isOpen }
        appendLine()
        appendLine("## Open debts (person | direction | remaining of original | due | title)")
        if (debts.isEmpty()) appendLine("none")
        debts.forEach { b ->
            val d = b.debt
            appendLine("${data.contact(d.contactId)?.name ?: "?"} | ${if (d.direction == DebtDirection.RECEIVABLE) "owes me" else "I owe"} | ${b.remaining.ils()} of ${d.originalAmount.ils()} | " +
                (d.dueDate?.il ?: "-") + (if (b.isOverdue) " OVERDUE" else "") + " | ${d.title}")
        }

        val events = data.events.filter { it.date >= today.minusDays(30) && it.date <= today.plusDays(60) }.sortedBy { it.date }
        appendLine()
        appendLine("## Events (last 30 days, next 60 days): date | title | expected income | payment status | client")
        if (events.isEmpty()) appendLine("none")
        events.forEach { e ->
            val f = Events.financials(e, data.transactions)
            appendLine("${e.date.il} | ${e.title} | ${e.expectedIncome?.ils() ?: "-"} | ${Labels.eventPayment(f.paymentStatus)}" +
                (if (f.receivedIncome.isPos) " (received ${f.receivedIncome.ils()})" else "") + " | ${data.contact(e.contactId)?.name ?: "-"}")
        }

        appendLine()
        appendLine("## Upcoming in 30 days (date | title | amount | confidence)")
        next30.items.sortedBy { it.date }.take(30).forEach { appendLine("${it.date.il} | ${it.title} | ${it.amount.ils()} | ${Labels.confidence(it.confidence)}" + if (it.isOverdue) " | overdue" else "") }

        val recent = data.transactions.filter { it.status != TxStatus.CANCELLED && it.date >= today.minusDays(90) && it.date <= today }
            .sortedByDescending { it.date }.take(MAX_TRANSACTIONS)
        appendLine()
        appendLine("## Recent transactions (newest first, max $MAX_TRANSACTIONS): date | kind | amount | title | category | account | person")
        recent.forEach { t ->
            appendLine("${t.date.il} | ${Labels.kind(t.kind)}${if (t.status == TxStatus.PENDING) " (pending)" else ""} | ${t.amount.ils()} | ${t.title} | " +
                "${data.category(t.categoryId)?.name ?: "-"} | ${data.account(t.accountId)?.name ?: "-"}" +
                (t.counterAccountId?.let { " → ${data.account(it)?.name}" } ?: "") + " | ${data.contact(t.contactId)?.name ?: "-"}")
        }

        appendLine()
        appendLine("Expense categories: " + data.categories.filter { it.kind == CategoryKind.EXPENSE && !it.isArchived }.joinToString(", ") { it.name })
        appendLine("Income categories: " + data.categories.filter { it.kind == CategoryKind.INCOME && !it.isArchived }.joinToString(", ") { it.name })
        appendLine("People: " + data.contacts.joinToString(", ") { it.name }.ifEmpty { "none" })
    }

    // ---------------- parsing the reply ----------------

    private val tag = Regex("""<action>\s*(\{.*?\})\s*</action>""", RegexOption.DOT_MATCHES_ALL)
    private val fence = Regex("""```(?:action|json)\s*(\{.*?\})\s*```""", RegexOption.DOT_MATCHES_ALL)

    fun parse(raw: String): AssistantReply {
        val blocks = tag.findAll(raw).toList().ifEmpty { fence.findAll(raw).filter { it.groupValues[1].contains("\"type\"") }.toList() }
        val actions = blocks.mapNotNull { m -> runCatching { Json.parseToJsonElement(m.groupValues[1]).jsonObject }.getOrNull()?.let(::action) }
        var text = raw
        blocks.forEach { text = text.replace(it.value, "") }
        return AssistantReply(text.replace(Regex("\n{3,}"), "\n\n").trim(), actions)
    }

    private fun JsonObject.str(vararg keys: String): String? = keys.firstNotNullOfOrNull { k -> (this[k] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content?.trim()?.takeIf { it.isNotEmpty() } }
    private fun JsonObject.money(vararg keys: String): Money? = keys.firstNotNullOfOrNull { k ->
        (this[k] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content?.let { MoneyText.parse(it) ?: it.toBigDecimalOrNull() }
    }?.abs2()?.takeIf { it.isPos }
    private fun JsonObject.date(vararg keys: String): LocalDate? = keys.firstNotNullOfOrNull { k -> DateText.flexible(str(k)) }

    private fun action(o: JsonObject): ProposedAction? {
        val type = o.str("type")?.lowercase() ?: return null
        return when (type) {
            "expense", "income" -> {
                val amount = o.money("amount") ?: return null
                ProposedAction.AddTransaction(if (type == "income") TxKind.INCOME else TxKind.EXPENSE, amount, o.str("title", "description") ?: Labels.kind(if (type == "income") TxKind.INCOME else TxKind.EXPENSE),
                    o.date("date"), o.str("category"), o.str("account"), o.str("person", "contact"))
            }
            "new_debt", "debt" -> {
                val amount = o.money("amount") ?: return null
                val person = o.str("person", "contact") ?: return null
                val dir = if (o.str("direction")?.lowercase()?.let { it.contains("i_owe") || it == "payable" } == true) DebtDirection.PAYABLE else DebtDirection.RECEIVABLE
                ProposedAction.AddDebt(dir, person, amount, o.str("title", "reason") ?: "חוב", o.date("due", "due_date"))
            }
            "add_to_debt", "increase_debt", "charge" -> ProposedAction.AddCharge(o.str("person", "contact") ?: return null, o.money("amount") ?: return null, o.str("reason", "title").orEmpty())
            "debt_payment", "payment" -> ProposedAction.DebtPayment(o.str("person", "contact") ?: return null, o.money("amount") ?: return null, o.date("date"), o.str("account"))
            "event" -> ProposedAction.AddEvent(o.str("title") ?: return null, o.date("date") ?: return null, o.money("expected_income", "expectedIncome"), o.str("person", "contact"))
            else -> null
        }
    }

    // ---------------- resolving names to records ----------------

    private fun norm(s: String) = s.trim().replace("\"", "").replace("׳", "'").lowercase()

    fun findContact(data: FinanceData, name: String): Contact? {
        val n = norm(name)
        return data.contacts.firstOrNull { norm(it.name) == n }
            ?: data.contacts.filter { norm(it.name).contains(n) || n.contains(norm(it.name)) }.singleOrNull()
            ?: data.contacts.filter { c -> norm(c.name).split(Regex("\\s+")).any { w -> w.length >= 2 && n.split(Regex("\\s+")).contains(w) } }.singleOrNull()
    }

    fun findAccount(data: FinanceData, name: String?): Account? {
        val n = name?.let(::norm)?.takeIf { it.isNotEmpty() } ?: return null
        val active = data.accounts.filter { it.isActive }
        return active.firstOrNull { norm(it.name) == n } ?: active.filter { norm(it.name).contains(n) || n.contains(norm(it.name)) }.singleOrNull()
    }

    fun findCategory(data: FinanceData, name: String?, kind: TxKind): Category? {
        val ck = if (kind == TxKind.INCOME) CategoryKind.INCOME else CategoryKind.EXPENSE
        val list = data.categories.filter { it.kind == ck && !it.isArchived }
        val n = name?.let(::norm)?.takeIf { it.isNotEmpty() } ?: return null
        return list.firstOrNull { norm(it.name) == n } ?: list.filter { norm(it.name).contains(n) || n.contains(norm(it.name)) }.singleOrNull()
    }

    /** The open debt a payment / extra charge refers to: oldest open one for that person. */
    fun findOpenDebt(data: FinanceData, person: String, today: LocalDate, direction: DebtDirection? = null): Debt? {
        val c = findContact(data, person) ?: return null
        return data.debts.filter { it.contactId == c.id && (direction == null || it.direction == direction) }
            .filter { Debts.balance(it, data.debtPayments, today).isOpen }.minByOrNull { it.issuedDate }
    }
}

/** Adds an extra charge to an existing debt and keeps a dated note of it. */
fun Debt.withCharge(amount: Money, reason: String, date: LocalDate): Debt {
    val line = "%02d/%02d/%04d: נוסף %s".format(date.dayOfMonth, date.monthValue, date.year, MoneyFormatter.format(amount)) + (if (reason.isNotBlank()) " — $reason" else "")
    return copy(originalAmount = (originalAmount + amount).m2(), notes = listOf(notes, line).filter { it.isNotBlank() }.joinToString("\n"), closedStatus = null)
}

// ---------------- provider chat requests ----------------

internal object ChatRequests {
    fun history(messages: List<ChatMessage>) = messages.takeLast(Assistant.MAX_HISTORY).dropWhile { it.role == ChatRole.ASSISTANT }

    fun gemini(baseUrl: String, model: String, key: String, system: String, messages: List<ChatMessage>): HttpRequest {
        if (key.isBlank()) throw AIError.missingKey
        val body = buildJsonObject {
            putJsonObject("systemInstruction") { putJsonArray("parts") { addJsonObject { put("text", system) } } }
            putJsonArray("contents") {
                history(messages).forEach { m -> addJsonObject { put("role", if (m.role == ChatRole.USER) "user" else "model"); putJsonArray("parts") { addJsonObject { put("text", m.text) } } } }
            }
            putJsonObject("generationConfig") { put("temperature", 0.3) }
        }
        val path = if (model.startsWith("models/")) model else "models/$model"
        return HttpRequest("$baseUrl/v1beta/$path:generateContent", "POST", mapOf("x-goog-api-key" to key), body.toString())
    }

    fun openAI(baseUrl: String, model: String, headers: Map<String, String>, system: String, messages: List<ChatMessage>): HttpRequest {
        if (model.isBlank()) throw AIError.invalid("לא נבחר מודל")
        val body = buildJsonObject {
            put("model", model)
            putJsonArray("messages") {
                addJsonObject { put("role", "system"); put("content", system) }
                history(messages).forEach { m -> addJsonObject { put("role", if (m.role == ChatRole.USER) "user" else "assistant"); put("content", m.text) } }
            }
            put("temperature", 0.3)
        }
        return HttpRequest("${baseUrl.trimEnd('/')}/chat/completions", "POST", headers, body.toString())
    }

    fun anthropic(baseUrl: String, model: String, headers: Map<String, String>, key: String, system: String, messages: List<ChatMessage>): HttpRequest {
        if (key.isBlank()) throw AIError.missingKey
        val body = buildJsonObject {
            put("model", model); put("max_tokens", 4000); put("system", system)
            putJsonArray("messages") {
                history(messages).forEach { m -> addJsonObject { put("role", if (m.role == ChatRole.USER) "user" else "assistant"); put("content", m.text) } }
            }
            put("fallbacks", "default")
        }
        return HttpRequest("$baseUrl/v1/messages", "POST", headers, body.toString())
    }
}

private fun String.toBigDecimalOrNull(): BigDecimal? = runCatching { BigDecimal(this.replace(",", "")) }.getOrNull()
