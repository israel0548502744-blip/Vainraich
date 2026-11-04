package com.vainraich.finance

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.vainraich.core.*
import com.vainraich.core.ai.*
import com.vainraich.finance.ui.ils
import com.vainraich.finance.services.Reminders
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.LocalDate

/** Navigation targets pushed on top of the tabs. */
sealed class Route {
    data object Forecast : Route()
    data object Accounts : Route()
    data class AccountDetail(val id: String) : Route()
    data class EditAccount(val id: String?) : Route()
    data class EditTransaction(val id: String?, val kind: TxKind = TxKind.EXPENSE, val eventId: String? = null) : Route()
    data object Recurring : Route()
    data class EditRule(val id: String?) : Route()
    data class EventDetail(val id: String) : Route()
    data class EditEvent(val id: String?, val date: LocalDate? = null) : Route()
    data object PaymentReview : Route()
    data class DebtDetail(val id: String) : Route()
    data class EditDebt(val id: String?, val direction: DebtDirection = DebtDirection.RECEIVABLE) : Route()
    data object Contacts : Route()
    data class ContactDetail(val id: String) : Route()
    data object Reports : Route()
    data object Import : Route()
    data object Categories : Route()
    data object Settings : Route()
    data object AiSettings : Route()
    data object CalendarSettings : Route()
    data object NotificationSettings : Route()
    data object Integrations : Route()
    data object Chat : Route()
}

enum class Tab { HOME, CALENDAR, TRANSACTIONS, DEBTS, MORE }

enum class Mode { PERSONAL, DEMO }

/** Single source of truth. Every change goes through here (validation, saving, reminders). */
class AppViewModel(app: Application) : AndroidViewModel(app) {
    private val store = FileStore(File(app.filesDir, "finance/finance.json"))
    private val prefs = app.getSharedPreferences("app", 0)

    var data by mutableStateOf(FinanceData())
        private set
    var mode by mutableStateOf(Mode.PERSONAL)
        private set
    var today by mutableStateOf(LocalDate.now())
        private set
    var tab by mutableStateOf(Tab.HOME)
    val stack = mutableStateListOf<Route>()
    var toast by mutableStateOf<String?>(null)
    var error by mutableStateOf<String?>(null)
    var hasOnboarded by mutableStateOf(prefs.getBoolean("onboarded", false))
        private set
    /** A document shared into the app from another app (opens the import screen). */
    var sharedDocument by mutableStateOf<com.vainraich.finance.services.PickedDoc?>(null)

    private var saveJob: Job? = null

    init {
        if (store.exists()) {
            try { data = store.load(); if (!hasOnboarded) setOnboarded(true) }
            catch (e: Exception) { error = "לא הצלחתי לקרוא את קובץ הנתונים. הקובץ לא נמחק — אפשר לשחזר מגיבוי בהגדרות." }
        }
        materializeRecurring()
    }

    // ---------- navigation ----------
    fun push(r: Route) { stack.add(r) }
    fun pop() { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) }
    fun popTo(predicate: (Route) -> Boolean) { while (stack.isNotEmpty() && !predicate(stack.last())) stack.removeAt(stack.lastIndex) }
    fun show(msg: String) {
        toast = msg
        viewModelScope.launch { delay(2300); if (toast == msg) toast = null }
    }

    // ---------- persistence ----------
    private fun update(f: (FinanceData) -> FinanceData) {
        data = f(data)
        changed()
    }

    private fun changed() {
        if (mode == Mode.DEMO) return
        saveJob?.cancel()
        saveJob = viewModelScope.launch {
            delay(400)
            persistNow()
        }
        Reminders.schedule(getApplication())
    }

    fun persistNow() {
        if (mode == Mode.DEMO) return
        val snapshot = data
        viewModelScope.launch(Dispatchers.IO) {
            try { store.save(snapshot) } catch (e: Exception) { withContext(Dispatchers.Main) { error = "השמירה נכשלה: ${e.message}" } }
        }
    }

    fun setOnboarded(v: Boolean) { hasOnboarded = v; prefs.edit().putBoolean("onboarded", v).apply() }

    fun refreshDay() { today = LocalDate.now(); materializeRecurring() }

    fun reloadIfChanged() {
        if (mode != Mode.PERSONAL || !store.exists()) return
        runCatching { store.load() }.getOrNull()?.let { if (it != data && saveJob?.isActive != true) data = it }
    }

    private fun materializeRecurring() {
        val created = Recurrence.materialize(data.recurringRules, today, data.transactions)
        if (created.isNotEmpty()) update { it.copy(transactions = it.transactions + created) }
    }

    fun enterDemo() { persistNow(); mode = Mode.DEMO; data = DemoData.make(today); stack.clear(); tab = Tab.HOME }
    fun exitDemo() {
        mode = Mode.PERSONAL
        data = if (store.exists()) runCatching { store.load() }.getOrElse { FinanceData() } else FinanceData()
        stack.clear(); tab = Tab.HOME
        if (!store.exists()) setOnboarded(false)
    }

    fun eraseAll() {
        saveJob?.cancel(); store.delete()
        File(getApplication<Application>().filesDir, "attachments").deleteRecursively()
        data = FinanceData(); mode = Mode.PERSONAL; stack.clear(); tab = Tab.HOME; setOnboarded(false)
    }

    fun replaceAll(backup: FinanceData) { data = backup.copy(isDemo = false); mode = Mode.PERSONAL; changed(); setOnboarded(true) }
    fun backupJson(): String = FinanceJson.encode(data)

    // ---------- derived ----------
    val activeAccounts: List<Account> get() = data.accounts.filter { it.isActive }.sortedWith(compareBy({ it.sortOrder }, { it.name }))
    val balances: Map<String, Money> get() = Ledger.balances(data.accounts, data.transactions)
    fun balance(id: String): Money = data.account(id)?.let { Ledger.balance(it, data.transactions) } ?: ZERO
    fun summary(period: DateRange) = SummaryCalculator.make(data, period, today)
    fun forecast(range: DateRange) = ForecastEngine.make(data, range, today)
    fun debtBalance(d: Debt) = Debts.balance(d, data.debtPayments, today)
    val defaultAccountId: String? get() = activeAccounts.firstOrNull { it.includeInAvailable }?.id ?: activeAccounts.firstOrNull()?.id
    val paymentQuestions: List<PaymentQuestion> get() = EventMatcher.questions(data, today)

    // ---------- transactions ----------
    fun save(t0: Transaction) {
        var t = t0.copy(title = t0.title.trim(), amount = t0.amount.m2(), updatedAt = System.currentTimeMillis())
        t = if (t.kind == TxKind.TRANSFER) t.copy(categoryId = null) else t.copy(counterAccountId = null)
        t.validate(data)
        update { d ->
            val exists = d.transactions.any { it.id == t.id }
            d.copy(
                transactions = if (exists) d.transactions.map { if (it.id == t.id) t else it } else d.transactions + t,
                debtPayments = d.debtPayments.map { if (it.transactionId == t.id) it.copy(amount = t.amount, date = t.date) else it },
            )
        }
    }

    fun deleteTransaction(id: String) {
        data.transaction(id)?.attachmentFile?.let { File(getApplication<Application>().filesDir, "attachments/$it").delete() }
        update { d -> d.copy(transactions = d.transactions.filter { it.id != id }, debtPayments = d.debtPayments.filter { it.transactionId != id }) }
    }

    fun confirm(id: String, date: LocalDate? = null) = update { d ->
        d.copy(transactions = d.transactions.map { if (it.id == id) it.copy(status = TxStatus.COMPLETED, date = date ?: it.date, updatedAt = System.currentTimeMillis()) else it })
    }

    // ---------- accounts ----------
    fun save(a0: Account) {
        var a = a0.copy(name = a0.name.trim())
        a.validate()
        if (a.type != AccountType.CREDIT_CARD) a = a.copy(billingDay = null, paymentAccountId = null, creditLimit = null)
        update { d ->
            if (d.accounts.any { it.id == a.id }) d.copy(accounts = d.accounts.map { if (it.id == a.id) a else it })
            else d.copy(accounts = d.accounts + a.copy(sortOrder = (d.accounts.maxOfOrNull { it.sortOrder } ?: -1) + 1))
        }
    }

    fun accountHasHistory(id: String) = data.transactions.any { it.accountId == id || it.counterAccountId == id } || data.recurringRules.any { it.accountId == id || it.counterAccountId == id }

    fun deleteOrDeactivate(id: String) = update { d ->
        if (accountHasHistory(id)) d.copy(accounts = d.accounts.map { if (it.id == id) it.copy(isActive = false) else it })
        else d.copy(accounts = d.accounts.filter { it.id != id })
    }

    /** Sets the real balance by recording an adjustment (never income/expense). */
    fun setBalance(accountId: String, newBalance: Money, date: LocalDate) {
        val diff = (newBalance - balance(accountId)).m2()
        if (diff.signum() == 0) return
        save(Transaction(kind = TxKind.ADJUSTMENT, amount = diff.abs2(), adjustmentIsNegative = diff.isNeg, accountId = accountId, title = "עדכון יתרה ידני", date = date))
    }

    // ---------- contacts & categories ----------
    fun addContact(c: Contact): Contact { update { it.copy(contacts = it.contacts + c) }; return c }
    fun findOrAddContact(name: String, phone: String? = null, systemId: String? = null): Contact =
        data.contacts.firstOrNull { (systemId != null && it.systemContactId == systemId) || it.name == name } ?: addContact(Contact(name = name, phone = phone, systemContactId = systemId))
    fun contactInUse(id: String) = data.debts.any { it.contactId == id } || data.transactions.any { it.contactId == id } || data.events.any { it.contactId == id }
    fun deleteContact(id: String) {
        if (contactInUse(id)) { error = "אי אפשר למחוק איש קשר שיש לו חובות, אירועים או תנועות."; return }
        update { d -> d.copy(contacts = d.contacts.filter { it.id != id }) }
    }
    fun save(c: Category) = update { d -> if (d.categories.any { it.id == c.id }) d.copy(categories = d.categories.map { if (it.id == c.id) c else it }) else d.copy(categories = d.categories + c) }

    // ---------- recurring ----------
    fun save(r: RecurringRule) {
        Recurrence.makeTransaction(r, r.startDate, TxStatus.PENDING).validate(data)
        update { d -> if (d.recurringRules.any { it.id == r.id }) d.copy(recurringRules = d.recurringRules.map { if (it.id == r.id) r else it }) else d.copy(recurringRules = d.recurringRules + r) }
        materializeRecurring()
    }

    fun deleteRule(id: String) = update { d ->
        d.copy(recurringRules = d.recurringRules.filter { it.id != id }, transactions = d.transactions.filter { !(it.recurringId == id && it.status == TxStatus.PENDING) })
    }

    // ---------- events ----------
    fun save(e0: FinanceEvent) {
        val e = e0.copy(title = e0.title.trim()); e.validate()
        update { d -> if (d.events.any { it.id == e.id }) d.copy(events = d.events.map { if (it.id == e.id) e else it }) else d.copy(events = d.events + e) }
    }

    fun deleteEvent(id: String) = update { d ->
        d.copy(events = d.events.filter { it.id != id }, transactions = d.transactions.map { if (it.eventId == id) it.copy(eventId = null) else it },
            debts = d.debts.map { if (it.eventId == id) it.copy(eventId = null) else it })
    }

    private fun updateEvent(id: String, f: (FinanceEvent) -> FinanceEvent) = update { d -> d.copy(events = d.events.map { if (it.id == id) f(it) else it }) }

    fun recordEventPayment(eventId: String, kind: TxKind, amount: Money, accountId: String, date: LocalDate, method: PaymentMethod?) {
        val e = data.event(eventId) ?: return
        if (kind == TxKind.INCOME) updateEvent(eventId) { it.copy(isIncomeEvent = true) }
        val debtId = e.debtId
        if (kind == TxKind.INCOME && debtId != null && data.debt(debtId) != null) { recordDebtPayment(debtId, amount, date, accountId); return }
        save(Transaction(kind = kind, amount = amount, accountId = accountId, categoryId = if (kind == TxKind.INCOME) DefaultCategories.SELF_EMPLOYED_INCOME else null,
            contactId = e.contactId, title = e.title, date = date, paymentMethod = method, eventId = eventId, source = TxSource.EVENT_PAYMENT))
    }

    fun createReceivable(eventId: String, contactId: String, due: LocalDate?) {
        val e = data.event(eventId) ?: return
        val f = Events.financials(e, data.transactions)
        if (!f.outstandingIncome.isPos) throw ValidationError.NonPositiveAmount
        val debt = Debt(direction = DebtDirection.RECEIVABLE, contactId = contactId, title = e.title, originalAmount = f.outstandingIncome, issuedDate = today, dueDate = due ?: e.date, eventId = eventId)
        update { d -> d.copy(debts = d.debts + debt, events = d.events.map { if (it.id == eventId) it.copy(debtId = debt.id, contactId = it.contactId ?: contactId) else it }) }
    }

    /** User confirmed: this income is (part of) the payment for the event. */
    fun confirmMatch(txId: String, eventId: String) {
        val e = data.event(eventId) ?: return
        val t = data.transaction(txId) ?: return
        update { d ->
            var payments = d.debtPayments
            e.debtId?.let { debtId -> d.debt(debtId)?.let { debt ->
                val b = Debts.balance(debt, d.debtPayments, today)
                if (b.isOpen && b.remaining.isPos && d.debtPayments.none { it.transactionId == txId })
                    payments = payments + DebtPayment(debtId = debtId, amount = t.amount.min(b.remaining), date = t.date, transactionId = txId)
            } }
            d.copy(
                transactions = d.transactions.map { if (it.id == txId) it.copy(eventId = eventId, contactId = it.contactId ?: e.contactId) else it },
                events = d.events.map { if (it.id == eventId) it.copy(isIncomeEvent = true) else it },
                debtPayments = payments,
            )
        }
    }

    fun rejectMatch(txId: String, eventId: String) = updateEvent(eventId) { if (txId in it.rejectedTransactionIds) it else it.copy(rejectedTransactionIds = it.rejectedTransactionIds + txId) }
    fun markNotIncomeEvent(eventId: String) = updateEvent(eventId) { it.copy(isIncomeEvent = false) }
    fun markAwaitingPayment(eventId: String, expected: Money?) = updateEvent(eventId) { it.copy(isIncomeEvent = true, expectedIncome = if (expected != null && expected.isPos) expected.m2() else it.expectedIncome) }
    fun setCalendarId(eventId: String, calId: Long?) = updateEvent(eventId) { it.copy(calendarEventId = calId) }

    fun importEvents(events: List<FinanceEvent>): Int {
        val known = data.events.mapNotNull { it.calendarEventId }.toSet()
        val fresh = events.filter { it.calendarEventId == null || it.calendarEventId !in known }
        if (fresh.isNotEmpty()) update { it.copy(events = it.events + fresh) }
        return fresh.size
    }

    // ---------- debts ----------
    fun save(d0: Debt) {
        val d = d0.copy(title = d0.title.trim(), originalAmount = d0.originalAmount.m2())
        if (d.title.isEmpty()) throw ValidationError.EmptyTitle
        if (!d.originalAmount.isPos) throw ValidationError.NonPositiveAmount
        val paid = data.paymentsFor(d.id).sumOfMoney { it.amount }
        if (d.originalAmount < paid) throw ValidationError.PaymentExceedsRemaining(paid)
        update { x -> if (x.debts.any { it.id == d.id }) x.copy(debts = x.debts.map { if (it.id == d.id) d else it }) else x.copy(debts = x.debts + d) }
    }

    fun recordDebtPayment(debtId: String, amount: Money, date: LocalDate, accountId: String, notes: String = "") {
        val (p, t) = Debts.recordPayment(debtId, amount, date, accountId, notes, data, today)
        update { it.copy(transactions = it.transactions + t, debtPayments = it.debtPayments + p) }
    }

    fun deletePayment(id: String) {
        val p = data.debtPayments.firstOrNull { it.id == id } ?: return
        update { d -> d.copy(debtPayments = d.debtPayments.filter { it.id != id }, transactions = d.transactions.filter { it.id != p.transactionId }) }
    }

    fun setClosedStatus(debtId: String, s: DebtStatus?) = update { d -> d.copy(debts = d.debts.map { if (it.id == debtId) it.copy(closedStatus = s) else it }) }

    fun deleteDebt(id: String) = update { d ->
        d.copy(debts = d.debts.filter { it.id != id }, debtPayments = d.debtPayments.filter { it.debtId != id }, events = d.events.map { if (it.debtId == id) it.copy(debtId = null) else it })
    }

    // ---------- import ----------
    fun applyImport(txs: List<Transaction>, adjustments: List<Transaction>): Int {
        (txs + adjustments).forEach { it.validate(data) }
        val target = (txs + adjustments).firstOrNull()?.accountId
        update { d -> d.copy(transactions = d.transactions + txs + adjustments, accounts = d.accounts.map { if (it.id == target) it.copy(lastSyncedAt = System.currentTimeMillis()) else it }) }
        return txs.size + adjustments.size
    }

    fun updateSettings(s: FinanceSettings) = update { it.copy(settings = s) }

    // ---------- debts: extra charges ----------
    fun addCharge(debtId: String, amount: Money, reason: String, date: LocalDate = today) {
        val d = data.debt(debtId) ?: return
        if (!amount.isPos) throw ValidationError.NonPositiveAmount
        save(d.withCharge(amount.m2(), reason.trim(), date))
    }

    // ---------- AI assistant chat ----------
    data class ChatEntry(
        val role: ChatRole, val text: String, val actions: List<ProposedAction> = emptyList(),
        /** index -> result message once confirmed / "בוטל" once dismissed */
        val resolved: Map<Int, String> = emptyMap(), val isError: Boolean = false, val id: String = newId(),
    )
    val chat = mutableStateListOf<ChatEntry>()
    var chatBusy by mutableStateOf(false)
        private set

    fun sendChat(text: String, onAnswer: (String) -> Unit = {}) {
        val q = text.trim()
        if (q.isEmpty() || chatBusy) return
        chat.add(ChatEntry(ChatRole.USER, q))
        val provider = runCatching { com.vainraich.finance.services.AiSettings(getApplication()).extractor() }.getOrElse { e ->
            chat.add(ChatEntry(ChatRole.ASSISTANT, (e as? AIError)?.hebrew ?: (e.message ?: "שגיאה"), isError = true)); return
        } as? ChatProvider
        if (provider == null) {
            chat.add(ChatEntry(ChatRole.ASSISTANT, "כדי לדבר איתי צריך לבחור ספק בינה מלאכותית (למשל Gemini החינמי) בהגדרות ← בינה מלאכותית.", isError = true)); return
        }
        val history = chat.filter { !it.isError }.map { ChatMessage(it.role, it.text + it.actions.joinToString("") { a -> "\n[הצעה: ${a.summary}]" }) }
        val system = Assistant.systemPrompt(data, today)
        chatBusy = true
        viewModelScope.launch {
            try {
                val raw = withContext(Dispatchers.IO) { provider.chat(system, history) }
                val r = Assistant.parse(raw)
                val shown = r.text.ifBlank { if (r.actions.isNotEmpty()) "הנה מה שאני מציע לרשום:" else "…" }
                chat.add(ChatEntry(ChatRole.ASSISTANT, shown, r.actions))
                onAnswer(shown)
            } catch (e: AIError) {
                chat.add(ChatEntry(ChatRole.ASSISTANT, e.hebrew, isError = true))
            } catch (e: Exception) {
                chat.add(ChatEntry(ChatRole.ASSISTANT, e.message ?: "שגיאה", isError = true))
            } finally { chatBusy = false }
        }
    }

    fun clearChat() { if (!chatBusy) chat.clear() }

    private fun resolve(entryId: String, index: Int, msg: String) {
        val i = chat.indexOfFirst { it.id == entryId }
        if (i >= 0) chat[i] = chat[i].copy(resolved = chat[i].resolved + (index to msg))
    }

    fun dismissAction(entryId: String, index: Int) = resolve(entryId, index, "בוטל")

    /** The user tapped "confirm" on a suggestion — only now is anything saved. */
    fun confirmAction(entryId: String, index: Int) {
        val a = chat.firstOrNull { it.id == entryId }?.actions?.getOrNull(index) ?: return
        var msg = "נשמר ✓"
        val ok = attempt {
            when (a) {
                is ProposedAction.AddTransaction -> {
                    val acc = Assistant.findAccount(data, a.account)?.id ?: defaultAccountId ?: throw ValidationError.UnknownAccount
                    val cat = Assistant.findCategory(data, a.category, a.kind)?.id ?: if (a.kind == TxKind.INCOME) "i06" else "e13"
                    val contact = a.person?.let { (Assistant.findContact(data, it) ?: addContact(Contact(name = it))).id }
                    save(Transaction(kind = a.kind, amount = a.amount, accountId = acc, categoryId = cat, contactId = contact, title = a.title, date = a.date ?: today))
                    msg = "נשמר ✓ (${data.account(acc)?.name})"
                }
                is ProposedAction.AddDebt -> {
                    val c = Assistant.findContact(data, a.person) ?: addContact(Contact(name = a.person))
                    save(Debt(direction = a.direction, contactId = c.id, title = a.title, originalAmount = a.amount, issuedDate = today, dueDate = a.dueDate))
                }
                is ProposedAction.AddCharge -> {
                    val d = Assistant.findOpenDebt(data, a.person, today, DebtDirection.RECEIVABLE) ?: Assistant.findOpenDebt(data, a.person, today)
                    if (d != null) { addCharge(d.id, a.amount, a.reason); msg = "נוסף לחוב ✓ (עכשיו ${debtBalance(data.debt(d.id)!!).remaining.ils()})" }
                    else {
                        val c = Assistant.findContact(data, a.person) ?: addContact(Contact(name = a.person))
                        save(Debt(direction = DebtDirection.RECEIVABLE, contactId = c.id, title = a.reason.ifBlank { "חוב" }, originalAmount = a.amount, issuedDate = today))
                        msg = "לא היה חוב פתוח — נפתח חוב חדש ✓"
                    }
                }
                is ProposedAction.DebtPayment -> {
                    val d = Assistant.findOpenDebt(data, a.person, today) ?: throw IllegalStateException("לא מצאתי חוב פתוח של ${a.person}.")
                    val acc = Assistant.findAccount(data, a.account)?.id ?: defaultAccountId ?: throw ValidationError.UnknownAccount
                    recordDebtPayment(d.id, a.amount, a.date ?: today, acc)
                    msg = "התשלום נרשם ✓"
                }
                is ProposedAction.AddEvent -> {
                    val c = a.person?.let { (Assistant.findContact(data, it) ?: addContact(Contact(name = it))).id }
                    save(FinanceEvent(title = a.title, date = a.date, expectedIncome = a.expectedIncome, contactId = c, isIncomeEvent = if (a.expectedIncome != null) true else null))
                }
            }
        }
        if (ok) resolve(entryId, index, msg)
    }

    /** Runs a mutation and shows a Hebrew error instead of crashing. */
    fun attempt(block: () -> Unit): Boolean = try { block(); true } catch (e: ValidationError) { error = e.hebrew; false } catch (e: Exception) { error = e.message ?: "שגיאה"; false }
}
