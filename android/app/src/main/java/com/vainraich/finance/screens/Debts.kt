package com.vainraich.finance.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.vainraich.core.*
import com.vainraich.finance.*
import com.vainraich.finance.ui.*
import com.vainraich.finance.ui.Card

@Composable
fun DebtsScreen(vm: AppViewModel) {
    var dir by remember { mutableStateOf(DebtDirection.RECEIVABLE) }
    var showClosed by remember { mutableStateOf(false) }
    val all = vm.data.debts.filter { it.direction == dir }.map { vm.debtBalance(it) }
    val open = all.filter { it.isOpen }.sortedWith(compareBy({ if (it.isOverdue) 0 else 1 }, { it.debt.dueDate ?: java.time.LocalDate.MAX }))
    val closed = all.filter { !it.isOpen }
    ScreenScaffold("חובות", actions = { IconButton(onClick = { vm.push(Route.EditDebt(null, dir)) }) { Icon(Icons.Outlined.Add, "חוב חדש") } }) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { DemoBanner(vm) }
            item { Segmented(DebtDirection.entries, dir, { if (it == DebtDirection.RECEIVABLE) "חייבים לי" else "אני חייב" }, { dir = it }) }
            if (all.isEmpty()) item {
                EmptyState(Icons.Outlined.PersonSearch, if (dir == DebtDirection.RECEIVABLE) "אף אחד לא חייב לך כסף" else "אין חובות פתוחים",
                    if (dir == DebtDirection.RECEIVABLE) "רשום כאן כסף שמגיע לך — הלוואות, תשלומים על עבודות — עם תשלומים חלקיים ותזכורות." else "רשום כאן כסף שאתה צריך להחזיר, כדי שייכנס לתחזית ולתזכורות.",
                    "הוספת חוב") { vm.push(Route.EditDebt(null, dir)) }
            } else item {
                val total = open.sumOfMoney { it.remaining }
                val overdue = open.filter { it.isOverdue }.sumOfMoney { it.remaining }
                val color = if (dir == DebtDirection.RECEIVABLE) Palette.receivable else Palette.expected
                Card {
                    Text(if (dir == DebtDirection.RECEIVABLE) "סה״כ מגיע לי" else "סה״כ אני חייב", color = Palette.secondaryText)
                    Amount(total, MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold), color = color)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Badge("${open.size} פתוחים", color)
                        if (overdue.isPos) Badge("באיחור ${overdue.ils()}", Palette.liability, Icons.Outlined.Error)
                        if (dir == DebtDirection.RECEIVABLE) Debts.collectionRate(vm.data)?.let { Badge("נגבה ${Math.round(it * 100)}%", Palette.actual) }
                    }
                    if (dir == DebtDirection.RECEIVABLE) Text("כסף שחייבים לך לא נספר ככסף זמין עד שהוא מתקבל בפועל.", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                }
            }
            if (open.isNotEmpty()) item { FormSection("פתוחים") { open.forEach { b -> DebtRow(vm, b) { vm.push(Route.DebtDetail(b.debt.id)) } } } }
            if (closed.isNotEmpty()) item {
                FormSection {
                    TextButton(onClick = { showClosed = !showClosed }) { Text("סגורים (${closed.size})"); Icon(if (showClosed) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore, null) }
                    if (showClosed) closed.forEach { b -> DebtRow(vm, b) { vm.push(Route.DebtDetail(b.debt.id)) } }
                }
            }
            if (vm.data.contacts.isNotEmpty()) item { FormSection("לפי אדם") { NavRow(Icons.Outlined.Contacts, "היסטוריית תשלומים לכל איש קשר", { vm.push(Route.Contacts) }) } }
        }
    }
}

@Composable
fun DebtDetailScreen(vm: AppViewModel, id: String) {
    val d = vm.data.debt(id) ?: run { ScreenScaffold("חוב", onBack = vm::pop) { EmptyState(Icons.Outlined.PersonOff, "החוב נמחק", "") }; return }
    val b = vm.debtBalance(d)
    val contact = vm.data.contact(d.contactId)
    var paying by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    ScreenScaffold(d.title, onBack = vm::pop, actions = { TextButton(onClick = { vm.push(Route.EditDebt(d.id)) }) { Text("עריכה") } }) { pad ->
        Column(Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(16.dp)) {
            Card {
                Text(if (d.direction == DebtDirection.RECEIVABLE) "${contact?.name.orEmpty()} חייב/ת לך" else "אתה חייב ל${contact?.name.orEmpty()}", color = Palette.secondaryText)
                Amount(b.remaining, MaterialTheme.typography.displaySmall.copy(fontWeight = FontWeight.Bold), color = if (d.direction == DebtDirection.RECEIVABLE) Palette.receivable else Palette.expected)
                LinearProgressIndicator(progress = { b.progress }, modifier = Modifier.fillMaxWidth(), color = Palette.actual)
                Row { Text("סכום מקורי ${d.originalAmount.ils()}", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText, modifier = Modifier.weight(1f)); Text("שולם ${b.paid.ils()}", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText) }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { Badge(Labels.debtStatus(b.status), Palette.debtStatus(b.status)); if (b.isOverdue) Badge("באיחור", Palette.liability) }
            }
            FormSection("פרטים") {
                ValueRow("סיבה", d.title)
                ValueRow("נוצר", d.issuedDate.il)
                d.dueDate?.let { ValueRow("מועד תשלום", it.il) }
                vm.data.event(d.eventId)?.let { ValueRow("אירוע", it.title) { vm.push(Route.EventDetail(it.id)) } }
                contact?.let { ValueRow("איש קשר", it.name) { vm.push(Route.ContactDetail(it.id)) } }
                if (!d.countsAsIncomeOrExpense) Text("הלוואה — התשלומים לא נספרים כהכנסה/הוצאה בדוחות.", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                if (d.notes.isNotBlank()) Text(d.notes, modifier = Modifier.padding(vertical = 6.dp))
            }
            FormSection {
                if (b.isOpen) {
                    NavRow(Icons.Outlined.AddCircle, if (d.direction == DebtDirection.RECEIVABLE) "רישום תשלום שהתקבל" else "רישום תשלום ששילמתי", { paying = true })
                    NavRow(Icons.Outlined.Block, "סימון כנמחק (לא ייגבה)", { vm.setClosedStatus(d.id, DebtStatus.WRITTEN_OFF) })
                    NavRow(Icons.Outlined.Cancel, "ביטול החוב", { vm.setClosedStatus(d.id, DebtStatus.CANCELLED) })
                } else if (d.closedStatus != null) NavRow(Icons.Outlined.Restore, "פתיחה מחדש", { vm.setClosedStatus(d.id, null) })
            }
            FormSection("היסטוריית תשלומים") {
                val payments = vm.data.paymentsFor(d.id).reversed()
                if (payments.isEmpty()) Text("עדיין לא נרשמו תשלומים.", color = Palette.secondaryText, modifier = Modifier.padding(vertical = 8.dp))
                payments.forEach { p ->
                    Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(p.date.il)
                            vm.data.transaction(p.transactionId)?.let { t -> Text(vm.data.account(t.accountId)?.name.orEmpty(), style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText) }
                        }
                        Amount(p.amount, color = Palette.actual)
                        IconButton(onClick = { vm.deletePayment(p.id) }) { Icon(Icons.Outlined.Delete, "מחיקה", tint = Palette.secondaryText) }
                    }
                }
            }
            FormSection(footer = "מחיקת חוב לא מוחקת כסף שכבר נכנס או יצא מהחשבון.") { TextButton(onClick = { confirmDelete = true }) { Text("מחיקת החוב", color = Palette.liability) } }
        }
    }
    if (paying) DebtPaymentDialog(vm, d, b.remaining) { paying = false }
    if (confirmDelete) ConfirmDialog("למחוק את החוב?", null, "מחיקה", onConfirm = { vm.deleteDebt(d.id); vm.pop() }, onDismiss = { confirmDelete = false })
}

@Composable
fun DebtPaymentDialog(vm: AppViewModel, d: Debt, remaining: Money, onDismiss: () -> Unit) {
    var amount by remember { mutableStateOf("") }
    var accountId by remember { mutableStateOf(vm.defaultAccountId) }
    var date by remember { mutableStateOf(vm.today) }
    AlertDialog(onDismissRequest = onDismiss, title = { Text("רישום תשלום") }, text = {
        Column {
            MoneyField("סכום", amount, { amount = it })
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("נותר: ${remaining.ils()}", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText, modifier = Modifier.weight(1f))
                TextButton(onClick = { amount = remaining.plain }) { Text("כל היתרה") }
            }
            Picker(if (d.direction == DebtDirection.RECEIVABLE) "לאיזה חשבון נכנס" else "מאיזה חשבון יצא", vm.activeAccounts, vm.data.account(accountId), { it.name }, { accountId = it.id })
            DateField("תאריך", date) { date = it }
            Text("התשלום משנה את היתרה בפועל ומקטין את החוב. אפשר לרשום כמה תשלומים חלקיים.", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
        }
    }, confirmButton = {
        TextButton(onClick = {
            val amt = MoneyText.parse(amount)?.abs2(); val acc = accountId
            if (amt == null || !amt.isPos) vm.error = ValidationError.NonPositiveAmount.hebrew
            else if (acc == null) vm.error = ValidationError.UnknownAccount.hebrew
            else if (vm.attempt { vm.recordDebtPayment(d.id, amt, date, acc) }) { vm.show("התשלום נרשם"); onDismiss() }
        }) { Text("רישום") }
    }, dismissButton = { TextButton(onClick = onDismiss) { Text("ביטול") } })
}

@Composable
fun DebtEditor(vm: AppViewModel, id: String?, dir0: DebtDirection) {
    val d0 = vm.data.debt(id)
    var dir by remember { mutableStateOf(d0?.direction ?: dir0) }
    var contactId by remember { mutableStateOf(d0?.contactId) }
    var title by remember { mutableStateOf(d0?.title ?: "") }
    var amount by remember { mutableStateOf(d0?.originalAmount?.plain ?: "") }
    var issued by remember { mutableStateOf(d0?.issuedDate ?: vm.today) }
    var hasDue by remember { mutableStateOf(d0?.dueDate != null || d0 == null) }
    var due by remember { mutableStateOf(d0?.dueDate ?: vm.today.plusDays(30)) }
    var loan by remember { mutableStateOf(d0?.countsAsIncomeOrExpense == false) }
    var notes by remember { mutableStateOf(d0?.notes ?: "") }
    fun save() {
        val c = contactId ?: run { vm.error = "יש לבחור איש קשר."; return }
        val amt = MoneyText.parse(amount)?.abs2()
        if (amt == null || !amt.isPos) { vm.error = ValidationError.NonPositiveAmount.hebrew; return }
        val base = d0 ?: Debt(direction = dir, contactId = c, title = title, originalAmount = amt)
        if (vm.attempt { vm.save(base.copy(direction = dir, contactId = c, title = title, originalAmount = amt, issuedDate = issued, dueDate = if (hasDue) due else null, countsAsIncomeOrExpense = !loan, notes = notes)) }) { vm.show("נשמר"); vm.pop() }
    }
    ScreenScaffold(if (d0 == null) "חוב חדש" else "עריכת חוב", onBack = vm::pop, actions = { TextButton(onClick = ::save) { Text("שמירה", fontWeight = FontWeight.Bold) } }) { pad ->
        Column(Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(16.dp)) {
            FormSection {
                if (d0 == null) Segmented(DebtDirection.entries, dir, { if (it == DebtDirection.RECEIVABLE) "חייבים לי" else "אני חייב" }, { dir = it }, Modifier.padding(vertical = 8.dp))
                ContactPicker(vm, if (dir == DebtDirection.RECEIVABLE) "מי חייב" else "למי", contactId, allowNone = false) { contactId = it }
                Field("על מה (למשל: צילום חתונה, הלוואה)", title, { title = it })
                MoneyField("סכום", amount, { amount = it }, large = true)
            }
            FormSection(footer = "הלוואה לחבר או ממנו — ההחזר מגדיל את היתרה בפועל אבל לא נספר כהכנסה בדוחות. עבור תשלום על עבודה, השאר כבוי.") {
                DateField("נוצר בתאריך", issued) { issued = it }
                SwitchRow("יש מועד לתשלום", hasDue) { hasDue = it }
                if (hasDue) DateField("מועד", due) { due = it }
                SwitchRow("זו הלוואה (לא הכנסה/הוצאה)", loan) { loan = it }
                Field("הערות", notes, { notes = it }, singleLine = false)
            }
        }
    }
}

@Composable
fun ContactsScreen(vm: AppViewModel) {
    var newName by remember { mutableStateOf<String?>(null) }
    ScreenScaffold("אנשי קשר", onBack = vm::pop, actions = { IconButton(onClick = { newName = "" }) { Icon(Icons.Outlined.PersonAdd, "הוספה") } }) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp)) {
            if (vm.data.contacts.isEmpty()) item { EmptyState(Icons.Outlined.Contacts, "אין אנשי קשר", "אנשי קשר נוצרים כשמוסיפים חוב, אירוע או תנועה עם לקוח.") }
            else item {
                FormSection {
                    vm.data.contacts.sortedBy { it.name }.forEach { c ->
                        val open = vm.data.debts.filter { it.contactId == c.id }.map { vm.debtBalance(it) }.filter { it.isOpen }
                        val owed = open.filter { it.debt.direction == DebtDirection.RECEIVABLE }.sumOfMoney { it.remaining }
                        val iOwe = open.filter { it.debt.direction == DebtDirection.PAYABLE }.sumOfMoney { it.remaining }
                        Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                            TextButton(onClick = { vm.push(Route.ContactDetail(c.id)) }, modifier = Modifier.weight(1f)) { Text(c.name, modifier = Modifier.fillMaxWidth()) }
                            if (owed.isPos) Amount(owed, color = Palette.receivable)
                            if (iOwe.isPos) Amount(iOwe.negate(), color = Palette.expected)
                            if (!vm.contactInUse(c.id)) IconButton(onClick = { vm.deleteContact(c.id) }) { Icon(Icons.Outlined.Delete, "מחיקה", tint = Palette.secondaryText) }
                        }
                    }
                }
            }
        }
    }
    newName?.let { n ->
        AlertDialog(onDismissRequest = { newName = null }, title = { Text("איש קשר חדש") }, text = { OutlinedTextField(n, { newName = it }, label = { Text("שם") }) },
            confirmButton = { TextButton(onClick = { if (n.isNotBlank()) vm.addContact(Contact(name = n.trim())); newName = null }) { Text("הוספה") } },
            dismissButton = { TextButton(onClick = { newName = null }) { Text("ביטול") } })
    }
}

@Composable
fun ContactDetailScreen(vm: AppViewModel, id: String) {
    val ctx = LocalContext.current
    val c = vm.data.contact(id) ?: run { vm.pop(); return }
    ScreenScaffold(c.name, onBack = vm::pop) { pad ->
        Column(Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(16.dp)) {
            c.phone?.let { p -> FormSection { NavRow(Icons.Outlined.Phone, p, { ctx.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$p"))) }) } }
            FormSection("חובות") {
                val debts = vm.data.debts.filter { it.contactId == c.id }.map { vm.debtBalance(it) }
                if (debts.isEmpty()) Text("אין חובות", color = Palette.secondaryText, modifier = Modifier.padding(vertical = 8.dp))
                debts.forEach { b -> DebtRow(vm, b) { vm.push(Route.DebtDetail(b.debt.id)) } }
            }
            val events = vm.data.events.filter { it.contactId == c.id }.sortedByDescending { it.date }
            if (events.isNotEmpty()) FormSection("אירועים") { events.forEach { e -> EventRow(vm, e) { vm.push(Route.EventDetail(e.id)) } } }
            FormSection("היסטוריית תשלומים") {
                val txs = vm.data.transactions.filter { it.contactId == c.id }.sortedByDescending { it.date }
                if (txs.isEmpty()) Text("אין תנועות", color = Palette.secondaryText, modifier = Modifier.padding(vertical = 8.dp))
                txs.forEach { t -> TransactionRow(vm, t) { vm.push(Route.EditTransaction(t.id)) } }
            }
        }
    }
}
