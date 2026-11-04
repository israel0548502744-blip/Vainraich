package com.vainraich.finance.screens

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings as AndroidSettings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.vainraich.core.*
import com.vainraich.core.ai.AIError
import com.vainraich.core.ai.RemoteProvider
import com.vainraich.finance.*
import com.vainraich.finance.services.*
import com.vainraich.finance.ui.*
import com.vainraich.finance.ui.Card
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun SettingsScreen(vm: AppViewModel) {
    val ctx = LocalContext.current
    val activity = ctx as MainActivity
    var lockOn by remember { mutableStateOf(activity.lockEnabled) }
    var confirmErase by remember { mutableStateOf(false) }
    var pendingRestore by remember { mutableStateOf<FinanceData?>(null) }
    val restore = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) pendingRestore = runCatching { FinanceJson.decode(ctx.contentResolver.openInputStream(uri)!!.bufferedReader().readText()) }.getOrElse { vm.error = "הקובץ אינו גיבוי תקין של האפליקציה."; null }
    }
    ScreenScaffold("הגדרות", onBack = vm::pop) { pad ->
        Column(Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(16.dp)) {
            FormSection("נתונים") {
                ValueRow("מצב", if (vm.mode == Mode.DEMO) "הדגמה (לא נשמר)" else "הנתונים שלי")
                if (vm.mode == Mode.DEMO) TextButton(onClick = { vm.exitDemo() }) { Text("מעבר לנתונים שלי") } else TextButton(onClick = { vm.enterDemo() }) { Text("צפייה בהדגמה") }
                ValueRow("חשבונות", "${vm.data.accounts.size}")
                ValueRow("תנועות", "${vm.data.transactions.size}")
            }
            FormSection("חיבורים") {
                NavRow(Icons.Outlined.AutoAwesome, "בינה מלאכותית לקריאת מסמכים", { vm.push(Route.AiSettings) })
                NavRow(Icons.Outlined.CalendarMonth, "יומן הטלפון", { vm.push(Route.CalendarSettings) })
                NavRow(Icons.Outlined.Notifications, "התראות ותזכורות", { vm.push(Route.NotificationSettings) })
                NavRow(Icons.Outlined.Link, "בנקים, אשראי וביט", { vm.push(Route.Integrations) })
            }
            FormSection("אבטחה", "הנתונים נשמרים רק בטלפון, באזור הפרטי של האפליקציה. מפתחות API נשמרים מוצפנים.") {
                SwitchRow("נעילה בטביעת אצבע / זיהוי פנים", lockOn, enabled = activity.canAuthenticate) { on ->
                    if (on) activity.authenticate { ok -> if (ok) { activity.setLockEnabled(true); lockOn = true } } else { activity.setLockEnabled(false); lockOn = false }
                }
            }
            FormSection("תחזית") {
                SwitchRow("לכלול חובות אליי בתחזית", vm.data.settings.includeReceivablesInForecast) { vm.updateSettings(vm.data.settings.copy(includeReceivablesInForecast = it)) }
                SwitchRow("לכלול חובות שלי בתחזית", vm.data.settings.includePayablesInForecast) { vm.updateSettings(vm.data.settings.copy(includePayablesInForecast = it)) }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("תזכורת ${vm.data.settings.reminderLeadDays} ימים לפני מועד", modifier = Modifier.weight(1f))
                    IconButton(onClick = { vm.updateSettings(vm.data.settings.copy(reminderLeadDays = (vm.data.settings.reminderLeadDays - 1).coerceAtLeast(0))) }) { Icon(Icons.Outlined.Remove, "פחות") }
                    IconButton(onClick = { vm.updateSettings(vm.data.settings.copy(reminderLeadDays = (vm.data.settings.reminderLeadDays + 1).coerceAtMost(14))) }) { Icon(Icons.Outlined.Add, "יותר") }
                }
            }
            FormSection("גיבוי וייצוא", "מומלץ לשמור גיבוי ב-Google Drive או בקבצים מדי פעם. הגיבוי כולל את כל הנתונים (ללא מפתחות API).") {
                NavRow(Icons.Outlined.Backup, "גיבוי מלא (קובץ)", { Exporter.share(ctx, Exporter.text(ctx, "גיבוי-כספים-${vm.today}.json", vm.backupJson()), "application/json") })
                NavRow(Icons.Outlined.Restore, "שחזור מגיבוי", { restore.launch(arrayOf("application/json", "*/*")) })
                NavRow(Icons.Outlined.TableChart, "ייצוא כל התנועות (CSV)", { Exporter.share(ctx, Exporter.text(ctx, "כל-התנועות-${vm.today}.csv", Csv.transactions(vm.data.transactions, vm.data)), "text/csv") })
            }
            FormSection { TextButton(onClick = { confirmErase = true }, enabled = vm.mode != Mode.DEMO) { Text("מחיקת כל הנתונים", color = Palette.liability) } }
            FormSection("אודות") {
                ValueRow("גרסה", ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName ?: "")
                Text("האפליקציה לא מתחברת לבנקים ולא שומרת סיסמאות. נתונים נכנסים ידנית או ממסמכים שאתה בוחר לייבא. האפליקציה אינה מספקת ייעוץ פיננסי.", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText, modifier = Modifier.padding(vertical = 8.dp))
            }
        }
    }
    if (confirmErase) ConfirmDialog("למחוק את כל הנתונים?", "כל החשבונות, התנועות, האירועים והחובות יימחקו מהטלפון. אי אפשר לבטל.", "מחיקה לצמיתות", onConfirm = { vm.eraseAll() }, onDismiss = { confirmErase = false })
    pendingRestore?.let { b ->
        ConfirmDialog("לשחזר מהגיבוי?", "בגיבוי: ${b.accounts.size} חשבונות, ${b.transactions.size} תנועות. הנתונים הנוכחיים יוחלפו.", "שחזור",
            onConfirm = { vm.replaceAll(b); vm.show("הנתונים שוחזרו") }, onDismiss = { pendingRestore = null })
    }
}

@Composable
fun AiSettingsScreen(vm: AppViewModel) {
    val ctx = LocalContext.current
    val ai = remember { AiSettings(ctx) }
    val scope = rememberCoroutineScope()
    var provider by remember { mutableStateOf(ai.provider) }
    var key by remember(provider) { mutableStateOf(ai.key(provider)) }
    var model by remember(provider) { mutableStateOf(ai.model(provider)) }
    var url by remember { mutableStateOf(ai.customUrl) }
    var textOnly by remember { mutableStateOf(ai.textOnly) }
    var models by remember(provider) { mutableStateOf<List<String>>(emptyList()) }
    var freeOnly by remember { mutableStateOf(true) }
    var testing by remember { mutableStateOf(false) }
    var result by remember(provider) { mutableStateOf<Pair<Boolean, String>?>(null) }
    fun persist() { ai.setKey(provider, key); ai.setModel(provider, model); if (provider == AiProvider.CUSTOM) ai.customUrl = url }
    DisposableEffect(Unit) { onDispose { persist() } }
    fun saveAndClose() {
        persist(); ai.provider = provider
        if (provider.needsKey && key.isBlank()) { vm.error = "חסר מפתח API. הדבק את המפתח שקיבלת מהספק ואז לחץ שמירה."; return }
        vm.show("ההגדרות נשמרו"); vm.pop()
    }
    ScreenScaffold("בינה מלאכותית", onBack = { persist(); vm.pop() }, actions = {
        TextButton(onClick = ::saveAndClose) { Text("שמירה", fontWeight = FontWeight.Bold) }
    }) { pad ->
        Column(Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(16.dp)) {
            FormSection("מי יקרא את המסמכים", "כל הספקים עובדים עם מפתח API אישי שלך — האפליקציה לא גובה כסף ולא שולחת לשרת שלה. אפשר להחליף ספק בכל רגע.") {
                AiProvider.entries.forEach { p ->
                    Row(Modifier.fillMaxWidth().clickable { persist(); provider = p; ai.provider = p }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(provider == p, { persist(); provider = p; ai.provider = p })
                        Column(Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(p.title)
                                if (p.free) Badge("חינם", Palette.actual)
                            }
                            Text(p.price, style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                        }
                    }
                }
            }
            if (provider.needsKey || provider == AiProvider.CUSTOM) FormSection("חיבור", "המפתח נשמר מוצפן בטלפון בלבד ולא נכלל בגיבויים.") {
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                    if (provider == AiProvider.CUSTOM) OutlinedTextField(url, { url = it }, label = { Text("Server URL (…/v1)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(key, { key = it }, label = { Text("API key") }, singleLine = true, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
                }
                provider.keyUrl?.let { u -> TextButton(onClick = { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(u))) }) { Icon(Icons.Outlined.Key, null); Spacer(Modifier.width(6.dp)); Text("איך משיגים מפתח (נפתח באתר הספק)") } }
            }
            if (provider.remote) {
                FormSection("מודל", "בחר מודל שתומך בתמונות כדי לקרוא צילומים. אם המודל לא תומך — הפעל את מצב הטקסט בלבד למטה.") {
                    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                        OutlinedTextField(model, { model = it }, label = { Text("Model") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    }
                    TextButton(onClick = {
                        persist(); testing = true
                        scope.launch {
                            result = try {
                                val list = withContext(Dispatchers.IO) { (ai.extractor(provider) as RemoteProvider).listModels() }
                                models = list
                                if (model.isBlank()) (list.firstOrNull { it.endsWith(":free") } ?: list.firstOrNull())?.let { model = it; ai.setModel(provider, it) }
                                true to "החיבור תקין — נמצאו ${list.size} מודלים."
                            } catch (e: AIError) { false to e.hebrew } catch (e: Exception) { false to (e.message ?: "שגיאה") }
                            testing = false
                        }
                    }, enabled = !testing) { if (testing) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Icon(Icons.Outlined.Sync, null); Spacer(Modifier.width(6.dp)); Text("טעינת רשימת מודלים ובדיקת חיבור") }
                    result?.let { (ok, msg) -> Text(msg, color = if (ok) Palette.actual else Palette.liability, style = MaterialTheme.typography.labelMedium) }
                    if (models.isNotEmpty()) {
                        if (provider == AiProvider.OPENROUTER) SwitchRow("רק מודלים חינמיים", freeOnly) { freeOnly = it }
                        val shown = if (provider == AiProvider.OPENROUTER && freeOnly) models.filter { it.endsWith(":free") } else models
                        Picker("בחירה מהרשימה", shown, model.takeIf { it.isNotBlank() }, { it }, { model = it; ai.setModel(provider, it) })
                    }
                }
                FormSection("פרטיות", listOfNotNull("במצב הזה המסמך הופך לטקסט על הטלפון, ומספרי ת.ז., חשבון וכרטיס מוחלפים בארבע הספרות האחרונות לפני השליחה. עובד עם קובצי PDF דיגיטליים וטקסט; צילומים דורשים לכבות אותו.", provider.privacy).joinToString("\n\n")) {
                    SwitchRow("שליחת טקסט בלבד עם הסתרת מספרים", textOnly) { textOnly = it; ai.textOnly = it }
                }
            } else FormSection {
                Text("קורא קובצי PDF דיגיטליים וטקסט מודבק — בלי אינטרנט ובלי לשלוח שום דבר. מתאים לדפי תנועות פשוטים. לצילומים ולמסמכים מורכבים בחר ספק בינה מלאכותית (למשל Gemini החינמי).", modifier = Modifier.padding(vertical = 8.dp))
            }
            Button(onClick = ::saveAndClose, modifier = Modifier.fillMaxWidth().padding(top = 12.dp).height(52.dp)) {
                Icon(Icons.Outlined.Check, null); Spacer(Modifier.width(8.dp)); Text("שמירה", fontWeight = FontWeight.Bold)
            }
            if (provider.remote) TextButton(onClick = { persist(); ai.provider = provider; vm.pop(); vm.push(Route.Chat) }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Outlined.AutoAwesome, null); Spacer(Modifier.width(6.dp)); Text("שמירה ומעבר לשיחה עם העוזר")
            }
        }
    }
}

@Composable
fun CalendarSettingsScreen(vm: AppViewModel) {
    val ctx = LocalContext.current
    var granted by remember { mutableStateOf(CalendarSync.hasRead(ctx) && CalendarSync.hasWrite(ctx)) }
    val perm = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted = CalendarSync.hasRead(ctx) && CalendarSync.hasWrite(ctx) }
    var selected by remember { mutableStateOf(setOf<Long>()) }
    var start by remember { mutableStateOf(vm.today) }
    var end by remember { mutableStateOf(vm.today.plusMonths(3)) }
    var msg by remember { mutableStateOf<String?>(null) }
    ScreenScaffold("יומן הטלפון", onBack = vm::pop) { pad ->
        Column(Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(16.dp)) {
            FormSection(footer = "האפליקציה ניגשת ליומן רק כשאתה מבקש. אירועים מיובאים לא מקבלים הכנסה אוטומטית — אירועים שבשמם המילה \"אירוע\" ייבדקו מול הכנסות, ותתבקש לאשר.") {
                ValueRow("הרשאה", if (granted) "מאושרת (ייבוא וייצוא)" else "עדיין לא אושרה")
                if (!granted) TextButton(onClick = { perm.launch(arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)) }) { Text("לאפשר גישה ליומן") }
            }
            if (granted) {
                FormSection("ייבוא אירועים מהיומן") {
                    CalendarSync.calendars(ctx).forEach { c ->
                        Row(Modifier.fillMaxWidth().clickable { selected = selected.toggle(c.id) }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(c.id in selected, { selected = selected.toggle(c.id) })
                            Box(Modifier.size(10.dp).clip(CircleShape).background(Color(c.color)))
                            Spacer(Modifier.width(8.dp)); Text(c.name)
                        }
                    }
                    DateField("מתאריך", start) { start = it }
                    DateField("עד", end) { end = it }
                    TextButton(onClick = {
                        val n = vm.importEvents(CalendarSync.importEvents(ctx, selected, DateRange.of(start, end)))
                        msg = if (n == 0) "לא נמצאו אירועים חדשים." else "יובאו $n אירועים. אירועים בתשלום יופיעו לאישור במסך \"תשלומים על אירועים\"."
                    }, enabled = selected.isNotEmpty()) { Text("ייבוא") }
                }
                FormSection(footer = "האירועים יישמרו ביומן נפרד בשם \"${CalendarSync.APP_CALENDAR}\".") {
                    TextButton(onClick = {
                        var n = 0
                        vm.data.events.filter { !it.date.isBefore(vm.today) }.forEach { e -> CalendarSync.export(ctx, e)?.let { vm.setCalendarId(e.id, it); n++ } }
                        msg = "יוצאו $n אירועים ליומן."
                    }) { Text("ייצוא כל האירועים העתידיים ליומן") }
                }
            }
        }
    }
    msg?.let { m -> AlertDialog(onDismissRequest = { msg = null }, text = { Text(m) }, confirmButton = { TextButton(onClick = { msg = null }) { Text("אישור") } }) }
}

@Composable
fun NotificationSettingsScreen(vm: AppViewModel) {
    val ctx = LocalContext.current
    var permitted by remember { mutableStateOf(Reminders.permitted(ctx)) }
    val perm = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { permitted = Reminders.permitted(ctx) }
    var hour by remember { mutableStateOf(Reminders.hour(ctx)) }
    val toggles = remember { mutableStateMapOf<Reminders.Kind, Boolean>().apply { Reminders.Kind.entries.forEach { put(it, Reminders.enabled(ctx, it)) } } }
    ScreenScaffold("התראות", onBack = vm::pop) { pad ->
        Column(Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(16.dp)) {
            FormSection(footer = "התזכורות נוצרות בטלפון עצמו פעם ביום — בלי שרת ובלי לשלוח נתונים. במצב הדגמה לא נשלחות תזכורות.") {
                if (permitted) Text("✓ התראות מאושרות", color = Palette.actual, modifier = Modifier.padding(vertical = 8.dp))
                else TextButton(onClick = {
                    if (Build.VERSION.SDK_INT >= 33) perm.launch(Manifest.permission.POST_NOTIFICATIONS)
                    else ctx.startActivity(Intent(AndroidSettings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(AndroidSettings.EXTRA_APP_PACKAGE, ctx.packageName))
                }) { Text("הפעלת התראות") }
            }
            FormSection("מה להזכיר") {
                Reminders.Kind.entries.forEach { k -> SwitchRow(k.title, toggles[k] ?: true) { toggles[k] = it; Reminders.setEnabled(ctx, k, it) } }
            }
            FormSection("שעה") {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("תזכורות בשעה ${"%02d:00".format(hour)}", modifier = Modifier.weight(1f))
                    IconButton(onClick = { if (hour > 6) { hour--; Reminders.setHour(ctx, hour) } }) { Icon(Icons.Outlined.Remove, "מוקדם יותר") }
                    IconButton(onClick = { if (hour < 22) { hour++; Reminders.setHour(ctx, hour) } }) { Icon(Icons.Outlined.Add, "מאוחר יותר") }
                }
            }
        }
    }
}

@Composable
fun IntegrationsScreen(vm: AppViewModel) {
    @Composable fun row(t: String, badge: String, c: Color, d: String) {
        Column(Modifier.padding(vertical = 8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) { Text(t, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f)); Badge(badge, c) }
            Text(d, style = MaterialTheme.typography.labelMedium, color = Palette.secondaryText)
        }
    }
    ScreenScaffold("בנקים, אשראי וביט", onBack = vm::pop) { pad ->
        Column(Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(16.dp)) {
            FormSection("עובד עכשיו") {
                row("ייבוא ממסמכים וצילומים", "פעיל", Palette.actual, "אישורי יתרה, דפי תנועות, פירוטי אשראי, קבלות וצילומי ביט. אפשר גם לשתף קובץ מוואטסאפ/מייל ישר לאפליקציה.")
                row("הזנה ידנית", "פעיל", Palette.actual, "כל סוגי התנועות, חובות, אירועים ותשלומים קבועים.")
                row("יומן הטלפון", "פעיל", Palette.actual, "ייבוא וייצוא אירועים, בהרשאתך.")
            }
            FormSection("מגבלות", "פירוט מלא במסמך API_INTEGRATIONS.md של הפרויקט.") {
                row("חיבור ישיר לבנקים ולחברות אשראי", "לא זמין", Palette.neutral, "בישראל רק גוף בעל רישיון \"נותן שירות מידע פיננסי\" מרשות ניירות ערך רשאי למשוך נתונים מהבנקים. האפליקציה לא מתחזה לחיבור כזה ולא מבקשת סיסמת בנק.")
                row("ביט", "ידני / ממסמך", Palette.expected, "אין ממשק פתוח לקריאת היסטוריית ביט של אדם פרטי. אפשר לרשום ידנית או לייבא צילום מסך, ותנועות \"ביט\" בדף הבנק מזוהות כדי למנוע כפילות.")
            }
        }
    }
}

// ======================= Onboarding =======================

@Composable
fun OnboardingScreen(vm: AppViewModel) {
    var step by remember { mutableStateOf(0) }
    var bankName by remember { mutableStateOf("עו״ש") }
    var bank by remember { mutableStateOf("") }
    var bankNeg by remember { mutableStateOf(false) }
    var cash by remember { mutableStateOf("") }
    var bit by remember { mutableStateOf("") }
    var hasCard by remember { mutableStateOf(false) }
    var cardDebt by remember { mutableStateOf("") }
    var cardDay by remember { mutableStateOf(10) }
    val rec = remember { mutableStateListOf(Triple("שכר דירה", "", 1)) }
    var incTitle by remember { mutableStateOf("") }
    var incAmount by remember { mutableStateOf("") }
    var incDate by remember { mutableStateOf(vm.today.plusDays(7)) }
    var evTitle by remember { mutableStateOf("") }
    var evDate by remember { mutableStateOf(vm.today.plusDays(14)) }
    var evIncome by remember { mutableStateOf("") }
    var evClient by remember { mutableStateOf("") }
    fun amt(s: String) = MoneyText.parse(s)?.abs2()

    if (step == 0) {
        Column(Modifier.fillMaxSize().statusBarsPadding().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Spacer(Modifier.height(24.dp))
            Icon(Icons.Outlined.ShowChart, null, tint = Palette.brand, modifier = Modifier.size(64.dp))
            Text("הכספים שלי", style = MaterialTheme.typography.headlineLarge)
            Text("תשובה ברורה אחת: כמה כסף יש לך באמת, כמה צפוי להיכנס, כמה אתה חייב — ואיך זה ייראה בעוד חודש.", style = MaterialTheme.typography.titleMedium, color = Palette.secondaryText)
            listOf(
                Triple(Icons.Outlined.Verified, Palette.actual, "כסף אמיתי מול צפוי" to "הכנסה צפויה לעולם לא מתערבבת ביתרה שלך."),
                Triple(Icons.Outlined.CalendarMonth, Palette.expected, "אירועים ותשלומים" to "יומן עם הכנסות צפויות, וזיהוי אוטומטי אם שילמו לך — באישורך."),
                Triple(Icons.Outlined.People, Palette.receivable, "מי חייב לך" to "תשלומים חלקיים, היסטוריה לכל אדם ותזכורות איחור."),
                Triple(Icons.Outlined.DocumentScanner, Palette.brand, "קריאת מסמכים" to "צלם אישור יתרה או דף חשבון — והנתונים נכנסים לבדיקה."),
            ).forEach { (icon, c, t) ->
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) { IconBubble(icon, c, 40.dp); Column { Text(t.first, fontWeight = FontWeight.SemiBold); Text(t.second, color = Palette.secondaryText) } }
            }
            Button(onClick = { step = 1 }, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text("להתחיל עם הנתונים שלי") }
            OutlinedButton(onClick = { vm.enterDemo() }, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text("להציץ בהדגמה") }
            Text("הנתונים נשמרים רק בטלפון שלך. ההדגמה מסומנת בבירור ולא נשמרת.", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
        }
        return
    }
    val titles = listOf("", "כמה כסף יש לך היום?", "הוצאות קבועות", "הכנסה צפויה", "האירוע הראשון", "הכול מוכן")
    ScreenScaffold(titles[step], onBack = if (step in 1..4) ({ step-- }) else null) { pad ->
        Column(Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(16.dp)) {
            when (step) {
                1 -> {
                    Text("הכנס יתרות נוכחיות. אפשר לדלג ולהוסיף אחר כך, או לייבא אישור יתרה.", color = Palette.secondaryText)
                    FormSection("חשבון בנק") { Field("שם", bankName, { bankName = it }); MoneyField("יתרה", bank, { bank = it }); SwitchRow("במינוס", bankNeg) { bankNeg = it } }
                    FormSection("מזומן וביט") { MoneyField("מזומן", cash, { cash = it }); MoneyField("ביט", bit, { bit = it }) }
                    FormSection(footer = "רכישות באשראי נספרות כהוצאה מיד, והכסף יורד מהבנק רק ביום החיוב — בלי ספירה כפולה.") {
                        SwitchRow("יש לי כרטיס אשראי", hasCard) { hasCard = it }
                        if (hasCard) {
                            MoneyField("חוב שעוד לא ירד", cardDebt, { cardDebt = it })
                            Row(verticalAlignment = Alignment.CenterVertically) { Text("יום חיוב: $cardDay", modifier = Modifier.weight(1f)); IconButton(onClick = { if (cardDay > 1) cardDay-- }) { Icon(Icons.Outlined.Remove, null) }; IconButton(onClick = { if (cardDay < 31) cardDay++ }) { Icon(Icons.Outlined.Add, null) } }
                        }
                    }
                    Button(onClick = {
                        val ok = vm.attempt {
                            var bankId: String? = null
                            amt(bank)?.let { v -> Account(name = bankName.ifBlank { "עו״ש" }, type = AccountType.BANK, openingBalance = if (bankNeg) v.negate() else v, openingDate = vm.today).also { vm.save(it); bankId = it.id } }
                            amt(cash)?.let { vm.save(Account(name = "מזומן", type = AccountType.CASH, openingBalance = it, openingDate = vm.today)) }
                            amt(bit)?.let { vm.save(Account(name = "ביט", type = AccountType.BIT, openingBalance = it, openingDate = vm.today)) }
                            if (hasCard) vm.save(Account(name = "כרטיס אשראי", type = AccountType.CREDIT_CARD, openingBalance = (amt(cardDebt) ?: ZERO).negate(), openingDate = vm.today, billingDay = cardDay, paymentAccountId = bankId))
                        }
                        if (ok) step = if (vm.data.accounts.isEmpty()) 5 else 2
                    }, modifier = Modifier.fillMaxWidth()) { Text("המשך") }
                }
                2 -> {
                    Text("שכר דירה, מנויים, הלוואות — הם ייכנסו לתחזית בכל חודש.", color = Palette.secondaryText)
                    rec.forEachIndexed { i, r ->
                        FormSection {
                            Field("מה", r.first, { rec[i] = r.copy(first = it) })
                            MoneyField("סכום חודשי", r.second, { rec[i] = r.copy(second = it) })
                            Row(verticalAlignment = Alignment.CenterVertically) { Text("ביום ${r.third} בחודש", modifier = Modifier.weight(1f)); IconButton(onClick = { if (r.third > 1) rec[i] = r.copy(third = r.third - 1) }) { Icon(Icons.Outlined.Remove, null) }; IconButton(onClick = { if (r.third < 31) rec[i] = r.copy(third = r.third + 1) }) { Icon(Icons.Outlined.Add, null) } }
                        }
                    }
                    TextButton(onClick = { rec.add(Triple("", "", 1)) }) { Text("+ עוד הוצאה קבועה") }
                    Button(onClick = {
                        val acc = vm.defaultAccountId
                        val ok = acc == null || vm.attempt {
                            rec.forEach { (t, a, d) ->
                                val v = amt(a); if (v == null || !v.isPos || t.isBlank()) return@forEach
                                var s = vm.today.withDayClamped(d); if (s.isBefore(vm.today)) s = vm.today.startOfMonth().plusMonths(1).withDayClamped(d)
                                vm.save(RecurringRule(kind = TxKind.EXPENSE, amount = v, accountId = acc, title = t, frequency = Frequency.MONTHLY, dayOfMonth = d, startDate = s))
                            }
                        }
                        if (ok) step = 3
                    }, modifier = Modifier.fillMaxWidth()) { Text("המשך") }
                }
                3 -> {
                    Text("משכורת או תשלום שאתה מחכה לו. הוא ייכנס לתחזית — לא ליתרה.", color = Palette.secondaryText)
                    FormSection { Field("מה (למשל: משכורת)", incTitle, { incTitle = it }); MoneyField("סכום", incAmount, { incAmount = it }); DateField("מתי", incDate) { incDate = it } }
                    Button(onClick = {
                        val v = amt(incAmount); val acc = vm.defaultAccountId
                        val ok = v == null || !v.isPos || acc == null || vm.attempt { vm.save(Transaction(kind = TxKind.INCOME, status = TxStatus.PENDING, amount = v, accountId = acc, title = incTitle.ifBlank { "הכנסה צפויה" }, date = incDate)) }
                        if (ok) step = 4
                    }, modifier = Modifier.fillMaxWidth()) { Text("המשך") }
                }
                4 -> {
                    Text("עבודה, הופעה, צילום — עם הכנסה צפויה ולקוח.", color = Palette.secondaryText)
                    FormSection { Field("שם האירוע", evTitle, { evTitle = it }); DateField("תאריך", evDate) { evDate = it }; MoneyField("הכנסה צפויה", evIncome, { evIncome = it }); Field("לקוח", evClient, { evClient = it }) }
                    Button(onClick = {
                        val ok = evTitle.isBlank() || vm.attempt {
                            val c = evClient.trim().takeIf { it.isNotEmpty() }?.let { vm.findOrAddContact(it).id }
                            vm.save(FinanceEvent(title = evTitle, date = evDate, contactId = c, expectedIncome = amt(evIncome)?.takeIf { it.isPos }))
                        }
                        if (ok) step = 5
                    }, modifier = Modifier.fillMaxWidth()) { Text("סיום") }
                }
                else -> {
                    Spacer(Modifier.height(40.dp))
                    Icon(Icons.Outlined.CheckCircle, null, tint = Palette.actual, modifier = Modifier.size(72.dp).align(Alignment.CenterHorizontally))
                    Text("טיפ: אפשר לצלם אישור יתרה או דף חשבון במסך \"עוד ← ייבוא ממסמך\", או לשתף קובץ מוואטסאפ ישר לאפליקציה.", color = Palette.secondaryText, modifier = Modifier.padding(24.dp))
                    Button(onClick = { vm.persistNow(); vm.setOnboarded(true) }, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text("למסך הבית") }
                }
            }
        }
    }
}
