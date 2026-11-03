package com.vainraich.finance.services

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.provider.CalendarContract
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.work.*
import com.vainraich.core.*
import com.vainraich.finance.MainActivity
import com.vainraich.finance.R
import java.io.File
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.TimeZone
import java.util.concurrent.TimeUnit

// ======================= Calendar (CalendarContract) =======================

data class DeviceCalendar(val id: Long, val name: String, val color: Int, val writable: Boolean)

/** Reads/writes the phone's calendar only after the user grants permission. Imported events never get income automatically. */
object CalendarSync {
    const val APP_CALENDAR = "הכספים שלי"
    fun hasRead(ctx: Context) = ContextCompat.checkSelfPermission(ctx, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED
    fun hasWrite(ctx: Context) = ContextCompat.checkSelfPermission(ctx, Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED
    private val zone: ZoneId = ZoneId.of("Asia/Jerusalem")

    fun calendars(ctx: Context): List<DeviceCalendar> {
        if (!hasRead(ctx)) return emptyList()
        val out = mutableListOf<DeviceCalendar>()
        ctx.contentResolver.query(CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars._ID, CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, CalendarContract.Calendars.CALENDAR_COLOR, CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL),
            null, null, null)?.use { c ->
            while (c.moveToNext()) out += DeviceCalendar(c.getLong(0), c.getString(1) ?: "", c.getInt(2), c.getInt(3) >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR)
        }
        return out.sortedBy { it.name }
    }

    fun importEvents(ctx: Context, calendarIds: Set<Long>, range: DateRange): List<FinanceEvent> {
        if (!hasRead(ctx) || calendarIds.isEmpty()) return emptyList()
        val start = range.start.atStartOfDay(zone).toInstant().toEpochMilli()
        val end = range.end.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also { android.content.ContentUris.appendId(it, start); android.content.ContentUris.appendId(it, end) }.build()
        val out = mutableListOf<FinanceEvent>()
        ctx.contentResolver.query(uri,
            arrayOf(CalendarContract.Instances.EVENT_ID, CalendarContract.Instances.TITLE, CalendarContract.Instances.BEGIN, CalendarContract.Instances.END,
                CalendarContract.Instances.ALL_DAY, CalendarContract.Instances.EVENT_LOCATION, CalendarContract.Instances.DESCRIPTION, CalendarContract.Instances.CALENDAR_ID),
            null, null, CalendarContract.Instances.BEGIN)?.use { c ->
            while (c.moveToNext()) {
                if (c.getLong(7) !in calendarIds) continue
                val allDay = c.getInt(4) == 1
                val b = LocalDateTime.ofInstant(java.time.Instant.ofEpochMilli(c.getLong(2)), if (allDay) ZoneId.of("UTC") else zone)
                val e = LocalDateTime.ofInstant(java.time.Instant.ofEpochMilli(c.getLong(3)), if (allDay) ZoneId.of("UTC") else zone)
                out += FinanceEvent(title = c.getString(1) ?: "אירוע", date = b.toLocalDate(),
                    startTime = if (allDay) null else TimeOfDay(b.hour, b.minute), endTime = if (allDay) null else TimeOfDay(e.hour, e.minute),
                    location = c.getString(5) ?: "", notes = c.getString(6) ?: "", calendarEventId = c.getLong(0))
            }
        }
        return out
    }

    private fun appCalendarId(ctx: Context): Long? {
        val cals = calendars(ctx)
        cals.firstOrNull { it.name == APP_CALENDAR && it.writable }?.let { return it.id }
        // Create a local calendar for the app's events.
        val uri = CalendarContract.Calendars.CONTENT_URI.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, "Vainraich")
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL).build()
        val v = ContentValues().apply {
            put(CalendarContract.Calendars.ACCOUNT_NAME, "Vainraich"); put(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            put(CalendarContract.Calendars.NAME, APP_CALENDAR); put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, APP_CALENDAR)
            put(CalendarContract.Calendars.CALENDAR_COLOR, 0xFF0F7675.toInt()); put(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL, CalendarContract.Calendars.CAL_ACCESS_OWNER)
            put(CalendarContract.Calendars.OWNER_ACCOUNT, "Vainraich"); put(CalendarContract.Calendars.VISIBLE, 1); put(CalendarContract.Calendars.SYNC_EVENTS, 1)
            put(CalendarContract.Calendars.CALENDAR_TIME_ZONE, "Asia/Jerusalem")
        }
        return ctx.contentResolver.insert(uri, v)?.lastPathSegment?.toLongOrNull() ?: cals.firstOrNull { it.writable }?.id
    }

    /** Creates or updates the phone-calendar copy of an event. Returns its id. */
    fun export(ctx: Context, e: FinanceEvent): Long? {
        if (!hasWrite(ctx) || !hasRead(ctx)) return null
        val v = ContentValues()
        val notes = listOfNotNull(e.expectedIncome?.takeIf { it.isPos }?.let { "הכנסה צפויה: ${MoneyFormatter.format(it)}" },
            e.expectedExpense?.takeIf { it.isPos }?.let { "הוצאה צפויה: ${MoneyFormatter.format(it)}" }, e.notes.ifBlank { null }).joinToString("\n")
        v.put(CalendarContract.Events.TITLE, e.title); v.put(CalendarContract.Events.EVENT_LOCATION, e.location); v.put(CalendarContract.Events.DESCRIPTION, notes)
        if (e.startTime != null) {
            val s = e.date.atTime(e.startTime!!.hour, e.startTime!!.minute).atZone(zone)
            val endT = e.endTime ?: TimeOfDay((e.startTime!!.hour + 1).coerceAtMost(23), e.startTime!!.minute)
            v.put(CalendarContract.Events.DTSTART, s.toInstant().toEpochMilli())
            v.put(CalendarContract.Events.DTEND, e.date.atTime(endT.hour, endT.minute).atZone(zone).toInstant().toEpochMilli())
            v.put(CalendarContract.Events.EVENT_TIMEZONE, "Asia/Jerusalem"); v.put(CalendarContract.Events.ALL_DAY, 0)
        } else {
            v.put(CalendarContract.Events.DTSTART, e.date.atStartOfDay(ZoneId.of("UTC")).toInstant().toEpochMilli())
            v.put(CalendarContract.Events.DTEND, e.date.plusDays(1).atStartOfDay(ZoneId.of("UTC")).toInstant().toEpochMilli())
            v.put(CalendarContract.Events.EVENT_TIMEZONE, "UTC"); v.put(CalendarContract.Events.ALL_DAY, 1)
        }
        e.calendarEventId?.let { id ->
            val n = ctx.contentResolver.update(android.content.ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id), v, null, null)
            if (n > 0) return id
        }
        val cal = appCalendarId(ctx) ?: return null
        v.put(CalendarContract.Events.CALENDAR_ID, cal)
        return ctx.contentResolver.insert(CalendarContract.Events.CONTENT_URI, v)?.lastPathSegment?.toLongOrNull()
    }
}

// ======================= Reminders (WorkManager, local only) =======================

object Reminders {
    const val CHANNEL = "reminders"
    private const val WORK = "daily-reminders"

    enum class Kind(val key: String, val title: String) {
        DUE("due", "תשלומים שמגיע מועדם"), OVERDUE("overdue", "חובות שעבר מועדם"), EVENTS("events", "אירועים ו\"האם שילמו לך?\""),
        RECURRING("recurring", "תשלומים קבועים וממתינים"), NEGATIVE("negative", "אזהרת יתרה שלילית")
    }

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("reminders", 0)
    fun enabled(ctx: Context, k: Kind) = prefs(ctx).getBoolean(k.key, true)
    fun setEnabled(ctx: Context, k: Kind, v: Boolean) = prefs(ctx).edit().putBoolean(k.key, v).apply()
    fun hour(ctx: Context) = prefs(ctx).getInt("hour", 9)
    fun setHour(ctx: Context, h: Int) { prefs(ctx).edit().putInt("hour", h).apply(); schedule(ctx, replace = true) }
    fun permitted(ctx: Context) = NotificationManagerCompat.from(ctx).areNotificationsEnabled()

    fun createChannel(ctx: Context) {
        ctx.getSystemService(NotificationManager::class.java)
            .createNotificationChannel(NotificationChannel(CHANNEL, "תזכורות תשלומים", NotificationManager.IMPORTANCE_DEFAULT))
    }

    /** One daily check at the chosen hour. */
    fun schedule(ctx: Context, replace: Boolean = false) {
        val now = LocalDateTime.now()
        var next = now.toLocalDate().atTime(hour(ctx), 0)
        if (!next.isAfter(now)) next = next.plusDays(1)
        val delay = java.time.Duration.between(now, next).toMinutes()
        val req = PeriodicWorkRequestBuilder<ReminderWorker>(1, TimeUnit.DAYS).setInitialDelay(delay, TimeUnit.MINUTES).build()
        WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(WORK, if (replace) ExistingPeriodicWorkPolicy.UPDATE else ExistingPeriodicWorkPolicy.KEEP, req)
    }

    /** Pure planning (what to tell the user today). */
    fun plan(data: FinanceData, today: LocalDate, enabled: (Kind) -> Boolean): List<Pair<String, String>> {
        if (data.isDemo) return emptyList()
        val out = mutableListOf<Pair<String, String>>()
        val lead = data.settings.reminderLeadDays.toLong()
        for (b in Debts.balances(data, today)) {
            if (!b.isOpen || !b.remaining.isPos) continue
            val due = b.debt.dueDate ?: continue
            val who = data.contact(b.debt.contactId)?.name.orEmpty()
            val amt = MoneyFormatter.format(b.remaining)
            if (enabled(Kind.DUE) && today == due.minusDays(lead))
                out += "מועד תשלום מתקרב" to (if (b.debt.direction == DebtDirection.RECEIVABLE) "$who אמור/ה להחזיר $amt — ${b.debt.title}" else "צריך לשלם ל$who $amt — ${b.debt.title}")
            if (enabled(Kind.OVERDUE) && due.isBefore(today) && (today.toEpochDay() - due.toEpochDay()) % 7 == 1L)
                out += "חוב שעבר מועדו" to (if (b.debt.direction == DebtDirection.RECEIVABLE) "$who עדיין חייב/ת $amt (${b.debt.title})" else "עדיין לא שילמת ל$who $amt")
        }
        if (enabled(Kind.EVENTS)) {
            for (e in data.events) {
                if (e.date == today.plusDays(1)) out += "מחר: ${e.title}" to listOfNotNull(e.startTime?.let { "ב־$it" }, e.expectedIncome?.takeIf { it.isPos }?.let { "הכנסה צפויה ${MoneyFormatter.format(it)}" }).joinToString(" · ").ifEmpty { e.title }
            }
            val asked = EventMatcher.questions(data, today)
            if (asked.isNotEmpty()) out += "האם שילמו לך?" to (if (asked.size == 1) "על ${asked[0].event.title} — סמן באפליקציה" else "${asked.size} אירועים מחכים לאישור תשלום")
        }
        if (enabled(Kind.RECURRING)) {
            val todays = data.transactions.filter { it.status == TxStatus.PENDING && it.date == today }
            if (todays.isNotEmpty()) out += "תשלומים צפויים היום" to todays.joinToString(", ") { "${it.title} ${MoneyFormatter.format(it.amount)}" }
        }
        if (enabled(Kind.NEGATIVE)) ForecastEngine.make(data, DateRange.next(30, today), today).firstNegativeDay?.let {
            if (today.daysUntil(it.date) in 0..3) out += "אזהרה: היתרה צפויה לרדת מתחת לאפס" to "ב־${it.date.il} היתרה החזויה היא ${MoneyFormatter.format(it.projected)}."
        }
        return out
    }
}

class ReminderWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    override fun doWork(): Result {
        val ctx = applicationContext
        val store = FileStore(File(ctx.filesDir, "finance/finance.json"))
        if (!store.exists() || !Reminders.permitted(ctx)) return Result.success()
        val data = runCatching { store.load() }.getOrNull() ?: return Result.success()
        val open = android.app.PendingIntent.getActivity(ctx, 0, Intent(ctx, MainActivity::class.java), android.app.PendingIntent.FLAG_IMMUTABLE)
        Reminders.plan(data, LocalDate.now(), { Reminders.enabled(ctx, it) }).forEachIndexed { i, (title, body) ->
            val n = NotificationCompat.Builder(ctx, Reminders.CHANNEL).setSmallIcon(R.mipmap.ic_launcher).setContentTitle(title).setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body)).setContentIntent(open).setAutoCancel(true).build()
            try { NotificationManagerCompat.from(ctx).notify(1000 + i, n) } catch (_: SecurityException) {}
        }
        return Result.success()
    }
}

// ======================= Export (CSV / PDF / backup) =======================

object Exporter {
    private fun dir(ctx: Context) = File(ctx.cacheDir, "exports").apply { mkdirs() }

    fun share(ctx: Context, file: File, mime: String) {
        val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".files", file)
        val i = Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        ctx.startActivity(Intent.createChooser(i, "שיתוף").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    fun text(ctx: Context, name: String, content: String): File = File(dir(ctx), name).apply { writeText(content, Charsets.UTF_8) }

    /** Simple printable A4 monthly report (right-to-left text). */
    fun monthlyPdf(ctx: Context, data: FinanceData, month: LocalDate, today: LocalDate): File {
        val m = Reports.monthly(data, month, 1).first()
        val six = Reports.monthly(data, month, 6)
        val cats = Reports.byCategory(data, TxKind.EXPENSE, DateRange.month(month))
        val s = SummaryCalculator.make(data, DateRange.month(month), today)
        val lines = buildList {
            add("דוח חודשי — ${Labels.month(month.monthValue)} ${month.year}" to 20f)
            add("הופק ב־${today.il}${if (data.isDemo) " · נתוני הדגמה" else ""}" to 11f)
            add("" to 8f)
            add("הכנסות: ${MoneyFormatter.format(m.income)}" to 13f)
            add("הוצאות: ${MoneyFormatter.format(m.expenses)}" to 13f)
            add("תזרים נטו: ${MoneyFormatter.format(m.net, showPlus = true)}" to 14f)
            add("" to 8f)
            add("כסף זמין: ${MoneyFormatter.format(s.available)}" to 12f)
            add("חוב בכרטיסי אשראי: ${MoneyFormatter.format(s.creditCardLiability)}" to 12f)
            add("חובות אליי: ${MoneyFormatter.format(s.receivables)}   ·   חובות שלי: ${MoneyFormatter.format(s.payables)}" to 12f)
            add("" to 8f)
            add("שישה חודשים אחרונים" to 14f)
            six.forEach { add("${Labels.month(it.month)} ${it.year}: הכנסות ${MoneyFormatter.format(it.income)} · הוצאות ${MoneyFormatter.format(it.expenses)} · נטו ${MoneyFormatter.format(it.net)}" to 11f) }
            add("" to 8f)
            add("הוצאות לפי קטגוריה" to 14f)
            cats.forEach { add("${it.name}: ${MoneyFormatter.format(it.amount)} (${Math.round(it.share * 100)}%)" to 11f) }
            add("" to 8f)
            add("סכומים צפויים אינם נכללים בכסף הזמין. העברות בין חשבונות ותשלומי אשראי אינם נספרים כהוצאה." to 9f)
        }
        val doc = PdfDocument()
        val page = doc.startPage(PdfDocument.PageInfo.Builder(595, 842, 1).create())
        val canvas = page.canvas
        var y = 40f
        for ((text, size) in lines) {
            val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = size; typeface = if (size >= 14f) Typeface.DEFAULT_BOLD else Typeface.DEFAULT }
            val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, 515).setAlignment(Layout.Alignment.ALIGN_NORMAL)
                .setTextDirection(android.text.TextDirectionHeuristics.RTL).build()
            canvas.save(); canvas.translate(40f, y); layout.draw(canvas); canvas.restore()
            y += layout.height + 6f
            if (y > 800f) break
        }
        doc.finishPage(page)
        val f = File(dir(ctx), "דוח-${month.year}-${"%02d".format(month.monthValue)}.pdf")
        f.outputStream().use { doc.writeTo(it) }
        doc.close()
        return f
    }
}
