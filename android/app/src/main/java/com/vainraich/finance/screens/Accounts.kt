package com.vainraich.finance.screens

import androidx.compose.foundation.clickable
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
import com.vainraich.finance.services.Exporter
import com.vainraich.finance.ui.*
import com.vainraich.finance.ui.Card
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

@Composable
fun AccountsScreen(vm: AppViewModel) {
    val balances = vm.balances
    val s = vm.summary(DateRange.day(vm.today))
    var showInactive by remember { mutableStateOf(false) }
    ScreenScaffold("חשבונות", onBack = vm::pop, actions = { IconButton(onClick = { vm.push(Route.EditAccount(null)) }) { Icon(Icons.Outlined.Add, "חשבון חדש") } }) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item { DemoBanner(vm) }
            if (vm.data.accounts.isEmpty()) item { EmptyState(Icons.Outlined.AccountBalance, "אין חשבונות", "הוסף חשבון בנק, מזומן, ביט או כרטיס אשראי עם היתרה הנוכחית.", "הוספת חשבון") { vm.push(Route.EditAccount(null)) } }
            else item {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Card(Modifier.weight(1f), 12.dp) { Text("זמין", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText); Amount(s.available, color = Palette.actual) }
                    Card(Modifier.weight(1f), 12.dp) { Text("אשראי", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText); Amount(s.creditCardLiability.negate(), color = Palette.liability) }
                    Card(Modifier.weight(1f), 12.dp) { Text("חיסכון", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText); Amount(s.savings, color = Palette.token("indigo")) }
                }
            }
            AccountType.entries.forEach { t ->
                val list = vm.activeAccounts.filter { it.type == t }
                if (list.isNotEmpty()) item { FormSection(Labels.accountType(t)) { list.forEach { a -> AccountRow(a, balances[a.id] ?: ZERO) { vm.push(Route.AccountDetail(a.id)) } } } }
            }
            val inactive = vm.data.accounts.filter { !it.isActive }
            if (inactive.isNotEmpty()) item {
                FormSection {
                    TextButton(onClick = { showInactive = !showInactive }) { Text("חשבונות לא פעילים (${inactive.size})") }
                    if (showInactive) inactive.forEach { a -> AccountRow(a, balances[a.id] ?: ZERO) { vm.push(Route.AccountDetail(a.id)) } }
                }
            }
        }
    }
}

@Composable
fun AccountDetailScreen(vm: AppViewModel, id: String) {
    val a = vm.data.account(id) ?: run { vm.pop(); return }
    val bal = vm.balance(a.id)
    val txs = vm.data.transactions.filter { it.accountId == a.id || it.counterAccountId == a.id }.sortedWith(compareByDescending<Transaction> { it.date }.thenByDescending { it.createdAt })
    var updating by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf(false) }
    val history = vm.accountHasHistory(a.id)
    ScreenScaffold(a.name, onBack = vm::pop, actions = { TextButton(onClick = { vm.push(Route.EditAccount(a.id)) }) { Text("עריכה") } }) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item {
                Card {
                    Text(Labels.accountType(a.type), color = Palette.accountType(a.type))
                    Amount(bal, MaterialTheme.typography.displaySmall.copy(fontWeight = FontWeight.Bold), bySign = a.type == AccountType.CREDIT_CARD)
                    if (a.type == AccountType.CREDIT_CARD) {
                        Text(if (bal.isNeg) "חוב בכרטיס. ייגבה מ${vm.data.account(a.paymentAccountId)?.name ?: "חשבון הבנק"} ביום החיוב." else "אין חוב פתוח בכרטיס.", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                        a.creditLimit?.takeIf { it.isPos }?.let { lim -> LinearProgressIndicator(progress = { (bal.negate().toDouble() / lim.toDouble()).toFloat().coerceIn(0f, 1f) }, color = Palette.liability, modifier = Modifier.fillMaxWidth()) }
                    }
                    a.lastSyncedAt?.let { Text("עודכן ממסמך: ${Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()).toLocalDate().il}", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText) }
                }
            }
            item {
                FormSection {
                    NavRow(Icons.Outlined.Tune, "עדכון יתרה לפי הבנק", { updating = true })
                    NavRow(Icons.Outlined.DocumentScanner, "ייבוא תנועות ממסמך", { vm.push(Route.Import) })
                }
            }
            item {
                FormSection("תנועות (${txs.size})") {
                    if (txs.isEmpty()) Text("אין תנועות בחשבון", color = Palette.secondaryText, modifier = Modifier.padding(vertical = 8.dp))
                    txs.take(200).forEach { t -> TransactionRow(vm, t) { vm.push(Route.EditTransaction(t.id)) } }
                }
            }
            item {
                FormSection(footer = if (history) "לחשבון יש היסטוריה, לכן הוא יסומן כלא פעיל ולא יימחק." else null) {
                    TextButton(onClick = { confirm = true }) { Text(if (history) "הפיכה ללא פעיל" else "מחיקת החשבון", color = Palette.liability) }
                }
            }
        }
    }
    if (updating) {
        var text by remember { mutableStateOf(bal.abs().plain) }
        var negative by remember { mutableStateOf(bal.isNeg && a.type != AccountType.CREDIT_CARD) }
        var date by remember { mutableStateOf(vm.today) }
        AlertDialog(onDismissRequest = { updating = false }, title = { Text("עדכון יתרה") }, text = {
            Column {
                Text("יתרה באפליקציה: ${bal.ils()}", color = Palette.secondaryText)
                MoneyField(if (a.type == AccountType.CREDIT_CARD) "חוב בכרטיס לפי החברה" else "יתרה אמיתית לפי הבנק", text, { text = it })
                if (a.type != AccountType.CREDIT_CARD) SwitchRow("היתרה במינוס", negative) { negative = it }
                DateField("נכון לתאריך", date) { date = it }
                Text("ההפרש יירשם כ\"עדכון יתרה\" — לא כהכנסה ולא כהוצאה.", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
            }
        }, confirmButton = {
            TextButton(onClick = {
                val v = MoneyText.parse(text)?.abs2() ?: run { vm.error = "יש להזין סכום."; return@TextButton }
                val target = if (a.type == AccountType.CREDIT_CARD || negative) v.negate() else v
                if (vm.attempt { vm.setBalance(a.id, target, date) }) { vm.show("היתרה עודכנה"); updating = false }
            }) { Text("עדכון") }
        }, dismissButton = { TextButton(onClick = { updating = false }) { Text("ביטול") } })
    }
    if (confirm) ConfirmDialog(if (history) "לסמן כלא פעיל?" else "למחוק את החשבון?", null, if (history) "סימון" else "מחיקה",
        onConfirm = { vm.deleteOrDeactivate(a.id); if (!history) vm.pop() }, onDismiss = { confirm = false })
}

@Composable
fun AccountEditor(vm: AppViewModel, id: String?) {
    val a0 = vm.data.account(id)
    var type by remember { mutableStateOf(a0?.type ?: AccountType.BANK) }
    var name by remember { mutableStateOf(a0?.name ?: "") }
    var institution by remember { mutableStateOf(a0?.institution ?: "") }
    var balance by remember { mutableStateOf("") }
    var negative by remember { mutableStateOf(false) }
    var include by remember { mutableStateOf(a0?.includeInAvailable ?: true) }
    var limit by remember { mutableStateOf(a0?.creditLimit?.plain ?: "") }
    var billingDay by remember { mutableStateOf(a0?.billingDay ?: 10) }
    var payId by remember { mutableStateOf(a0?.paymentAccountId ?: vm.activeAccounts.firstOrNull { it.type == AccountType.BANK }?.id) }
    var active by remember { mutableStateOf(a0?.isActive ?: true) }
    var notes by remember { mutableStateOf(a0?.notes ?: "") }
    fun save() {
        val v = MoneyText.parse(balance)?.abs2() ?: ZERO
        val base = a0 ?: Account(name = name, type = type, openingDate = vm.today, openingBalance = if (type == AccountType.CREDIT_CARD || negative) v.negate() else v)
        if (vm.attempt { vm.save(base.copy(name = name, type = type, institution = institution.ifBlank { null }, includeInAvailable = if (type == AccountType.CREDIT_CARD) false else include,
                creditLimit = MoneyText.parse(limit)?.abs2(), billingDay = if (type == AccountType.CREDIT_CARD) billingDay else null, paymentAccountId = if (type == AccountType.CREDIT_CARD) payId else null,
                isActive = active, notes = notes)) }) { vm.show("החשבון נשמר"); vm.pop() }
    }
    ScreenScaffold(if (a0 == null) "חשבון חדש" else "עריכת חשבון", onBack = vm::pop, actions = { TextButton(onClick = ::save) { Text("שמירה", fontWeight = FontWeight.Bold) } }) { pad ->
        Column(Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(16.dp)) {
            FormSection {
                Picker("סוג", AccountType.entries, type, Labels::accountType, { type = it; if (a0 == null) include = it.defaultIncludeInAvailable })
                Field("שם (למשל: עו״ש לאומי)", name, { name = it })
                if (type in setOf(AccountType.BANK, AccountType.CREDIT_CARD, AccountType.SAVINGS)) Field(if (type == AccountType.CREDIT_CARD) "חברת האשראי" else "בנק / מוסד", institution, { institution = it })
            }
            if (a0 == null) FormSection(footer = if (type == AccountType.CREDIT_CARD) "סכום החיובים שעוד לא ירדו מהבנק. השאר ריק אם אין." else "היתרה כפי שהיא היום. מעכשיו היא תתעדכן לפי התנועות.") {
                MoneyField(if (type == AccountType.CREDIT_CARD) "חוב נוכחי בכרטיס" else "יתרה נוכחית", balance, { balance = it }, large = true)
                if (type != AccountType.CREDIT_CARD) SwitchRow("היתרה במינוס", negative) { negative = it }
            }
            if (type == AccountType.CREDIT_CARD) FormSection("כרטיס אשראי") {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("יום חיוב: $billingDay בחודש", modifier = Modifier.weight(1f))
                    IconButton(onClick = { if (billingDay > 1) billingDay-- }) { Icon(Icons.Outlined.Remove, "פחות") }
                    IconButton(onClick = { if (billingDay < 31) billingDay++ }) { Icon(Icons.Outlined.Add, "יותר") }
                }
                Picker("משולם מחשבון", vm.activeAccounts.filter { it.id != a0?.id && it.type != AccountType.CREDIT_CARD }, vm.data.account(payId), { it.name }, { payId = it.id }, "לא נבחר") { payId = null }
                MoneyField("מסגרת אשראי (לא חובה)", limit, { limit = it })
            }
            FormSection(footer = "חיסכון ופיקדונות לא נספרים ככסף זמין כברירת מחדל.") {
                SwitchRow("נספר בכסף הזמין", include, enabled = type != AccountType.CREDIT_CARD) { include = it }
                if (a0 != null) SwitchRow("חשבון פעיל", active) { active = it }
                Field("הערות", notes, { notes = it }, singleLine = false)
            }
        }
    }
}

@Composable
fun CategoriesScreen(vm: AppViewModel) {
    var adding by remember { mutableStateOf<CategoryKind?>(null) }
    var name by remember { mutableStateOf("") }
    ScreenScaffold("קטגוריות", onBack = vm::pop) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp)) {
            listOf(CategoryKind.EXPENSE, CategoryKind.INCOME).forEach { k ->
                item {
                    FormSection(if (k == CategoryKind.EXPENSE) "הוצאות" else "הכנסות") {
                        vm.data.categories.filter { it.kind == k }.forEach { c ->
                            Row(Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                IconBubble(Icon.of(c.icon), Palette.token(c.colorToken), 30.dp)
                                Text(c.name, modifier = Modifier.weight(1f), color = if (c.isArchived) Palette.secondaryText else MaterialTheme.colorScheme.onSurface)
                                TextButton(onClick = { vm.save(c.copy(isArchived = !c.isArchived)) }) { Text(if (c.isArchived) "שחזור" else "הסתרה") }
                            }
                        }
                        TextButton(onClick = { adding = k }) { Icon(Icons.Outlined.Add, null); Text("קטגוריה חדשה") }
                    }
                }
            }
        }
    }
    adding?.let { k ->
        AlertDialog(onDismissRequest = { adding = null }, title = { Text("קטגוריה חדשה") }, text = { OutlinedTextField(name, { name = it }, label = { Text("שם") }) },
            confirmButton = { TextButton(onClick = { if (name.isNotBlank()) vm.save(Category(name = name.trim(), kind = k, icon = "tag", colorToken = "teal")); name = ""; adding = null }) { Text("הוספה") } },
            dismissButton = { TextButton(onClick = { adding = null }) { Text("ביטול") } })
    }
}

@Composable
fun ReportsScreen(vm: AppViewModel) {
    val ctx = LocalContext.current
    var month by remember { mutableStateOf(vm.today.startOfMonth()) }
    var kind by remember { mutableStateOf(TxKind.EXPENSE) }
    var sel by remember { mutableStateOf<String?>(null) }
    var exportMenu by remember { mutableStateOf(false) }
    val range = DateRange.month(month)
    val m = Reports.monthly(vm.data, month, 1).first()
    val prev = Reports.monthly(vm.data, month.minusMonths(1), 1).first()
    val slices = Reports.byCategory(vm.data, kind, range)
    val sources = Reports.incomeBySource(vm.data, range)
    fun change(now: Money, before: Money) = if (before.isPos) ((now.toDouble() - before.toDouble()) / before.toDouble() * 100).let { "${if (it >= 0) "▲" else "▼"} ${Math.round(kotlin.math.abs(it))}% מהחודש הקודם" } else null
    ScreenScaffold("דוחות", onBack = vm::pop, actions = {
        Box {
            IconButton(onClick = { exportMenu = true }) { Icon(Icons.Outlined.Share, "ייצוא") }
            DropdownMenu(exportMenu, { exportMenu = false }) {
                DropdownMenuItem({ Text("תנועות החודש (CSV)") }, {
                    exportMenu = false
                    Exporter.share(ctx, Exporter.text(ctx, "תנועות-${month.year}-${"%02d".format(month.monthValue)}.csv", Csv.transactions(vm.data.transactions.filter { it.date in range }, vm.data)), "text/csv")
                })
                DropdownMenuItem({ Text("סיכום 12 חודשים (CSV)") }, {
                    exportMenu = false
                    Exporter.share(ctx, Exporter.text(ctx, "סיכום-חודשי.csv", Csv.monthly(Reports.monthly(vm.data, month, 12))), "text/csv")
                })
                DropdownMenuItem({ Text("דוח חודשי (PDF)") }, { exportMenu = false; Exporter.share(ctx, Exporter.monthlyPdf(ctx, vm.data, month, vm.today), "application/pdf") })
            }
        }
    }) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { DemoBanner(vm) }
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { month = month.minusMonths(1) }) { Icon(Icons.Outlined.ChevronRight, "חודש קודם") }
                    Text("${Labels.month(month.monthValue)} ${month.year}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                    IconButton(onClick = { month = month.plusMonths(1) }, enabled = month.isBefore(vm.today.startOfMonth())) { Icon(Icons.Outlined.ChevronLeft, "חודש הבא") }
                }
            }
            item {
                Card {
                    Row {
                        Column(Modifier.weight(1f)) { Text("הכנסות", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText); Amount(m.income, MaterialTheme.typography.titleLarge, color = Palette.actual); change(m.income, prev.income)?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText) } }
                        Column(Modifier.weight(1f)) { Text("הוצאות", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText); Amount(m.expenses, MaterialTheme.typography.titleLarge, color = Palette.liability); change(m.expenses, prev.expenses)?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText) } }
                    }
                    HorizontalDivider(color = Palette.separator)
                    Row(verticalAlignment = Alignment.CenterVertically) { Text("תזרים נטו", fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f)); Amount(m.net, MaterialTheme.typography.titleLarge, bySign = true, plus = true) }
                    Text("לא כולל העברות בין חשבונות, תשלומי כרטיס אשראי, עדכוני יתרה והלוואות.", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                }
            }
            item { Card { SectionTitle("מגמה — 6 חודשים"); MonthlyBars(Reports.monthly(vm.data, month, 6), showNet = true) } }
            item {
                Card {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("לפי קטגוריה", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        Segmented(listOf(TxKind.EXPENSE, TxKind.INCOME), kind, { if (it == TxKind.EXPENSE) "הוצאות" else "הכנסות" }, { kind = it; sel = null }, Modifier.width(180.dp))
                    }
                    if (slices.isEmpty()) Text("אין נתונים לחודש הזה.", color = Palette.secondaryText)
                    else {
                        Donut(slices, sel) { sel = it }
                        slices.forEach { s ->
                            Row(Modifier.fillMaxWidth().clickable { sel = if (sel == s.id) null else s.id }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                IconBubble(Icon.of(s.icon), Palette.token(s.colorToken), 28.dp)
                                Text(s.name, modifier = Modifier.weight(1f))
                                Text("${Math.round(s.share * 100)}%", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                                Amount(s.amount, MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }
            }
            if (sources.isNotEmpty()) item {
                Card {
                    SectionTitle("הכנסות לפי מקור")
                    sources.forEach { s ->
                        Row(verticalAlignment = Alignment.CenterVertically) { Text(s.name, modifier = Modifier.weight(1f)); Amount(s.amount, MaterialTheme.typography.bodyMedium) }
                        ShareBar(s.share, Palette.actual)
                    }
                }
            }
            item {
                val open = vm.data.debts.filter { it.direction == DebtDirection.RECEIVABLE }.map { vm.debtBalance(it) }.filter { it.isOpen }
                val overdue = open.filter { it.isOverdue }.sumOfMoney { it.remaining }
                Card {
                    SectionTitle("גבייה")
                    Row { Text("חובות פתוחים אליי", modifier = Modifier.weight(1f)); Amount(open.sumOfMoney { it.remaining }, color = Palette.receivable) }
                    Row { Text("מתוכם באיחור", modifier = Modifier.weight(1f)); Amount(overdue, color = if (overdue.isPos) Palette.liability else null) }
                    Debts.collectionRate(vm.data)?.let { r ->
                        Row { Text("שיעור גבייה (מכל החובות)", modifier = Modifier.weight(1f)); Text("${Math.round(r * 100)}%") }
                        LinearProgressIndicator(progress = { r.toFloat() }, color = Palette.actual, modifier = Modifier.fillMaxWidth())
                    }
                }
            }
        }
    }
}
