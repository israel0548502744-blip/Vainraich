package com.vainraich.finance.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.vainraich.core.*
import com.vainraich.finance.*
import com.vainraich.finance.services.CalendarSync
import com.vainraich.finance.ui.*
import com.vainraich.finance.ui.Card
import java.time.LocalDate

enum class CalMode(val title: String) { MONTH("חודש"), WEEK("שבוע"), DAY("יום") }

@Composable
fun CalendarScreen(vm: AppViewModel) {
    var mode by remember { mutableStateOf(CalMode.MONTH) }
    var selected by remember { mutableStateOf(vm.today) }
    var anchor by remember { mutableStateOf(vm.today) }
    fun step(n: Long) { when (mode) { CalMode.MONTH -> { anchor = anchor.startOfMonth().plusMonths(n); selected = anchor }; CalMode.WEEK -> { anchor = anchor.plusWeeks(n); selected = anchor }; CalMode.DAY -> { selected = selected.plusDays(n); anchor = selected } } }
    val q = vm.paymentQuestions.size
    ScreenScaffold("יומן", actions = {
        TextButton(onClick = { selected = vm.today; anchor = vm.today }) { Text("היום") }
        IconButton(onClick = { vm.push(Route.PaymentReview) }) {
            BadgedBox(badge = { if (q > 0) Badge { Text("$q") } }) { Icon(Icons.Outlined.EventAvailable, "אירועים לאישור תשלום") }
        }
        IconButton(onClick = { vm.push(Route.EditEvent(null, selected)) }) { Icon(Icons.Outlined.Add, "אירוע חדש") }
    }) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { DemoBanner(vm) }
            item { Segmented(CalMode.entries, mode, { it.title }, { mode = it }) }
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { step(-1) }) { Icon(Icons.Outlined.ChevronRight, "הקודם") }
                    Text(when (mode) {
                        CalMode.MONTH -> "${Labels.month(anchor.monthValue)} ${anchor.year}"
                        CalMode.WEEK -> DateRange.week(anchor).let { "${it.start.dayOfMonth}–${it.end.dayOfMonth} ב${Labels.month(it.end.monthValue)}" }
                        CalMode.DAY -> selected.weekdayAndDay()
                    }, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                    IconButton(onClick = { step(1) }) { Icon(Icons.Outlined.ChevronLeft, "הבא") }
                }
            }
            if (mode != CalMode.DAY) item {
                Card(padding = 10.dp) {
                    Row { Labels.weekdayShort.forEach { Text(it, style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center) } }
                    val days: List<LocalDate?> = if (mode == CalMode.MONTH) {
                        val first = anchor.startOfMonth()
                        List(first.weekdaySun1 - 1) { null } + (0 until first.lengthOfMonth()).map { first.plusDays(it.toLong()) }
                    } else DateRange.week(anchor).days
                    days.chunked(7).forEach { week ->
                        Row { (0 until 7).forEach { i -> Box(Modifier.weight(1f)) { week.getOrNull(i)?.let { DayCell(vm, it, it == selected) { selected = it } } } } }
                    }
                }
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                    LegendDot(Palette.expected, "הכנסה צפויה"); LegendDot(Palette.actual, "שולם"); LegendDot(Palette.liability, "הוצאה"); LegendDot(Palette.receivable, "מועד חוב")
                }
            }
            val visible = if (mode == CalMode.WEEK) DateRange.week(anchor).days else listOf(selected)
            visible.forEach { d ->
                val events = vm.data.events.filter { it.date == d }.sortedBy { it.startTime?.minutes ?: 0 }
                val dues = vm.data.debts.filter { it.dueDate == d && vm.debtBalance(it).isOpen }
                val items = if (d.isBefore(vm.today)) emptyList() else vm.forecast(DateRange.day(d)).items.filter { it.source is ForecastSource.Pending || it.source is ForecastSource.Recurring || it.source is ForecastSource.CardBill }
                if (mode == CalMode.WEEK && events.isEmpty() && dues.isEmpty() && items.isEmpty()) return@forEach
                item(key = "day-$d") {
                    Card {
                        Text(if (d == vm.today) "היום · ${d.weekdayAndDay()}" else d.weekdayAndDay(), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        if (events.isEmpty() && dues.isEmpty() && items.isEmpty()) Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("אין אירועים", color = Palette.secondaryText, modifier = Modifier.weight(1f))
                            TextButton(onClick = { vm.push(Route.EditEvent(null, d)) }) { Text("הוספת אירוע") }
                        }
                        events.forEach { e -> EventRow(vm, e) { vm.push(Route.EventDetail(e.id)) } }
                        dues.forEach { debt ->
                            Row(Modifier.fillMaxWidth().clickable { vm.push(Route.DebtDetail(debt.id)) }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                IconBubble(Icons.Outlined.PersonPin, Palette.receivable, 32.dp)
                                val name = vm.data.contact(debt.contactId)?.name.orEmpty()
                                Column(Modifier.weight(1f)) {
                                    Text(if (debt.direction == DebtDirection.RECEIVABLE) "$name אמור להחזיר" else "לשלם ל$name")
                                    Text(debt.title, style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                                }
                                Amount(vm.debtBalance(debt).remaining, color = Palette.receivable)
                            }
                        }
                        items.forEach { ForecastRow(vm, it) }
                    }
                }
            }
        }
    }
}

@Composable
private fun LegendDot(c: Color, t: String) = Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
    Box(Modifier.size(7.dp).clip(CircleShape).background(c)); Text(t, style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
}

@Composable
private fun DayCell(vm: AppViewModel, d: LocalDate, isSelected: Boolean, onClick: () -> Unit) {
    val isToday = d == vm.today
    val events = vm.data.events.filter { it.date == d }
    val statuses = events.map { Events.paymentStatus(it, vm.data, vm.today) }
    val dots = buildList {
        if (EventPaymentStatus.UNPAID in statuses) add(Palette.expected)
        if (EventPaymentStatus.PARTIALLY_PAID in statuses) add(Palette.token("blue"))
        if (EventPaymentStatus.PAID in statuses) add(Palette.actual)
        if (events.any { it.expectedExpense?.isPos == true }) add(Palette.liability)
        if (vm.data.debts.any { it.dueDate == d && vm.debtBalance(it).isOpen }) add(Palette.receivable)
        if (EventPaymentStatus.NONE in statuses) add(Palette.neutral)
    }
    Column(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(32.dp).clip(CircleShape).background(if (isSelected) Palette.brand else if (isToday) Palette.brandSoft else Color.Transparent), contentAlignment = Alignment.Center) {
            Text("${d.dayOfMonth}", color = if (isSelected) Color.White else if (isToday) Palette.brand else MaterialTheme.colorScheme.onSurface, fontWeight = if (isToday) FontWeight.Bold else FontWeight.Normal)
        }
        Row(Modifier.height(7.dp).padding(top = 2.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) { dots.take(4).forEach { Dot(it) } }
    }
}

@Composable
fun EventEditor(vm: AppViewModel, id: String?, date0: LocalDate?) {
    val ctx = LocalContext.current
    val e0 = vm.data.event(id)
    var title by remember { mutableStateOf(e0?.title ?: "") }
    var date by remember { mutableStateOf(e0?.date ?: date0 ?: vm.today) }
    var hasTime by remember { mutableStateOf(e0?.startTime != null) }
    var start by remember { mutableStateOf(e0?.startTime ?: TimeOfDay(18, 0)) }
    var end by remember { mutableStateOf(e0?.endTime ?: TimeOfDay(20, 0)) }
    var location by remember { mutableStateOf(e0?.location ?: "") }
    var contactId by remember { mutableStateOf(e0?.contactId) }
    var income by remember { mutableStateOf(e0?.expectedIncome?.plain ?: "") }
    var expense by remember { mutableStateOf(e0?.expectedExpense?.plain ?: "") }
    var notes by remember { mutableStateOf(e0?.notes ?: "") }
    var toCalendar by remember { mutableStateOf(false) }
    var pendingSave by remember { mutableStateOf<FinanceEvent?>(null) }
    fun finish(e: FinanceEvent) {
        if (toCalendar && CalendarSync.hasWrite(ctx)) CalendarSync.export(ctx, e)?.let { vm.setCalendarId(e.id, it) }
        vm.show("האירוע נשמר"); vm.pop()
    }
    val perm = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { pendingSave?.let { finish(it) } }
    fun save() {
        val base = e0 ?: FinanceEvent(title = title, date = date)
        val e = base.copy(title = title, date = date, startTime = if (hasTime) start else null, endTime = if (hasTime) end else null, location = location, contactId = contactId,
            expectedIncome = MoneyText.parse(income)?.abs2()?.takeIf { it.isPos }, expectedExpense = MoneyText.parse(expense)?.abs2()?.takeIf { it.isPos }, notes = notes)
        if (!vm.attempt { vm.save(e) }) return
        if (toCalendar && !CalendarSync.hasWrite(ctx)) { pendingSave = e; perm.launch(arrayOf(android.Manifest.permission.READ_CALENDAR, android.Manifest.permission.WRITE_CALENDAR)) }
        else finish(e)
    }
    ScreenScaffold(if (e0 == null) "אירוע חדש" else "עריכת אירוע", onBack = vm::pop, actions = { TextButton(onClick = ::save) { Text("שמירה", fontWeight = FontWeight.Bold) } }) { pad ->
        Column(Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(16.dp)) {
            FormSection {
                Field("שם האירוע (למשל: צילום חתונה)", title, { title = it })
                DateField("תאריך", date) { date = it }
                SwitchRow("שעה מוגדרת", hasTime) { hasTime = it }
                if (hasTime) { TimeField("התחלה", start) { start = it }; TimeField("סיום", end) { end = it } }
                Field("מיקום", location, { location = it })
                ContactPicker(vm, "לקוח / איש קשר", contactId) { contactId = it }
            }
            FormSection("כסף", "השאר ריק אם האירוע לא קשור לכסף. הכנסה צפויה נכנסת לתחזית בלבד — היא לא נספרת ככסף זמין עד שתרשום שהתשלום התקבל. אירוע שבשמו המילה \"אירוע\" ייבדק אוטומטית מול הכנסות, ותתבקש לאשר.") {
                MoneyField("הכנסה צפויה", income, { income = it })
                MoneyField("הוצאה צפויה", expense, { expense = it })
            }
            FormSection {
                Field("הערות", notes, { notes = it }, singleLine = false)
                SwitchRow("להוסיף גם ליומן של הטלפון", toCalendar) { toCalendar = it }
            }
            if (e0 != null) TextButton(onClick = { vm.deleteEvent(e0.id); vm.popTo { it !is Route.EventDetail && it !is Route.EditEvent }; vm.pop() }) { Text("מחיקת האירוע", color = Palette.liability) }
        }
    }
}

@Composable
fun EventDetailScreen(vm: AppViewModel, id: String) {
    val ctx = LocalContext.current
    val e = vm.data.event(id) ?: run { ScreenScaffold("אירוע", onBack = vm::pop) { EmptyState(Icons.Outlined.EventBusy, "האירוע נמחק", "") }; return }
    val fin = Events.financials(e, vm.data.transactions)
    val status = Events.paymentStatus(e, vm.data, vm.today)
    val debt = vm.data.debt(e.debtId)
    val linked = vm.data.transactionsForEvent(e.id).sortedByDescending { it.date }
    val suggestions = EventMatcher.suggestions(vm.data)[e.id].orEmpty()
    var recording by remember { mutableStateOf<TxKind?>(null) }
    var creatingDebt by remember { mutableStateOf(false) }
    val perm = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        if (CalendarSync.hasWrite(ctx)) CalendarSync.export(ctx, e)?.let { vm.setCalendarId(e.id, it); vm.show("נשמר ביומן הטלפון") } else vm.error = "אין הרשאה ליומן."
    }
    ScreenScaffold("אירוע", onBack = vm::pop, actions = { TextButton(onClick = { vm.push(Route.EditEvent(e.id)) }) { Text("עריכה") } }) { pad ->
        Column(Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(16.dp)) {
            FormSection {
                Text(e.title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(vertical = 6.dp))
                Text(e.date.weekdayAndDay() + (e.startTime?.let { " · $it" } ?: ""))
                if (e.location.isNotBlank()) Text(e.location, color = Palette.secondaryText)
                vm.data.contact(e.contactId)?.let { Text(it.name, color = Palette.secondaryText) }
                if (e.calendarEventId != null) Text("מקושר ליומן הטלפון", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                Spacer(Modifier.height(6.dp))
            }
            if (e.expectedIncome?.isPos == true || e.expectedExpense?.isPos == true) FormSection("מצב כספי") {
                e.expectedIncome?.takeIf { it.isPos }?.let {
                    LabelAmount("הכנסה צפויה", it); LabelAmount("התקבל בפועל", fin.receivedIncome, Palette.actual)
                    LabelAmount("נותר לגבייה", debt?.let { d -> vm.debtBalance(d).remaining } ?: fin.outstandingIncome, Palette.expected)
                    Row(Modifier.padding(vertical = 6.dp)) { Text("סטטוס", modifier = Modifier.weight(1f)); Badge(Labels.eventPayment(status), Palette.eventStatus(status)) }
                }
                e.expectedExpense?.takeIf { it.isPos }?.let { LabelAmount("הוצאה צפויה", it); LabelAmount("שולם בפועל", fin.paidExpense, Palette.liability) }
            }
            if (suggestions.isNotEmpty()) FormSection("הכנסות שאולי שייכות לאירוע", "שום דבר לא מקושר בלי אישור שלך.") {
                suggestions.forEach { s -> vm.data.transaction(s.transactionId)?.let { t -> SuggestionBlock(vm, s, t, e.id) } }
            }
            if ((e.expectedIncome ?: ZERO).signum() == 0 && linked.none { it.kind == TxKind.INCOME }) FormSection("תשלום") {
                if (e.isIncomeEvent == false) TextButton(onClick = { vm.markAwaitingPayment(e.id, null) }) { Text("זה כן אירוע בתשלום") }
                else {
                    TextButton(onClick = { recording = TxKind.INCOME }) { Text("שילמו לי על האירוע") }
                    TextButton(onClick = { vm.markNotIncomeEvent(e.id) }) { Text("לא אירוע בתשלום", color = Palette.neutral) }
                }
            }
            FormSection("פעולות") {
                if (e.expectedIncome?.isPos == true && status != EventPaymentStatus.PAID) NavRow(Icons.Outlined.CheckCircle, "רישום תשלום שהתקבל", { recording = TxKind.INCOME })
                if (e.expectedIncome?.isPos == true && debt == null && fin.outstandingIncome.isPos) NavRow(Icons.Outlined.PersonPin, "פתיחת חוב לגבייה (עם תזכורות)", { creatingDebt = true })
                NavRow(Icons.Outlined.NorthEast, "רישום הוצאה לאירוע", { recording = TxKind.EXPENSE })
                NavRow(Icons.Outlined.EditCalendar, if (e.calendarEventId == null) "הוספה ליומן הטלפון" else "עדכון ביומן הטלפון", {
                    if (CalendarSync.hasWrite(ctx) && CalendarSync.hasRead(ctx)) CalendarSync.export(ctx, e)?.let { vm.setCalendarId(e.id, it); vm.show("נשמר ביומן הטלפון") }
                    else perm.launch(arrayOf(android.Manifest.permission.READ_CALENDAR, android.Manifest.permission.WRITE_CALENDAR))
                })
                debt?.let { NavRow(Icons.Outlined.People, "מעבר לחוב: ${it.title}", { vm.push(Route.DebtDetail(it.id)) }) }
            }
            FormSection("תנועות מקושרות") {
                if (linked.isEmpty()) Text("עדיין לא נרשמו תשלומים לאירוע.", color = Palette.secondaryText, modifier = Modifier.padding(vertical = 8.dp))
                linked.forEach { t -> TransactionRow(vm, t) { vm.push(Route.EditTransaction(t.id)) } }
            }
            if (e.notes.isNotBlank()) FormSection("הערות") { Text(e.notes, modifier = Modifier.padding(vertical = 8.dp)) }
        }
    }
    recording?.let { k ->
        EventPaymentDialog(vm, e, k, if (k == TxKind.INCOME) (debt?.let { vm.debtBalance(it).remaining } ?: fin.outstandingIncome) else fin.outstandingExpense) { recording = null }
    }
    if (creatingDebt) CreateReceivableDialog(vm, e) { creatingDebt = false }
}

@Composable
fun LabelAmount(label: String, amount: Money, color: Color? = null) {
    Row(Modifier.padding(vertical = 6.dp)) { Text(label, modifier = Modifier.weight(1f)); Amount(amount, color = color) }
}

@Composable
fun SuggestionBlock(vm: AppViewModel, s: MatchSuggestion, t: Transaction, eventId: String) {
    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp).clip(RoundedCornerShape(12.dp)).background(Palette.elevated).padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(t.title)
                Text("${t.date.il} · ${vm.data.account(t.accountId)?.name.orEmpty()}", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
            }
            Amount(t.amount, color = Palette.actual, plus = true)
        }
        Text(s.reasons.joinToString(" · "), style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { vm.confirmMatch(t.id, eventId); vm.show("קושר לאירוע — סומן כשולם") }, colors = ButtonDefaults.buttonColors(containerColor = Palette.actual)) { Text("כן, זה התשלום") }
            OutlinedButton(onClick = { vm.rejectMatch(t.id, eventId) }) { Text("לא קשור") }
        }
    }
}

@Composable
fun EventPaymentDialog(vm: AppViewModel, e: FinanceEvent, kind: TxKind, suggested: Money, onDismiss: () -> Unit) {
    var amount by remember { mutableStateOf(if (suggested.isPos) suggested.plain else "") }
    var accountId by remember { mutableStateOf(vm.defaultAccountId) }
    var date by remember { mutableStateOf(vm.today) }
    var method by remember { mutableStateOf<PaymentMethod?>(if (kind == TxKind.INCOME) PaymentMethod.BIT else null) }
    AlertDialog(onDismissRequest = onDismiss, title = { Text(if (kind == TxKind.INCOME) "תשלום שהתקבל" else "הוצאה לאירוע") },
        text = {
            Column {
                MoneyField("סכום", amount, { amount = it })
                Picker(if (kind == TxKind.INCOME) "לאיזה חשבון נכנס" else "מאיזה חשבון יצא", vm.activeAccounts, vm.data.account(accountId), { it.name }, { accountId = it.id })
                DateField("תאריך", date) { date = it }
                Picker("אמצעי תשלום", PaymentMethod.entries, method, Labels::method, { method = it }, "לא צוין") { method = null }
                Text(if (kind == TxKind.INCOME) "הסכום ייכנס ליתרה בפועל ויקטין את מה שנותר לגבייה." else "ההוצאה תירשם ותקושר לאירוע.", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val amt = MoneyText.parse(amount)?.abs2()
                val acc = accountId
                if (amt == null || !amt.isPos) vm.error = ValidationError.NonPositiveAmount.hebrew
                else if (acc == null) vm.error = ValidationError.UnknownAccount.hebrew
                else if (vm.attempt { vm.recordEventPayment(e.id, kind, amt, acc, date, method) }) { vm.show("נרשם"); onDismiss() }
            }) { Text("רישום") }
        }, dismissButton = { TextButton(onClick = onDismiss) { Text("ביטול") } })
}

@Composable
fun CreateReceivableDialog(vm: AppViewModel, e: FinanceEvent, onDismiss: () -> Unit) {
    var contactId by remember { mutableStateOf(e.contactId) }
    var due by remember { mutableStateOf(maxOf(e.date, vm.today)) }
    AlertDialog(onDismissRequest = onDismiss, title = { Text("פתיחת חוב לגבייה") }, text = {
        Column {
            ContactPicker(vm, "מי צריך לשלם", contactId, allowNone = false) { contactId = it }
            DateField("מועד לתשלום", due) { due = it }
            Text("החוב יופיע במסך החובות עם תזכורת. בתחזית ייספר החוב במקום ההכנסה הצפויה — לא פעמיים.", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
        }
    }, confirmButton = {
        TextButton(onClick = {
            val c = contactId
            if (c == null) vm.error = "יש לבחור איש קשר." else if (vm.attempt { vm.createReceivable(e.id, c, due) }) { vm.show("החוב נוצר"); onDismiss() }
        }) { Text("יצירה") }
    }, dismissButton = { TextButton(onClick = onDismiss) { Text("ביטול") } })
}

/** "Did you get paid for this event?" — nothing is linked without the user's confirmation. */
@Composable
fun PaymentReviewScreen(vm: AppViewModel) {
    val questions = vm.paymentQuestions
    var recording by remember { mutableStateOf<FinanceEvent?>(null) }
    var awaiting by remember { mutableStateOf<FinanceEvent?>(null) }
    ScreenScaffold("תשלומים על אירועים", onBack = vm::pop) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { DemoBanner(vm) }
            if (questions.isEmpty()) item {
                Card { EmptyState(Icons.Outlined.Verified, "הכול מעודכן", "אין אירועים שמחכים לתשובה. כשיופיע אירוע (למשל עם המילה \"אירוע\") או הכנסה שנראית כמו תשלום עליו — הוא יופיע כאן לאישור שלך.") }
            } else item { Text("מצאתי אירועים שכדאי לבדוק אם שילמו עליהם. שום דבר לא מקושר בלי האישור שלך.", color = Palette.secondaryText) }
            questions.forEach { q ->
                item(key = q.event.id) {
                    val e = q.event
                    Card {
                        Row {
                            Column(Modifier.weight(1f)) {
                                Text(e.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                                Text(listOfNotNull(e.date.il, vm.data.contact(e.contactId)?.name).joinToString(" · "), style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                            }
                            e.expectedIncome?.takeIf { it.isPos }?.let { Column(horizontalAlignment = Alignment.End) {
                                Amount(it, color = Palette.expected)
                                if (q.outstanding.isPos && q.outstanding != it) Text("נותר ${q.outstanding.ils()}", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                            } }
                        }
                        when (q.kind) {
                            PaymentQuestion.Kind.POSSIBLE_MATCH -> {
                                Text("נמצאה הכנסה שאולי היא התשלום על האירוע:", fontWeight = FontWeight.Medium)
                                q.suggestions.forEach { s -> vm.data.transaction(s.transactionId)?.let { t -> SuggestionBlock(vm, s, t, e.id) } }
                                TextButton(onClick = { recording = e }) { Text("אף אחת מהן — אני ארשום ידנית") }
                            }
                            PaymentQuestion.Kind.UNPAID_AFTER_EVENT -> {
                                Text("האירוע עבר ועוד לא נרשם תשלום. שילמו לך?", fontWeight = FontWeight.Medium)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Button(onClick = { recording = e }, colors = ButtonDefaults.buttonColors(containerColor = Palette.actual)) { Text("כן, שילמו") }
                                    OutlinedButton(onClick = { awaiting = e }) { Text("עדיין לא") }
                                }
                            }
                            PaymentQuestion.Kind.UNKNOWN_IF_PAID -> {
                                Text("זה נראה כמו אירוע בתשלום. שילמו לך עליו?", fontWeight = FontWeight.Medium)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Button(onClick = { recording = e }, colors = ButtonDefaults.buttonColors(containerColor = Palette.actual)) { Text("כן, שילמו") }
                                    OutlinedButton(onClick = { awaiting = e }) { Text("עדיין לא") }
                                    OutlinedButton(onClick = { vm.markNotIncomeEvent(e.id); vm.show("לא אשאל יותר על האירוע הזה") }) { Text("לא בתשלום") }
                                }
                            }
                        }
                        TextButton(onClick = { vm.push(Route.EventDetail(e.id)) }) { Text("פרטי האירוע") }
                    }
                }
            }
        }
    }
    recording?.let { e -> EventPaymentDialog(vm, e, TxKind.INCOME, Events.financials(e, vm.data.transactions).outstandingIncome) { recording = null } }
    awaiting?.let { e ->
        var amount by remember(e.id) { mutableStateOf(e.expectedIncome?.plain ?: "") }
        var openDebt by remember(e.id) { mutableStateOf(false) }
        var contactId by remember(e.id) { mutableStateOf(e.contactId) }
        AlertDialog(onDismissRequest = { awaiting = null }, title = { Text("עדיין לא שילמו") }, text = {
            Column {
                MoneyField("כמה אמורים לשלם לך", amount, { amount = it })
                Text("הסכום ייכנס לתחזית כהכנסה צפויה — לא ליתרה בפועל — עד שתאשר שהתקבל.", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                SwitchRow("לפתוח חוב לגבייה עם תזכורת", openDebt) { openDebt = it }
                if (openDebt) ContactPicker(vm, "מי צריך לשלם", contactId, allowNone = false) { contactId = it }
            }
        }, confirmButton = {
            TextButton(onClick = {
                val amt = MoneyText.parse(amount)?.abs2()
                vm.markAwaitingPayment(e.id, amt)
                if (openDebt) {
                    val c = contactId
                    if (c == null) { vm.error = "יש לבחור איש קשר."; return@TextButton }
                    if (!vm.attempt { vm.createReceivable(e.id, c, vm.today.plusDays(7)) }) return@TextButton
                }
                vm.show("נשמר — אזכיר לך"); awaiting = null
            }) { Text("שמירה") }
        }, dismissButton = { TextButton(onClick = { awaiting = null }) { Text("ביטול") } })
    }
}
