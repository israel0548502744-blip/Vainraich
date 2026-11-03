package com.vainraich.finance.screens

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.vainraich.core.*
import com.vainraich.finance.*
import com.vainraich.finance.ui.*
import java.io.File
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun TransactionsScreen(vm: AppViewModel) {
    var filter by remember { mutableStateOf(TxFilter()) }
    var showFilters by remember { mutableStateOf(false) }
    var add by remember { mutableStateOf(false) }
    val list = filter.apply(vm.data)
    val pending = if (filter.isActive) emptyList() else list.filter { it.status == TxStatus.PENDING && !it.date.isAfter(vm.today) }
    val groups = list.groupBy { it.date }.toSortedMap(compareByDescending { it })
    ScreenScaffold("תנועות", actions = {
        IconButton(onClick = { showFilters = true }) { Icon(if (filter.isActive) Icons.Outlined.FilterAlt else Icons.Outlined.FilterList, "סינון") }
        Box {
            IconButton(onClick = { add = true }) { Icon(Icons.Outlined.Add, "הוספה") }
            DropdownMenu(add, { add = false }) {
                DropdownMenuItem({ Text("הוצאה") }, { add = false; vm.push(Route.EditTransaction(null, TxKind.EXPENSE)) })
                DropdownMenuItem({ Text("הכנסה") }, { add = false; vm.push(Route.EditTransaction(null, TxKind.INCOME)) })
                DropdownMenuItem({ Text("העברה בין חשבונות") }, { add = false; vm.push(Route.EditTransaction(null, TxKind.TRANSFER)) })
            }
        }
    }) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            item { DemoBanner(vm) }
            item {
                OutlinedTextField(filter.search, { filter = filter.copy(search = it) }, leadingIcon = { Icon(Icons.Outlined.Search, null) },
                    placeholder = { Text("חיפוש לפי תיאור, קטגוריה, חשבון או סכום") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            }
            if (filter.isActive) item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("מסונן: ${list.size} תנועות", modifier = Modifier.weight(1f))
                    TextButton(onClick = { filter = TxFilter(search = filter.search) }) { Text("ניקוי") }
                }
            }
            if (pending.isNotEmpty()) item {
                FormSection("ממתינות לאישור", "לחץ \"בוצע\" כשהתשלום עבר. עד אז הוא לא משנה את היתרה בפועל.") {
                    pending.forEach { t ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.weight(1f)) { TransactionRow(vm, t) { vm.push(Route.EditTransaction(t.id)) } }
                            TextButton(onClick = { vm.confirm(t.id); vm.show("סומן כבוצע") }) { Text("בוצע") }
                        }
                    }
                }
            }
            if (list.isEmpty()) item {
                if (vm.data.transactions.isEmpty()) EmptyState(Icons.Outlined.ReceiptLong, "עוד אין תנועות", "הוסף הוצאה או הכנסה, או ייבא דף חשבון מצולם — והן יופיעו כאן.", "הוספת תנועה") { vm.push(Route.EditTransaction(null)) }
                else EmptyState(Icons.Outlined.SearchOff, "לא נמצאו תוצאות", "נסה מילה אחרת או נקה את הסינון.")
            }
            groups.forEach { (date, items) ->
                item(key = date.toString()) {
                    val net = items.filter { it.countsInReports }.sumOfMoney { if (it.kind == TxKind.INCOME) it.amount else it.amount.negate() }
                    Row(Modifier.padding(horizontal = 6.dp, vertical = 4.dp)) {
                        Text(if (date == vm.today) "היום" else date.weekdayAndDay(), style = MaterialTheme.typography.labelLarge, color = Palette.secondaryText, modifier = Modifier.weight(1f))
                        if (net.signum() != 0) Amount(net, MaterialTheme.typography.labelLarge, color = Palette.secondaryText, plus = true)
                    }
                    com.vainraich.finance.ui.Card(padding = 10.dp) { items.forEach { t -> TransactionRow(vm, t, showDate = false) { vm.push(Route.EditTransaction(t.id)) } } }
                }
            }
        }
    }
    if (showFilters) ModalBottomSheet(onDismissRequest = { showFilters = false }) {
        Column(Modifier.padding(16.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("סינון", style = MaterialTheme.typography.titleLarge)
            Text("סוג", fontWeight = FontWeight.SemiBold)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                TxKind.entries.forEach { k -> FilterChip(k in filter.kinds, { filter = filter.copy(kinds = filter.kinds.toggle(k)) }, { Text(Labels.kind(k)) }) }
            }
            Text("סטטוס", fontWeight = FontWeight.SemiBold)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                TxStatus.entries.forEach { s -> FilterChip(s in filter.statuses, { filter = filter.copy(statuses = filter.statuses.toggle(s)) }, { Text(Labels.status(s)) }) }
            }
            Text("חשבון", fontWeight = FontWeight.SemiBold)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                vm.data.accounts.forEach { a -> FilterChip(a.id in filter.accountIds, { filter = filter.copy(accountIds = filter.accountIds.toggle(a.id)) }, { Text(a.name) }) }
            }
            Text("קטגוריה", fontWeight = FontWeight.SemiBold)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                vm.data.categories.filter { !it.isArchived }.forEach { c -> FilterChip(c.id in filter.categoryIds, { filter = filter.copy(categoryIds = filter.categoryIds.toggle(c.id)) }, { Text(c.name) }) }
            }
            SwitchRow("טווח תאריכים", filter.range != null) { filter = filter.copy(range = if (it) DateRange(vm.today.startOfMonth(), vm.today) else null) }
            filter.range?.let { r ->
                DateField("מ־", r.start) { filter = filter.copy(range = DateRange.of(it, r.end)) }
                DateField("עד", r.end) { filter = filter.copy(range = DateRange.of(r.start, it)) }
            }
            Row { TextButton(onClick = { filter = TxFilter(search = filter.search) }) { Text("איפוס") }; Spacer(Modifier.weight(1f)); Button(onClick = { showFilters = false }) { Text("הצגה") } }
            Spacer(Modifier.height(24.dp))
        }
    }
}

fun <T> Set<T>.toggle(x: T) = if (x in this) this - x else this + x

@Composable
fun TransactionEditor(vm: AppViewModel, id: String?, initialKind: TxKind, eventId: String? = null) {
    val ctx = LocalContext.current
    val existing = vm.data.transaction(id)
    var kind by remember { mutableStateOf(existing?.kind ?: initialKind) }
    var amount by remember { mutableStateOf(existing?.amount?.let { if (it.stripTrailingZeros().scale() <= 0) it.toBigInteger().toString() else it.plain } ?: "") }
    var title by remember { mutableStateOf(existing?.title ?: "") }
    var accountId by remember { mutableStateOf(existing?.accountId ?: vm.defaultAccountId) }
    var counterId by remember { mutableStateOf(existing?.counterAccountId ?: if (initialKind == TxKind.TRANSFER) vm.activeAccounts.firstOrNull { it.type == AccountType.CREDIT_CARD }?.id else null) }
    var categoryId by remember { mutableStateOf(existing?.categoryId) }
    var contactId by remember { mutableStateOf(existing?.contactId) }
    var date by remember { mutableStateOf(existing?.date ?: vm.today) }
    var status by remember { mutableStateOf(existing?.status ?: TxStatus.COMPLETED) }
    var method by remember { mutableStateOf(existing?.paymentMethod) }
    var notes by remember { mutableStateOf(existing?.notes ?: "") }
    var excluded by remember { mutableStateOf(existing?.excludedFromReports ?: false) }
    var attachment by remember { mutableStateOf(existing?.attachmentFile) }
    var recurring by remember { mutableStateOf(false) }
    var freq by remember { mutableStateOf(Frequency.MONTHLY) }
    var interval by remember { mutableStateOf(1) }
    var autoPost by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    val pickPhoto = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) runCatching {
            val bytes = ctx.contentResolver.openInputStream(uri)!!.use { it.readBytes() }
            val dir = File(ctx.filesDir, "attachments").apply { mkdirs() }
            val name = UUID.randomUUID().toString() + ".jpg"
            File(dir, name).writeBytes(bytes); attachment = name
        }
    }
    val isNew = existing == null

    fun save() {
        val amt = MoneyText.parse(amount)?.abs2()
        if (amt == null || !amt.isPos) { vm.error = ValidationError.NonPositiveAmount.hebrew; return }
        val acc = accountId ?: run { vm.error = ValidationError.UnknownAccount.hebrew; return }
        val finalTitle = title.trim().ifEmpty { vm.data.category(categoryId)?.name ?: if (kind == TxKind.TRANSFER) "העברה ל${vm.data.account(counterId)?.name.orEmpty()}" else Labels.kind(kind) }
        val ok = vm.attempt {
            if (isNew && recurring) {
                vm.save(RecurringRule(kind = kind, amount = amt, accountId = acc, counterAccountId = if (kind == TxKind.TRANSFER) counterId else null,
                    categoryId = if (kind == TxKind.TRANSFER) null else categoryId, contactId = contactId, title = finalTitle, frequency = freq, interval = interval,
                    dayOfMonth = if (freq == Frequency.MONTHLY) date.dayOfMonth else null, startDate = date, paymentMethod = method, autoPost = autoPost, notes = notes))
                vm.show("התשלום הקבוע נשמר")
            } else {
                val base = existing ?: Transaction(kind = kind, amount = amt, accountId = acc, title = finalTitle, date = date, eventId = eventId)
                vm.save(base.copy(kind = kind, amount = amt, title = finalTitle, accountId = acc, counterAccountId = if (kind == TxKind.TRANSFER) counterId else null,
                    categoryId = if (kind == TxKind.TRANSFER) null else categoryId, contactId = if (kind == TxKind.TRANSFER) null else contactId, date = date,
                    status = status, paymentMethod = method, notes = notes, excludedFromReports = excluded, attachmentFile = attachment))
                vm.show(if (isNew) "נשמר" else "עודכן")
            }
        }
        if (ok) vm.pop()
    }

    ScreenScaffold(if (isNew) when (kind) { TxKind.INCOME -> "הכנסה חדשה"; TxKind.TRANSFER -> "העברה חדשה"; else -> "הוצאה חדשה" } else "עריכת תנועה",
        onBack = vm::pop, actions = { TextButton(onClick = ::save) { Text("שמירה", fontWeight = FontWeight.Bold) } }) { pad ->
        Column(Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(16.dp)) {
            FormSection {
                if (kind != TxKind.ADJUSTMENT) Segmented(listOf(TxKind.EXPENSE, TxKind.INCOME, TxKind.TRANSFER), kind, Labels::kind, { kind = it; categoryId = null }, Modifier.padding(vertical = 8.dp))
                MoneyField("סכום", amount, { amount = it }, large = true)
                Field(if (kind == TxKind.TRANSFER) "תיאור (למשל: תשלום ויזה)" else "תיאור", title, { title = it })
            }
            val footer = when {
                kind == TxKind.TRANSFER -> "העברה בין החשבונות שלך — כולל תשלום חשבון כרטיס אשראי — לא נספרת כהוצאה, כי ההוצאה כבר נרשמה בזמן הרכישה."
                vm.data.account(accountId)?.type == AccountType.CREDIT_CARD && kind == TxKind.EXPENSE -> "רכישה באשראי נרשמת כהוצאה עכשיו וכחוב בכרטיס. הכסף יירד מהבנק ביום החיוב."
                status == TxStatus.PENDING -> "תנועה ממתינה נכללת בתחזית אבל לא משנה את היתרה בפועל עד שתסמן אותה כבוצעה."
                else -> null
            }
            FormSection(footer = footer) {
                Picker(if (kind == TxKind.TRANSFER) "מחשבון" else "חשבון", vm.activeAccounts, vm.data.account(accountId), { it.name }, { accountId = it.id })
                if (kind == TxKind.TRANSFER) Picker("לחשבון", vm.activeAccounts.filter { it.id != accountId }, vm.data.account(counterId), { it.name }, { counterId = it.id })
                else if (kind != TxKind.ADJUSTMENT) Picker("קטגוריה", vm.data.categories.filter { !it.isArchived && it.kind == if (kind == TxKind.INCOME) CategoryKind.INCOME else CategoryKind.EXPENSE },
                    vm.data.category(categoryId), { it.name }, { categoryId = it.id }, "ללא קטגוריה") { categoryId = null }
                DateField("תאריך", date) { date = it }
                Picker("סטטוס", if (isNew) listOf(TxStatus.COMPLETED, TxStatus.PENDING) else TxStatus.entries, status, { if (it == TxStatus.PENDING) "ממתין / צפוי" else Labels.status(it) }, { status = it })
            }
            if (kind != TxKind.ADJUSTMENT) FormSection("פרטים נוספים") {
                Picker("אמצעי תשלום", PaymentMethod.entries, method, Labels::method, { method = it }, "לא צוין") { method = null }
                if (kind != TxKind.TRANSFER) {
                    ContactPicker(vm, if (kind == TxKind.INCOME) "ממי" else "למי", contactId) { contactId = it }
                    SwitchRow("לא לכלול בדוחות הכנסות/הוצאות", excluded) { excluded = it }
                }
                Field("הערות", notes, { notes = it }, singleLine = false)
            }
            FormSection("קבלה / מסמך") {
                val bmp = remember(attachment) { attachment?.let { BitmapFactory.decodeFile(File(ctx.filesDir, "attachments/$it").path) } }
                if (bmp != null) {
                    Image(bmp.asImageBitmap(), null, Modifier.fillMaxWidth().heightIn(max = 180.dp))
                    TextButton(onClick = { attachment = null }) { Text("הסרת הצרופה", color = Palette.liability) }
                } else TextButton(onClick = { pickPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) {
                    Icon(Icons.Outlined.AttachFile, null); Spacer(Modifier.width(6.dp)); Text("צירוף תמונה של קבלה")
                }
            }
            if (isNew && kind != TxKind.ADJUSTMENT) FormSection(footer = if (recurring) (if (autoPost) "כל מופע יירשם כבוצע ביום שלו (מתאים להוראות קבע)." else "כל מופע יופיע כ\"ממתין\" ביום שלו ותאשר אותו כשהתשלום בוצע.") else null) {
                SwitchRow("תשלום קבוע (חוזר)", recurring) { recurring = it }
                if (recurring) {
                    Picker("תדירות", Frequency.entries, freq, { Labels.frequency(it) }, { freq = it })
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("כל $interval", modifier = Modifier.weight(1f))
                        IconButton(onClick = { if (interval > 1) interval-- }) { Icon(Icons.Outlined.Remove, "פחות") }
                        IconButton(onClick = { if (interval < 24) interval++ }) { Icon(Icons.Outlined.Add, "יותר") }
                    }
                    SwitchRow("לרשום אוטומטית כבוצע", autoPost) { autoPost = it }
                }
            }
            if (!isNew) FormSection {
                vm.data.recurringRules.firstOrNull { it.id == existing?.recurringId }?.let { Text("חלק מתשלום קבוע: ${it.title} · ${Labels.frequency(it.frequency, it.interval)}", style = MaterialTheme.typography.labelMedium, color = Palette.secondaryText) }
                if (vm.data.debtPayments.any { it.transactionId == existing?.id }) Text("תשלום של חוב — שינוי כאן יעדכן גם את החוב", style = MaterialTheme.typography.labelMedium, color = Palette.secondaryText)
                TextButton(onClick = { confirmDelete = true }) { Text("מחיקת התנועה", color = Palette.liability) }
            }
            Spacer(Modifier.height(40.dp))
        }
    }
    if (confirmDelete) ConfirmDialog("למחוק את התנועה?", null, "מחיקה", onConfirm = { existing?.let { vm.deleteTransaction(it.id) }; vm.pop() }, onDismiss = { confirmDelete = false })
}

/** Contact picker with inline creation and the phone's contact picker. */
@Composable
fun ContactPicker(vm: AppViewModel, label: String, selected: String?, allowNone: Boolean = true, onSelect: (String?) -> Unit) {
    val ctx = LocalContext.current
    var newName by remember { mutableStateOf<String?>(null) }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickContact()) { uri ->
        if (uri != null) runCatching {
            ctx.contentResolver.query(uri, arrayOf(android.provider.ContactsContract.Contacts.DISPLAY_NAME, android.provider.ContactsContract.Contacts.LOOKUP_KEY), null, null, null)?.use { c ->
                if (c.moveToFirst()) onSelect(vm.findOrAddContact(c.getString(0) ?: "ללא שם", systemId = c.getString(1)).id)
            }
        }
    }
    Picker(label, vm.data.contacts.sortedBy { it.name }, vm.data.contact(selected), { it.name }, { onSelect(it.id) }, if (allowNone) "ללא" else null, if (allowNone) ({ onSelect(null) }) else null)
    Row {
        TextButton(onClick = { newName = "" }) { Icon(Icons.Outlined.PersonAdd, null); Spacer(Modifier.width(4.dp)); Text("איש קשר חדש") }
        TextButton(onClick = { pick.launch(null) }) { Icon(Icons.Outlined.Contacts, null); Spacer(Modifier.width(4.dp)); Text("מאנשי הקשר בטלפון") }
    }
    newName?.let { n ->
        AlertDialog(onDismissRequest = { newName = null }, title = { Text("איש קשר חדש") }, text = { OutlinedTextField(n, { newName = it }, label = { Text("שם") }, singleLine = true) },
            confirmButton = { TextButton(onClick = { if (n.isNotBlank()) onSelect(vm.addContact(Contact(name = n.trim())).id); newName = null }) { Text("הוספה") } },
            dismissButton = { TextButton(onClick = { newName = null }) { Text("ביטול") } })
    }
}

@Composable
fun RecurringScreen(vm: AppViewModel) {
    val rules = vm.data.recurringRules.sortedBy { it.title }
    ScreenScaffold("תשלומים קבועים", onBack = vm::pop, actions = { IconButton(onClick = { vm.push(Route.EditRule(null)) }) { Icon(Icons.Outlined.Add, "הוספה") } }) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (rules.isEmpty()) item { EmptyState(Icons.Outlined.Repeat, "אין תשלומים קבועים", "שכר דירה, מנויים, משכורת — הוסף אותם פעם אחת והם ייכנסו לתחזית בכל חודש, בלי כפילויות.", "הוספת תשלום קבוע") { vm.push(Route.EditRule(null)) } }
            else item {
                FormSection {
                    val out = rules.filter { it.isActive && it.kind == TxKind.EXPENSE }.sumOfMoney { Recurrence.monthlyEquivalent(it) }
                    val inn = rules.filter { it.isActive && it.kind == TxKind.INCOME }.sumOfMoney { Recurrence.monthlyEquivalent(it) }
                    Row(Modifier.padding(vertical = 6.dp)) { Text("הוצאות קבועות בחודש (בערך)", modifier = Modifier.weight(1f)); Amount(out, color = Palette.liability) }
                    Row(Modifier.padding(vertical = 6.dp)) { Text("הכנסות קבועות בחודש (בערך)", modifier = Modifier.weight(1f)); Amount(inn, color = Palette.actual) }
                }
            }
            items(rules, key = { it.id }) { r ->
                com.vainraich.finance.ui.Card(padding = 12.dp, onClick = { vm.push(Route.EditRule(r.id)) }) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        IconBubble(vm.data.category(r.categoryId)?.let { Icon.of(it.icon) } ?: Icon.kind(r.kind), if (r.isActive) Palette.brand else Palette.neutral)
                        Column(Modifier.weight(1f)) {
                            Text(r.title)
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(Labels.frequency(r.frequency, r.interval) + (Recurrence.next(r, vm.today)?.let { " · הבא: ${it.il}" } ?: ""), style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                                if (!r.isActive) Badge("מושהה", Palette.neutral)
                                if (r.autoPost) Badge("אוטומטי", Palette.brand)
                            }
                        }
                        Amount(if (r.kind == TxKind.INCOME) r.amount else r.amount.negate(), bySign = r.kind == TxKind.INCOME)
                    }
                }
            }
        }
    }
}

@Composable
fun RuleEditor(vm: AppViewModel, id: String?) {
    val r0 = vm.data.recurringRules.firstOrNull { it.id == id }
    var kind by remember { mutableStateOf(r0?.kind ?: TxKind.EXPENSE) }
    var amount by remember { mutableStateOf(r0?.amount?.plain ?: "") }
    var title by remember { mutableStateOf(r0?.title ?: "") }
    var accountId by remember { mutableStateOf(r0?.accountId ?: vm.defaultAccountId) }
    var counterId by remember { mutableStateOf(r0?.counterAccountId) }
    var categoryId by remember { mutableStateOf(r0?.categoryId) }
    var freq by remember { mutableStateOf(r0?.frequency ?: Frequency.MONTHLY) }
    var interval by remember { mutableStateOf(r0?.interval ?: 1) }
    var day by remember { mutableStateOf(r0?.dayOfMonth ?: vm.today.dayOfMonth) }
    var weekdays by remember { mutableStateOf(r0?.weekdays?.toSet() ?: emptySet()) }
    var start by remember { mutableStateOf(r0?.startDate ?: vm.today) }
    var end by remember { mutableStateOf(r0?.endDate) }
    var autoPost by remember { mutableStateOf(r0?.autoPost ?: false) }
    var active by remember { mutableStateOf(r0?.isActive ?: true) }
    fun save() {
        val amt = MoneyText.parse(amount)?.abs2()
        if (amt == null || !amt.isPos) { vm.error = ValidationError.NonPositiveAmount.hebrew; return }
        val acc = accountId ?: run { vm.error = ValidationError.UnknownAccount.hebrew; return }
        if (title.isBlank()) { vm.error = ValidationError.EmptyTitle.hebrew; return }
        val base = r0 ?: RecurringRule(kind = kind, amount = amt, accountId = acc, title = title, frequency = freq, startDate = start)
        if (vm.attempt { vm.save(base.copy(kind = kind, amount = amt, title = title.trim(), accountId = acc, counterAccountId = if (kind == TxKind.TRANSFER) counterId else null,
                categoryId = if (kind == TxKind.TRANSFER) null else categoryId, frequency = freq, interval = interval, dayOfMonth = if (freq == Frequency.MONTHLY) day else null,
                weekdays = if (freq == Frequency.WEEKLY) weekdays.sorted() else emptyList(), startDate = start, endDate = end, autoPost = autoPost, isActive = active)) }) { vm.show("נשמר"); vm.pop() }
    }
    ScreenScaffold(if (r0 == null) "תשלום קבוע חדש" else "עריכת תשלום קבוע", onBack = vm::pop, actions = { TextButton(onClick = ::save) { Text("שמירה", fontWeight = FontWeight.Bold) } }) { pad ->
        Column(Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(16.dp)) {
            FormSection {
                Segmented(listOf(TxKind.EXPENSE, TxKind.INCOME, TxKind.TRANSFER), kind, Labels::kind, { kind = it }, Modifier.padding(vertical = 8.dp))
                MoneyField("סכום", amount, { amount = it }, large = true)
                Field("תיאור (למשל: שכר דירה)", title, { title = it })
                Picker(if (kind == TxKind.TRANSFER) "מחשבון" else "חשבון", vm.activeAccounts, vm.data.account(accountId), { it.name }, { accountId = it.id })
                if (kind == TxKind.TRANSFER) Picker("לחשבון", vm.activeAccounts.filter { it.id != accountId }, vm.data.account(counterId), { it.name }, { counterId = it.id })
                else Picker("קטגוריה", vm.data.categories.filter { it.kind == if (kind == TxKind.INCOME) CategoryKind.INCOME else CategoryKind.EXPENSE }, vm.data.category(categoryId), { it.name }, { categoryId = it.id }, "ללא") { categoryId = null }
            }
            FormSection("מתי", "כל מופע נרשם פעם אחת בלבד. מופעים שכבר נרשמו לא ייווצרו שוב.") {
                Picker("תדירות", Frequency.entries, freq, { Labels.frequency(it) }, { freq = it })
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(Labels.frequency(freq, interval), modifier = Modifier.weight(1f))
                    IconButton(onClick = { if (interval > 1) interval-- }) { Icon(Icons.Outlined.Remove, "פחות") }
                    IconButton(onClick = { if (interval < 24) interval++ }) { Icon(Icons.Outlined.Add, "יותר") }
                }
                if (freq == Frequency.MONTHLY) Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("ביום $day בחודש${if (day >= 29) " (או האחרון)" else ""}", modifier = Modifier.weight(1f))
                    IconButton(onClick = { if (day > 1) day-- }) { Icon(Icons.Outlined.Remove, "פחות") }
                    IconButton(onClick = { if (day < 31) day++ }) { Icon(Icons.Outlined.Add, "יותר") }
                }
                if (freq == Frequency.WEEKLY) Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    (1..7).forEach { d -> FilterChip(d in weekdays, { weekdays = weekdays.toggle(d) }, { Text(Labels.weekdayShort[d - 1]) }) }
                }
                DateField("החל מ־", start) { start = it }
                SwitchRow("עד תאריך", end != null) { end = if (it) start.plusYears(1) else null }
                end?.let { DateField("תאריך סיום", it) { d -> end = d } }
                SwitchRow("לרשום אוטומטית כבוצע", autoPost) { autoPost = it }
                SwitchRow("פעיל", active) { active = it }
            }
            if (r0 != null) TextButton(onClick = { vm.deleteRule(r0.id); vm.pop() }) { Text("מחיקת התשלום הקבוע", color = Palette.liability) }
        }
    }
}
