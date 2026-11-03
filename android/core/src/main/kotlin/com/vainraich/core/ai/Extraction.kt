package com.vainraich.core.ai

import com.vainraich.core.*
import kotlinx.serialization.json.*
import java.time.LocalDate

enum class DocumentKind(val key: String, val hebrew: String) {
    BANK_STATEMENT("bank_statement", "דף תנועות בנק"),
    CARD_STATEMENT("credit_card_statement", "פירוט כרטיס אשראי"),
    BALANCE_CONFIRMATION("balance_confirmation", "אישור יתרה"),
    RECEIPT("receipt", "קבלה"),
    INVOICE("invoice", "חשבונית"),
    BIT_SCREENSHOT("bit_screenshot", "צילום מסך מביט"),
    OTHER("other", "מסמך אחר");

    companion object { fun of(s: String?) = entries.firstOrNull { it.key == s?.lowercase() } ?: OTHER }
}

data class ExtractedBalance(val label: String, val amount: Money, val asOf: LocalDate?)

data class ExtractedTx(
    val date: LocalDate?, val description: String, val amount: Money, val moneyIn: Boolean,
    val categoryHint: String? = null, val isCardBillPayment: Boolean = false, val isBit: Boolean = false,
    val counterparty: String? = null, val reference: String? = null,
)

data class ExtractionResult(
    val kind: DocumentKind, val institution: String? = null,
    /** Last 4 digits only. */
    val accountHint: String? = null, val currency: String = "ILS", val statementDate: LocalDate? = null,
    val balances: List<ExtractedBalance> = emptyList(), val transactions: List<ExtractedTx> = emptyList(),
    val warnings: List<String> = emptyList(), val producedBy: String? = null,
)

class AIError(val hebrew: String) : Exception(hebrew) {
    companion object {
        val missingKey = AIError("לא הוגדר מפתח API לספק הזה. אפשר להוסיף אותו בהגדרות ← בינה מלאכותית.")
        fun unsupported(what: String) = AIError("הספק לא תומך בסוג הקובץ הזה ($what).")
        fun rateLimited(sec: Int?) = AIError("הגעת למכסה החינמית של הספק כרגע." + (sec?.let { " נסה שוב בעוד $it שניות." } ?: " נסה שוב מאוחר יותר."))
        val unauthorized = AIError("המפתח נדחה על ידי הספק. בדוק שהעתקת אותו נכון ושהוא פעיל.")
        fun http(code: Int, m: String) = AIError("שגיאה מהספק ($code): $m")
        fun invalid(m: String) = AIError("לא הצלחתי להבין את תשובת הבינה המלאכותית: $m")
        fun refused(m: String) = AIError("הספק סירב לעבד את המסמך: $m")
        fun network(m: String) = AIError("בעיית רשת: $m")
    }
}

object Prompt {
    val system = """
        You extract financial data from Israeli personal-finance documents: bank statements (דף תנועות / עובר ושב), credit-card statements (פירוט חיובים), balance confirmations (אישור יתרה), receipts, invoices and Bit app screenshots. Documents are usually in Hebrew and amounts are in Israeli New Shekels (₪, ILS) unless stated otherwise.

        Rules:
        - Output ONLY one JSON object that follows the schema. No prose, no markdown fences.
        - Never invent data. If a value is not clearly visible, use null or omit the row and add a short note to "warnings".
        - Dates are day-first in Israel (15/12/26 = 15 December 2026). Output dates as YYYY-MM-DD.
        - "amount" is always a positive decimal string with a dot as decimal separator and no thousands separators, e.g. "1234.50".
        - "direction": "in" when money entered the account (זכות, הפקדה, משכורת, קבלה מ…), "out" when it left (חובה, משיכה, חיוב, רכישה). For a credit-card statement every purchase is "out" and a refund (זיכוי) is "in".
        - "is_card_bill_payment": true for bank lines that pay a credit-card company (ויזה, ישראכרט, מקס, כאל, אמריקן אקספרס, חיוב כרטיס).
        - "is_bit": true for Bit transfers (ביט, BIT).
        - "category_hint": a short Hebrew category (מזון, מסעדות, תחבורה, דיור, חשבונות, תקשורת, בריאות, קניות, חינוך, פנאי, עמלות, משכורת, החזר) or null.
        - "balances": every stated balance (יתרה, יתרה זמינה, יתרה ליום, יתרת חוב) with its date if shown. A card debt balance is positive.
        - "account_hint": ONLY the last 4 digits of the account or card number. Never output ID numbers (ת.ז.).
        - Skip summary/total rows; list each transaction once.
        - "document_type": one of bank_statement, credit_card_statement, balance_confirmation, receipt, invoice, bit_screenshot, other.
    """.trimIndent()

    const val user = "Extract the data from this document according to the rules. Return only the JSON object."

    val schemaText = """
        JSON shape:
        {"document_type": "...", "institution": string|null, "account_hint": "1234"|null, "currency": "ILS", "statement_date": "YYYY-MM-DD"|null,
         "balances": [{"label": string, "amount": "0.00", "as_of": "YYYY-MM-DD"|null}],
         "transactions": [{"date": "YYYY-MM-DD"|null, "description": string, "amount": "0.00", "direction": "in"|"out", "category_hint": string|null, "is_card_bill_payment": bool, "is_bit": bool, "counterparty": string|null, "reference": string|null}],
         "warnings": [string]}
    """.trimIndent()

    /** JSON schema for providers with structured output. */
    val jsonSchema: JsonObject by lazy {
        fun t(type: String) = buildJsonObject { put("type", type) }
        fun nullable(type: String) = buildJsonObject { putJsonArray("type") { add(type); add("null") } }
        buildJsonObject {
            put("type", "object"); put("additionalProperties", false)
            putJsonArray("required") { listOf("document_type", "institution", "account_hint", "currency", "statement_date", "balances", "transactions", "warnings").forEach { add(it) } }
            putJsonObject("properties") {
                putJsonObject("document_type") { put("type", "string"); putJsonArray("enum") { DocumentKind.entries.forEach { add(it.key) } } }
                put("institution", nullable("string")); put("account_hint", nullable("string")); put("currency", t("string")); put("statement_date", nullable("string"))
                putJsonObject("balances") {
                    put("type", "array")
                    putJsonObject("items") {
                        put("type", "object"); put("additionalProperties", false)
                        putJsonArray("required") { add("label"); add("amount"); add("as_of") }
                        putJsonObject("properties") { put("label", t("string")); put("amount", t("string")); put("as_of", nullable("string")) }
                    }
                }
                putJsonObject("transactions") {
                    put("type", "array")
                    putJsonObject("items") {
                        put("type", "object"); put("additionalProperties", false)
                        putJsonArray("required") { listOf("date", "description", "amount", "direction", "category_hint", "is_card_bill_payment", "is_bit", "counterparty", "reference").forEach { add(it) } }
                        putJsonObject("properties") {
                            put("date", nullable("string")); put("description", t("string")); put("amount", t("string"))
                            putJsonObject("direction") { put("type", "string"); putJsonArray("enum") { add("in"); add("out") } }
                            put("category_hint", nullable("string")); put("is_card_bill_payment", t("boolean")); put("is_bit", t("boolean"))
                            put("counterparty", nullable("string")); put("reference", nullable("string"))
                        }
                    }
                }
                putJsonObject("warnings") { put("type", "array"); put("items", t("string")) }
            }
        }
    }

    /** First top-level JSON object in model text (tolerates fences/prose). */
    fun extractJsonObject(text: String): String? {
        val start = text.indexOf('{').takeIf { it >= 0 } ?: return null
        var depth = 0; var inStr = false; var esc = false
        for (i in start until text.length) {
            val c = text[i]
            if (inStr) { if (esc) esc = false else if (c == '\\') esc = true else if (c == '"') inStr = false }
            else { if (c == '"') inStr = true; if (c == '{') depth++; if (c == '}') { depth--; if (depth == 0) return text.substring(start, i + 1) } }
        }
        return null
    }

    private fun JsonObject.str(k: String): String? = (this[k] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content?.trim()?.takeIf { it.isNotEmpty() && it != "null" }
    private fun JsonObject.bool(k: String): Boolean = (this[k] as? JsonPrimitive)?.let { it.booleanOrNull ?: (it.content.lowercase() in setOf("true", "yes", "1", "כן")) } ?: false

    /** Lenient parse: malformed rows are skipped, not fatal. */
    fun parse(text: String, producedBy: String): ExtractionResult {
        val js = extractJsonObject(text) ?: throw AIError.invalid("לא נמצא JSON בתשובה")
        val o = runCatching { Json.parseToJsonElement(js).jsonObject }.getOrElse { throw AIError.invalid("התשובה לא תאמה למבנה הצפוי") }
        val balances = (o["balances"] as? JsonArray).orEmpty().mapNotNull { el ->
            val b = el as? JsonObject ?: return@mapNotNull null
            val amt = MoneyText.parse(b.str("amount")) ?: return@mapNotNull null
            ExtractedBalance(b.str("label") ?: "יתרה", amt, DateText.flexible(b.str("as_of")))
        }
        val txs = (o["transactions"] as? JsonArray).orEmpty().mapNotNull { el ->
            val t = el as? JsonObject ?: return@mapNotNull null
            val raw = MoneyText.parse(t.str("amount")) ?: return@mapNotNull null
            val dir = t.str("direction")?.lowercase()
            val moneyIn = !raw.isNeg && dir in setOf("in", "credit", "income", "זכות")
            ExtractedTx(DateText.flexible(t.str("date")), t.str("description").orEmpty(), raw.abs2(), moneyIn, t.str("category_hint"),
                t.bool("is_card_bill_payment"), t.bool("is_bit"), t.str("counterparty"), t.str("reference"))
        }
        val warnings = (o["warnings"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.content }
        return ExtractionResult(DocumentKind.of(o.str("document_type")), o.str("institution"), o.str("account_hint")?.let(Redactor::lastFour),
            (o.str("currency") ?: "ILS").uppercase(), DateText.flexible(o.str("statement_date")), balances, txs, warnings, producedBy)
    }
}

/** Masks identifying numbers before text leaves the phone (keeps last 4 digits). Amounts and dates are untouched. */
object Redactor {
    fun lastFour(s: String): String {
        val digits = s.filter { it.isDigit() }
        return if (digits.length > 4) "****" + digits.takeLast(4) else if (digits.isEmpty()) s else digits
    }

    fun redact(text: String): String {
        var out = text
        out = Regex("""\b(?:\d{4}[ -]){3}\d{4}\b""").replace(out) { lastFour(it.value) }
        out = Regex("""\b\d{2,3}-\d{3}-\d{4,9}\b""").replace(out) { lastFour(it.value) }
        out = Regex("""(?<![\d.,])\d{7,}(?![\d]|[.,]\d)""").replace(out) { lastFour(it.value) }
        out = Regex("""[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}""").replace(out, "[דוא״ל]")
        return out
    }
}
