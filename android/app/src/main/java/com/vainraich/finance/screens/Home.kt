package com.vainraich.finance.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.vainraich.core.*
import com.vainraich.finance.*
import com.vainraich.finance.ui.*
import com.vainraich.finance.ui.Card

enum class Period(val title: String) { TODAY("היום"), WEEK("השבוע"), MONTH("החודש"), CUSTOM("טווח") }

@Composable
fun HomeScreen(vm: AppViewModel) {
    var period by remember { mutableStateOf(Period.MONTH) }
    var customEnd by remember { mutableStateOf(vm.today.plusDays(30)) }
    var addMenu by remember { mutableStateOf(false) }
    val range = when (period) {
        Period.TODAY -> DateRange.day(vm.today); Period.WEEK -> DateRange.week(vm.today)
        Period.MONTH -> DateRange.month(vm.today); Period.CUSTOM -> DateRange.of(vm.today, customEnd)
    }
    val s = vm.summary(range)
    ScreenScaffold("הכסף שלי", actions = {
        IconButton(onClick = { vm.push(Route.Chat) }) { Icon(Icons.Outlined.AutoAwesome, "העוזר שלי", tint = Palette.brand, modifier = Modifier.size(28.dp)) }
        Box {
            IconButton(onClick = { addMenu = true }) { Icon(Icons.Outlined.AddCircle, "הוספה", tint = Palette.brand, modifier = Modifier.size(30.dp)) }
            DropdownMenu(addMenu, { addMenu = false }) {
                DropdownMenuItem({ Text("הוצאה") }, { addMenu = false; vm.push(Route.EditTransaction(null, TxKind.EXPENSE)) }, leadingIcon = { Icon(Icons.Outlined.NorthEast, null) })
                DropdownMenuItem({ Text("הכנסה") }, { addMenu = false; vm.push(Route.EditTransaction(null, TxKind.INCOME)) }, leadingIcon = { Icon(Icons.Outlined.SouthWest, null) })
                DropdownMenuItem({ Text("העברה / תשלום כרטיס") }, { addMenu = false; vm.push(Route.EditTransaction(null, TxKind.TRANSFER)) }, leadingIcon = { Icon(Icons.Outlined.SwapHoriz, null) })
                HorizontalDivider()
                DropdownMenuItem({ Text("אירוע") }, { addMenu = false; vm.push(Route.EditEvent(null)) }, leadingIcon = { Icon(Icons.Outlined.Event, null) })
                DropdownMenuItem({ Text("חוב / גבייה") }, { addMenu = false; vm.push(Route.EditDebt(null)) }, leadingIcon = { Icon(Icons.Outlined.PersonAdd, null) })
                HorizontalDivider()
                DropdownMenuItem({ Text("ייבוא ממסמך") }, { addMenu = false; vm.push(Route.Import) }, leadingIcon = { Icon(Icons.Outlined.DocumentScanner, null) })
            }
        }
    }) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            item { DemoBanner(vm) }
            if (vm.data.accounts.isEmpty()) {
                item { Card { EmptyState(Icons.Outlined.AccountBalance, "בוא נתחיל", "הוסף חשבון בנק, מזומן או ביט עם היתרה הנוכחית — וכל המספרים כאן יתעדכנו.", "הוספת חשבון") { vm.push(Route.EditAccount(null)) } } }
                return@LazyColumn
            }
            item {
                Segmented(Period.entries, period, { it.title }, { period = it })
                if (period == Period.CUSTOM) DateField("עד תאריך", customEnd) { customEnd = it }
            }
            item { EventQuestionsCard(vm) }
            item {
                Card(onClick = { vm.push(Route.Chat) }, padding = 14.dp) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(Modifier.size(40.dp).clip(CircleShape).background(Palette.brandSoft), contentAlignment = Alignment.Center) { Icon(Icons.Outlined.AutoAwesome, null, tint = Palette.brand) }
                        Column(Modifier.weight(1f)) {
                            Text("שאל את העוזר", fontWeight = FontWeight.SemiBold)
                            Text("\"כמה יש לי באמת?\" · \"רשום הוצאה של 50 על דלק\" — בכתב או בקול", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                        }
                        Icon(Icons.Outlined.Mic, null, tint = Palette.brand)
                    }
                }
            }
            item { HeroCard(vm, s) }
            item { EquationCard(vm, s, range) }
            s.forecast.firstNegativeDay?.let { neg -> item { NegativeWarning(neg) } }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        StatTile("חוב בכרטיסי אשראי", s.creditCardLiability, Icons.Outlined.CreditCard, Palette.liability, "ירד מהבנק ביום החיוב", Modifier.weight(1f))
                        StatTile("חייבים לי", s.receivables, Icons.Outlined.People, Palette.receivable,
                            if (s.overdueReceivables.isPos) "באיחור: ${s.overdueReceivables.ils()}" else "לא כלול בכסף הזמין", Modifier.weight(1f))
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        StatTile("אני חייב", s.payables, Icons.Outlined.PanTool, Palette.expected, null, Modifier.weight(1f))
                        StatTile("תזרים ${period.title}", s.periodNet, Icons.Outlined.ImportExport, if (s.periodNet.isNeg) Palette.liability else Palette.actual,
                            "נכנס ${s.periodIncome.ils()} · יצא ${s.periodExpenses.ils()}", Modifier.weight(1f))
                    }
                }
            }
            item { ForecastChart(if (s.forecast.days.size >= 7) s.forecast else vm.forecast(DateRange.next(30, vm.today))) }
            item {
                Card {
                    SectionTitle("תשלומים קרובים")
                    val items = vm.forecast(DateRange.next(14, vm.today)).items.take(6)
                    if (items.isEmpty()) Text("אין תשלומים צפויים בשבועיים הקרובים.", color = Palette.secondaryText)
                    items.forEach { ForecastRow(vm, it) }
                }
            }
            item { Card { SectionTitle("הכנסות והוצאות — 6 חודשים"); MonthlyBars(Reports.monthly(vm.data, vm.today, 6)) } }
        }
    }
}

@Composable
fun EventQuestionsCard(vm: AppViewModel) {
    val q = vm.paymentQuestions
    if (q.isEmpty()) return
    val matches = q.count { it.kind == PaymentQuestion.Kind.POSSIBLE_MATCH }
    Card(padding = 14.dp, onClick = { vm.push(Route.PaymentReview) }) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconBubble(Icons.Outlined.EventAvailable, Palette.expected, 40.dp)
            Column(Modifier.weight(1f)) {
                Text(if (q.size == 1) "אירוע אחד מחכה לאישור תשלום" else "${q.size} אירועים מחכים לאישור תשלום", fontWeight = FontWeight.SemiBold)
                Text(if (matches > 0) "נמצאו הכנסות שנראות כמו התשלום — לאשר?" else "שילמו לך? סמן כדי שהמספרים יהיו מדויקים.", style = MaterialTheme.typography.labelMedium, color = Palette.secondaryText)
            }
            Icon(Icons.Outlined.ChevronLeft, null, tint = Palette.secondaryText)
        }
    }
}

@Composable
private fun HeroCard(vm: AppViewModel, s: Summary) {
    Card {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.Verified, null, tint = Palette.actual, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text("כסף זמין עכשיו", color = Palette.actual, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Text(vm.today.weekdayAndDay(), style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
        }
        Amount(s.available, MaterialTheme.typography.displaySmall.copy(fontWeight = FontWeight.Bold), color = if (s.available.isNeg) Palette.liability else null)
        Text("כסף שנמצא בפועל בחשבונות, במזומן ובביט — בלי הכנסות צפויות.", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(AccountType.BANK, AccountType.CASH, AccountType.BIT, AccountType.OTHER).forEach { t ->
                s.availableByType[t]?.let { v ->
                    Column(Modifier.clip(RoundedCornerShape(10.dp)).background(Palette.elevated).padding(horizontal = 10.dp, vertical = 8.dp)) {
                        Text(Labels.accountType(t), style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                        Amount(v, MaterialTheme.typography.labelLarge)
                    }
                }
            }
        }
    }
}

@Composable
private fun EquationCard(vm: AppViewModel, s: Summary, range: DateRange) {
    Card {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("צפי עד ${if (range.end == vm.today) "סוף היום" else range.end.il}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            TextButton(onClick = { vm.push(Route.Forecast) }) { Text("תחזית מלאה") }
        }
        EqRow("=", "כסף זמין", s.available, Palette.actual)
        EqRow("+", "צפוי להיכנס", s.expectedIncome, Palette.expected)
        EqRow("−", "צפוי לצאת", s.expectedExpenses, Palette.liability)
        HorizontalDivider(color = Palette.separator)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("יתרה חזויה", fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Amount(s.projected, MaterialTheme.typography.titleLarge, bySign = true)
        }
        val est = s.forecast.total(Confidence.ESTIMATED, true)
        if (est.isPos) Text("כולל ${est.ils()} שאחרים אמורים להחזיר לך (משוער).", style = MaterialTheme.typography.labelSmall, color = Palette.receivable)
    }
}

@Composable
private fun EqRow(op: String, title: String, amount: Money, c: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(op, color = Palette.secondaryText, modifier = Modifier.width(16.dp))
        Box(Modifier.size(8.dp).clip(CircleShape).background(c))
        Text(title, modifier = Modifier.weight(1f))
        Amount(amount, MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun NegativeWarning(d: ForecastDay) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Palette.liability.copy(alpha = 0.1f)).padding(14.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(Icons.Outlined.Warning, null, tint = Palette.liability)
        Column {
            Text("היתרה צפויה לרדת מתחת לאפס", fontWeight = FontWeight.SemiBold)
            Text("ב־${d.date.long()} היתרה החזויה היא ${d.projected.ils()}. כדאי להקדים גבייה או לדחות תשלום.", style = MaterialTheme.typography.labelMedium, color = Palette.secondaryText)
        }
    }
}

@Composable
fun ForecastScreen(vm: AppViewModel) {
    var days by remember { mutableStateOf(30) }
    var custom by remember { mutableStateOf(false) }
    var end by remember { mutableStateOf(vm.today.plusDays(60)) }
    val range = if (custom) DateRange.of(vm.today, end) else DateRange.next(days, vm.today)
    val f = vm.forecast(range)
    ScreenScaffold("תחזית תזרים", onBack = vm::pop) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                Segmented(listOf(7, 30, 90, 0), if (custom) 0 else days, { if (it == 0) "מותאם" else "$it ימים" }, { if (it == 0) custom = true else { custom = false; days = it } })
                if (custom) DateField("עד תאריך", end) { end = it }
            }
            item { ForecastChart(f) }
            item {
                FormSection("סיכום", "מאושר = תנועות שהזנת עם סכום ותאריך וחיובי כרטיס ידועים. צפוי = תשלומים קבועים ואירועים. משוער = כסף שתלוי באחרים. אף אחד מהם לא נספר ככסף זמין עד שהוא מתקבל בפועל.") {
                    SumRow("כסף זמין היום", f.starting, Palette.actual)
                    SumRow("מאושר — נכנס", f.total(Confidence.CONFIRMED, true), Palette.actual)
                    SumRow("מאושר — יוצא", f.total(Confidence.CONFIRMED, false).negate(), Palette.liability)
                    SumRow("צפוי — נכנס", f.total(Confidence.EXPECTED, true), Palette.expected)
                    SumRow("צפוי — יוצא", f.total(Confidence.EXPECTED, false).negate(), Palette.expected)
                    SumRow("משוער — חובות אליי", f.total(Confidence.ESTIMATED, true), Palette.receivable)
                    HorizontalDivider(color = Palette.separator)
                    Row(Modifier.padding(vertical = 8.dp)) { Text("יתרה חזויה בסוף הטווח", fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f)); Amount(f.ending, bySign = true) }
                    Row(Modifier.padding(vertical = 4.dp)) { Text("רק על בסיס מאושר", modifier = Modifier.weight(1f)); Amount(f.endingConfirmed, bySign = true) }
                    f.firstNegativeDay?.let { Text("ב־${it.date.il} היתרה צפויה לרדת ל־${it.projected.ils()}", color = Palette.liability, modifier = Modifier.padding(vertical = 6.dp)) }
                }
            }
            item {
                FormSection {
                    SwitchRow("לכלול חובות שאחרים חייבים לי", vm.data.settings.includeReceivablesInForecast) { vm.updateSettings(vm.data.settings.copy(includeReceivablesInForecast = it)) }
                    SwitchRow("לכלול חובות שאני חייב", vm.data.settings.includePayablesInForecast) { vm.updateSettings(vm.data.settings.copy(includePayablesInForecast = it)) }
                }
            }
            item {
                FormSection("מה צפוי (${f.items.size})") {
                    if (f.items.isEmpty()) Text("אין פריטים צפויים בטווח הזה.", color = Palette.secondaryText, modifier = Modifier.padding(vertical = 8.dp))
                    f.items.forEach { ForecastRow(vm, it) }
                }
            }
        }
    }
}

@Composable
private fun SumRow(t: String, a: Money, c: Color) {
    Row(Modifier.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(c)); Text(t, modifier = Modifier.weight(1f)); Amount(a)
    }
}

@Composable
fun MoreScreen(vm: AppViewModel) {
    ScreenScaffold("עוד") { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp)) {
            item { DemoBanner(vm) }
            item {
                FormSection("הכסף שלי") {
                    NavRow(Icons.Outlined.AccountBalance, "חשבונות", { vm.push(Route.Accounts) })
                    NavRow(Icons.Outlined.ShowChart, "תחזית תזרים", { vm.push(Route.Forecast) })
                    NavRow(Icons.Outlined.PieChart, "דוחות וניתוחים", { vm.push(Route.Reports) })
                    NavRow(Icons.Outlined.Repeat, "תשלומים קבועים", { vm.push(Route.Recurring) })
                    NavRow(Icons.Outlined.EventAvailable, "תשלומים על אירועים", { vm.push(Route.PaymentReview) }, vm.paymentQuestions.size.takeIf { it > 0 }?.toString())
                }
            }
            item {
                FormSection("הכנסת נתונים") {
                    NavRow(Icons.Outlined.AutoAwesome, "העוזר שלי — שיחה עם בינה מלאכותית", { vm.push(Route.Chat) })
                    NavRow(Icons.Outlined.DocumentScanner, "ייבוא ממסמך או צילום", { vm.push(Route.Import) })
                    NavRow(Icons.Outlined.Contacts, "אנשי קשר", { vm.push(Route.Contacts) })
                    NavRow(Icons.Outlined.Sell, "קטגוריות", { vm.push(Route.Categories) })
                }
            }
            item { FormSection { NavRow(Icons.Outlined.Settings, "הגדרות", { vm.push(Route.Settings) }) } }
        }
    }
}
