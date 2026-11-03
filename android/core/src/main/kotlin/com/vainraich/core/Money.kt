package com.vainraich.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonPrimitive
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * Money is always BigDecimal with scale 2 (agorot). Never Double.
 * All amounts in the model are normalised with [m2] so `==` compares values correctly.
 */
typealias Money = BigDecimal

val ZERO: Money = BigDecimal.ZERO.setScale(2)

fun Money.m2(): Money = setScale(2, RoundingMode.HALF_UP)
fun money(v: Int): Money = BigDecimal(v).m2()
fun money(v: String): Money = BigDecimal(v).m2()
fun Money.abs2(): Money = abs().m2()
val Money.isNeg: Boolean get() = signum() < 0
val Money.isPos: Boolean get() = signum() > 0
fun Iterable<Money>.sumMoney(): Money = fold(ZERO) { a, b -> a + b }.m2()
inline fun <T> Iterable<T>.sumOfMoney(f: (T) -> Money): Money = fold(ZERO) { a, t -> a + f(t) }.m2()

/** Canonical machine text: "1234.50". */
val Money.plain: String get() = m2().toPlainString()

object MoneyText {
    /**
     * Parses money written by humans or models: "1,234.50", "₪ 1,234", "-120", "(120.00)", "120.00-", "1.234,56", "12,5".
     * Never goes through Double.
     */
    fun parse(raw: String?): Money? {
        if (raw == null) return null
        var s = raw.trim()
        if (s.isEmpty()) return null
        var negative = false
        if (s.startsWith("(") && s.endsWith(")")) { negative = true; s = s.substring(1, s.length - 1) }
        s = s.replace('−', '-').replace('–', '-')
        s = s.filter { !(it.isLetter() || it.isWhitespace() || it in "₪$€£'‏‎‪‫‬⁦⁧⁨⁩ ") }
        if (s.endsWith("-")) { negative = !negative; s = s.dropLast(1) }
        if (s.startsWith("-")) { negative = !negative; s = s.drop(1) }
        if (s.startsWith("+")) s = s.drop(1)
        if (s.isEmpty()) return null
        val commas = s.count { it == ',' }
        val dots = s.count { it == '.' }
        s = when {
            commas > 0 && dots > 0 ->
                if (s.lastIndexOf(',') > s.lastIndexOf('.')) s.replace(".", "").replace(",", ".") else s.replace(",", "")
            commas == 1 -> if (s.substringAfter(',').length == 3) s.replace(",", "") else s.replace(",", ".")
            commas > 1 -> s.replace(",", "")
            dots > 1 -> s.replace(".", "")
            else -> s
        }
        if (!s.all { it.isDigit() || it == '.' } || !s.any { it.isDigit() }) return null
        val v = s.toBigDecimalOrNull() ?: return null
        return (if (negative) v.negate() else v).m2()
    }
}

/** Deterministic Israeli formatting, independent of device locale. */
object MoneyFormatter {
    fun symbol(currency: String) = when (currency.uppercase()) {
        "ILS" -> "₪"; "USD" -> "$"; "EUR" -> "€"; "GBP" -> "£"; else -> currency.uppercase() + " "
    }

    /** "₪1,500" / "₪1,500.50" / "-₪300" / "+₪300". */
    fun format(amount: Money, currency: String = "ILS", alwaysCents: Boolean = false, showPlus: Boolean = false): String {
        val r = amount.m2()
        val mag = r.abs().toPlainString()
        val intPart = mag.substringBefore('.')
        val frac = mag.substringAfter('.', "00").padEnd(2, '0').take(2)
        val grouped = intPart.reversed().chunked(3).joinToString(",").reversed()
        val body = if (alwaysCents || frac != "00") "$grouped.$frac" else grouped
        val sign = if (r.isNeg) "-" else if (showPlus && r.isPos) "+" else ""
        return sign + symbol(currency) + body
    }

    /** Chart axes: "₪12.5K". Display only. */
    fun compact(amount: Money, currency: String = "ILS"): String {
        val v = amount.toDouble()
        val sign = if (v < 0) "-" else ""
        val a = kotlin.math.abs(v)
        val sym = symbol(currency)
        fun t(x: Double) = String.format(java.util.Locale.US, "%.1f", x).removeSuffix(".0")
        return when {
            a >= 1_000_000 -> "$sign$sym${t(a / 1_000_000)}M"
            a >= 1_000 -> "$sign$sym${t(a / 1_000)}K"
            else -> "$sign$sym${Math.round(a)}"
        }
    }
}

// ---------- Dates ----------

private val IL_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("dd/MM/yyyy")

/** "15/12/2026". */
val LocalDate.il: String get() = format(IL_FORMAT)

/** 1 = Sunday … 7 = Saturday (Israeli week). */
val LocalDate.weekdaySun1: Int get() = dayOfWeek.value % 7 + 1

fun LocalDate.startOfWeekSunday(): LocalDate = minusDays((weekdaySun1 - 1).toLong())
fun LocalDate.startOfMonth(): LocalDate = withDayOfMonth(1)
fun LocalDate.endOfMonth(): LocalDate = withDayOfMonth(lengthOfMonth())
fun LocalDate.withDayClamped(day: Int): LocalDate = withDayOfMonth(day.coerceIn(1, lengthOfMonth()))
fun LocalDate.daysUntil(other: LocalDate): Long = other.toEpochDay() - toEpochDay()

object DateText {
    fun iso(s: String?): LocalDate? = s?.trim()?.take(10)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }

    /** Day-first: "15/12/2026", "1.2.26", "1-2-2026". */
    fun israeli(s: String?): LocalDate? {
        if (s == null) return null
        val parts = s.trim().split('/', '.', '-').filter { it.isNotEmpty() }
        if (parts.size != 3) return null
        val d = parts[0].toIntOrNull() ?: return null
        val m = parts[1].toIntOrNull() ?: return null
        var y = parts[2].toIntOrNull() ?: return null
        if (y < 100) y += 2000
        return runCatching { LocalDate.of(y, m, d) }.getOrNull()
    }

    fun flexible(s: String?): LocalDate? = iso(s) ?: israeli(s)
}

/** Closed range of days. */
data class DateRange(val start: LocalDate, val end: LocalDate) {
    init { require(!end.isBefore(start)) { "end before start" } }
    operator fun contains(d: LocalDate) = !d.isBefore(start) && !d.isAfter(end)
    val dayCount: Int get() = (start.daysUntil(end) + 1).toInt()
    val days: List<LocalDate> get() = (0 until dayCount).map { start.plusDays(it.toLong()) }

    companion object {
        /** Builds a range, swapping the bounds if needed. */
        fun of(a: LocalDate, b: LocalDate) = if (b.isBefore(a)) DateRange(b, a) else DateRange(a, b)
        fun day(d: LocalDate) = DateRange(d, d)
        fun week(d: LocalDate) = d.startOfWeekSunday().let { DateRange(it, it.plusDays(6)) }
        fun month(d: LocalDate) = DateRange(d.startOfMonth(), d.endOfMonth())
        fun next(days: Int, from: LocalDate) = DateRange(from, from.plusDays((maxOf(days, 1) - 1).toLong()))
    }
}

// ---------- Serializers ----------

object MoneySerializer : KSerializer<BigDecimal> {
    override val descriptor = PrimitiveSerialDescriptor("Money", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: BigDecimal) = encoder.encodeString(value.plain)
    override fun deserialize(decoder: Decoder): BigDecimal {
        if (decoder is JsonDecoder) {
            val el = decoder.decodeJsonElement()
            val p = el as? JsonPrimitive ?: error("amount")
            return MoneyText.parse(p.content) ?: error("bad amount ${p.content}")
        }
        return MoneyText.parse(decoder.decodeString()) ?: error("bad amount")
    }
}

object LocalDateSerializer : KSerializer<LocalDate> {
    override val descriptor = PrimitiveSerialDescriptor("LocalDate", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: LocalDate) = encoder.encodeString(value.toString())
    override fun deserialize(decoder: Decoder): LocalDate = LocalDate.parse(decoder.decodeString())
}
