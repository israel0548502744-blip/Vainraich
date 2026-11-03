package com.vainraich.finance.services

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.vainraich.core.ai.*
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.URI

enum class AiProvider(val title: String, val price: String, val free: Boolean, val needsKey: Boolean, val keyUrl: String?, val defaultModel: String, val privacy: String?) {
    ON_DEVICE("זיהוי בסיסי בטלפון", "חינם · ללא אינטרנט · דיוק בסיסי", true, false, null, "", null),
    GEMINI("Google Gemini", "יש מסלול חינמי עם מגבלת שימוש", true, true, "https://aistudio.google.com/apikey", GeminiProvider.DEFAULT_MODEL,
        "במסלול החינמי של Google, התוכן שנשלח עשוי לשמש לשיפור המוצרים שלהם. מומלץ להפעיל \"שליחת טקסט בלבד עם הסתרת מספרים\"."),
    OPENROUTER("OpenRouter", "יש מודלים חינמיים (מסומנים free)", true, true, Preset.openRouter.keyUrl, "",
        "חלק מהמודלים החינמיים ב-OpenRouter עשויים לשמור את התוכן. מומלץ להפעיל \"שליחת טקסט בלבד עם הסתרת מספרים\"."),
    GROQ("Groq", "יש מסלול חינמי עם מגבלת שימוש", true, true, Preset.groq.keyUrl, "", "המסמך נשלח לשרתי הספק לעיבוד."),
    MISTRAL("Mistral", "יש מסלול ניסיון חינמי", true, true, Preset.mistral.keyUrl, "", "המסמך נשלח לשרתי הספק לעיבוד."),
    OPENAI("OpenAI", "בתשלום לפי שימוש", false, true, Preset.openAI.keyUrl, "", "המסמך נשלח לשרתי הספק לעיבוד."),
    ANTHROPIC("Anthropic Claude", "בתשלום לפי שימוש", false, true, "https://console.anthropic.com/settings/keys", AnthropicProvider.DEFAULT_MODEL, "המסמך נשלח לשרתי הספק לעיבוד."),
    CUSTOM("שרת משלך (Ollama / LM Studio)", "חינם · רץ על מחשב שלך ברשת הביתית", true, false, null, "", null);

    val remote get() = this != ON_DEVICE
}

/** AI choice + the user's own API keys (encrypted on the phone, never in backups). */
class AiSettings(ctx: Context) {
    private val plain = ctx.getSharedPreferences("ai", 0)
    private val secure: SharedPreferences = runCatching {
        EncryptedSharedPreferences.create(ctx, "ai_keys", MasterKey.Builder(ctx).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV, EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM)
    }.getOrElse { ctx.getSharedPreferences("ai_keys_fallback", 0) }

    var provider: AiProvider
        get() = runCatching { AiProvider.valueOf(plain.getString("provider", null) ?: "") }.getOrDefault(AiProvider.ON_DEVICE)
        set(v) = plain.edit().putString("provider", v.name).apply()
    fun model(p: AiProvider) = plain.getString("model.${p.name}", null) ?: p.defaultModel
    fun setModel(p: AiProvider, m: String) = plain.edit().putString("model.${p.name}", m.trim()).apply()
    fun key(p: AiProvider) = secure.getString("key.${p.name}", "") ?: ""
    fun setKey(p: AiProvider, k: String) = secure.edit().putString("key.${p.name}", k.trim()).apply()
    var customUrl: String
        get() = plain.getString("customUrl", null) ?: Preset.custom.baseUrl
        set(v) = plain.edit().putString("customUrl", v.trim()).apply()
    /** Privacy mode: send text only, with ID/account numbers masked. */
    var textOnly: Boolean
        get() = plain.getBoolean("textOnly", false)
        set(v) = plain.edit().putBoolean("textOnly", v).apply()

    fun extractor(p: AiProvider = provider): DocumentExtractor = when (p) {
        AiProvider.ON_DEVICE -> RuleBasedExtractor()
        AiProvider.GEMINI -> GeminiProvider(key(p), model(p))
        AiProvider.ANTHROPIC -> AnthropicProvider(key(p), model(p))
        AiProvider.OPENROUTER -> OpenAICompatibleProvider(Preset.openRouter.name, key(p), model(p), Preset.openRouter.baseUrl)
        AiProvider.GROQ -> OpenAICompatibleProvider(Preset.groq.name, key(p), model(p), Preset.groq.baseUrl)
        AiProvider.MISTRAL -> OpenAICompatibleProvider(Preset.mistral.name, key(p), model(p), Preset.mistral.baseUrl)
        AiProvider.OPENAI -> OpenAICompatibleProvider(Preset.openAI.name, key(p), model(p), Preset.openAI.baseUrl)
        AiProvider.CUSTOM -> {
            if (!isAllowedBaseUrl(customUrl)) throw AIError("כתובת http מותרת רק לשרת ברשת הביתית (192.168.x.x / 10.x.x.x). לשרת באינטרנט השתמש ב-https.")
            OpenAICompatibleProvider("שרת מקומי", key(p), model(p), customUrl)
        }
    }

    companion object {
        /** https anywhere; plain http only for private LAN addresses. */
        fun isAllowedBaseUrl(url: String): Boolean {
            val u = runCatching { URI(url) }.getOrNull() ?: return false
            if (u.scheme == "https") return true
            if (u.scheme != "http") return false
            val h = u.host ?: return false
            return h == "localhost" || h.startsWith("10.") || h.startsWith("192.168.") || Regex("""^172\.(1[6-9]|2\d|3[01])\.""").containsMatchIn(h)
        }
    }
}

/** A document the user picked or shared into the app. */
sealed class PickedDoc {
    class Images(val bitmaps: List<Bitmap>) : PickedDoc()
    class Pdf(val bytes: ByteArray) : PickedDoc()
    class Text(val text: String) : PickedDoc()
    val description: String get() = when (this) {
        is Images -> if (bitmaps.size == 1) "נבחרה תמונה" else "נבחרו ${bitmaps.size} תמונות"
        is Pdf -> "קובץ PDF"
        is Text -> "טקסט (${text.length} תווים)"
    }
}

object DocumentPrep {
    fun load(ctx: Context, uri: Uri, mime: String?): PickedDoc? {
        val bytes = ctx.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return null
        val type = mime ?: ctx.contentResolver.getType(uri) ?: ""
        return when {
            type == "application/pdf" || uri.toString().endsWith(".pdf", true) -> PickedDoc.Pdf(bytes)
            type.startsWith("image/") -> BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { PickedDoc.Images(listOf(it)) }
            else -> PickedDoc.Text(decodeText(bytes))
        }
    }

    /** UTF-8, falling back to Windows-1255 (some Israeli bank exports). */
    fun decodeText(bytes: ByteArray): String {
        val utf = String(bytes, Charsets.UTF_8)
        return if (utf.contains('�')) String(bytes, charset("windows-1255")) else utf
    }

    fun jpeg(b: Bitmap): ByteArray {
        val scale = minOf(1f, 2000f / maxOf(b.width, b.height))
        val s = if (scale < 1f) Bitmap.createScaledBitmap(b, (b.width * scale).toInt(), (b.height * scale).toInt(), true) else b
        return ByteArrayOutputStream().also { s.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
    }

    fun pdfText(ctx: Context, bytes: ByteArray): String = runCatching {
        PDFBoxResourceLoader.init(ctx)
        PDDocument.load(bytes).use { PDFTextStripper().getText(it) }
    }.getOrDefault("")

    fun renderPdf(ctx: Context, bytes: ByteArray, maxPages: Int = 5): List<Bitmap> {
        val f = File.createTempFile("doc", ".pdf", ctx.cacheDir).apply { writeBytes(bytes) }
        return try {
            ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
                PdfRenderer(pfd).use { r ->
                    (0 until minOf(r.pageCount, maxPages)).map { i ->
                        r.openPage(i).use { p ->
                            Bitmap.createBitmap(p.width * 2, p.height * 2, Bitmap.Config.ARGB_8888).also { bmp ->
                                bmp.eraseColor(android.graphics.Color.WHITE)
                                p.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            }
                        }
                    }
                }
            }
        } finally { f.delete() }
    }

    /** Fits the picked document to what the chosen engine accepts. */
    fun inputs(ctx: Context, doc: PickedDoc, ex: DocumentExtractor, textOnly: Boolean): List<DocInput> {
        val caps = ex.capabilities
        fun text(s: String) = DocInput.Text(if (textOnly) Redactor.redact(s) else s)
        val wantsText = textOnly || (!caps.images && !caps.pdf)
        return when (doc) {
            is PickedDoc.Text -> listOf(text(doc.text))
            is PickedDoc.Pdf -> {
                if (!wantsText && caps.pdf) return listOf(DocInput.Pdf(doc.bytes))
                val t = pdfText(ctx, doc.bytes)
                if (t.trim().length > 40) return listOf(text(t))
                if (!wantsText && caps.images) return renderPdf(ctx, doc.bytes).map { DocInput.Image(jpeg(it), "image/jpeg") }
                throw AIError("זה PDF סרוק (תמונה) ואין בו טקסט. כדי לקרוא אותו צריך לבחור ספק בינה מלאכותית שקורא תמונות, ולכבות את מצב \"טקסט בלבד\".")
            }
            is PickedDoc.Images -> {
                if (!wantsText && caps.images) return doc.bitmaps.map { DocInput.Image(jpeg(it), "image/jpeg") }
                throw AIError("קריאת תמונות דורשת ספק בינה מלאכותית (למשל Gemini החינמי). זיהוי טקסט עברי מתמונה בתוך הטלפון אינו זמין באנדרואיד.")
            }
        }
    }

    fun extract(ctx: Context, doc: PickedDoc, ex: DocumentExtractor, textOnly: Boolean): ExtractionResult {
        val results = inputs(ctx, doc, ex, textOnly).map { ex.extract(it) }
        if (results.isEmpty()) throw AIError.invalid("המסמך ריק")
        var r = results.first()
        for (x in results.drop(1)) r = r.copy(transactions = r.transactions + x.transactions, balances = r.balances + x.balances, warnings = r.warnings + x.warnings)
        if (r.transactions.isEmpty() && r.balances.isEmpty()) r = r.copy(warnings = r.warnings + "לא נמצאו תנועות או יתרות. נסה ספק אחר או צילום ברור יותר.")
        return r
    }
}
