package com.vainraich.core.ai

import kotlinx.serialization.json.*
import java.net.HttpURLConnection
import java.net.URL
import java.util.Base64

sealed class DocInput {
    class Image(val bytes: ByteArray, val mime: String) : DocInput()
    class Pdf(val bytes: ByteArray) : DocInput()
    class Text(val text: String) : DocInput()
    val kindName get() = when (this) { is Image -> "image"; is Pdf -> "pdf"; is Text -> "text" }
}

data class Capabilities(val pdf: Boolean, val images: Boolean, val onDevice: Boolean = false)

interface DocumentExtractor {
    val displayName: String
    val capabilities: Capabilities
    fun extract(input: DocInput): ExtractionResult
}

interface RemoteProvider : DocumentExtractor, ChatProvider {
    fun listModels(): List<String>
}

// ---------------- HTTP ----------------

data class HttpRequest(val url: String, val method: String, val headers: Map<String, String>, val body: String?)
data class HttpResponse(val status: Int, val body: String, val headers: Map<String, String>)

fun interface HttpClient { fun send(r: HttpRequest): HttpResponse }

object UrlConnectionHttp : HttpClient {
    override fun send(r: HttpRequest): HttpResponse = try {
        val c = URL(r.url).openConnection() as HttpURLConnection
        c.requestMethod = r.method
        c.connectTimeout = 30_000
        c.readTimeout = 180_000
        r.headers.forEach { (k, v) -> c.setRequestProperty(k, v) }
        if (r.body != null) {
            c.doOutput = true
            c.setRequestProperty("Content-Type", "application/json")
            c.outputStream.use { it.write(r.body.toByteArray(Charsets.UTF_8)) }
        }
        val code = c.responseCode
        val stream = if (code in 200..299) c.inputStream else (c.errorStream ?: c.inputStream)
        val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
        HttpResponse(code, text, c.headerFields.filterKeys { it != null }.mapValues { it.value.firstOrNull().orEmpty() })
    } catch (e: java.io.IOException) {
        throw AIError.network(e.message ?: "")
    }
}

internal object Http {
    fun check(r: HttpResponse) {
        if (r.status in 200..299) return
        val msg = errorMessage(r.body)
        when (r.status) {
            401, 403 -> throw AIError.unauthorized
            429 -> throw AIError.rateLimited(r.headers.entries.firstOrNull { it.key.equals("Retry-After", true) }?.value?.toIntOrNull())
            else -> throw AIError.http(r.status, msg)
        }
    }

    fun errorMessage(body: String): String = runCatching {
        val o = Json.parseToJsonElement(body).jsonObject
        ((o["error"] as? JsonObject)?.get("message") as? JsonPrimitive)?.content
            ?: (o["message"] as? JsonPrimitive)?.content ?: (o["error"] as? JsonPrimitive)?.content
    }.getOrNull() ?: body.take(300)

    fun obj(body: String): JsonObject = runCatching { Json.parseToJsonElement(body).jsonObject }.getOrElse { throw AIError.invalid("not JSON") }
    fun b64(b: ByteArray): String = Base64.getEncoder().encodeToString(b)
}

// ---------------- Gemini ----------------

/** Google Gemini (free tier available; on the free tier Google may use content to improve products). */
class GeminiProvider(
    private val apiKey: String, model: String = DEFAULT_MODEL,
    private val baseUrl: String = "https://generativelanguage.googleapis.com", private val http: HttpClient = UrlConnectionHttp,
) : RemoteProvider {
    val model = model.ifBlank { DEFAULT_MODEL }
    override val displayName get() = "Google Gemini ($model)"
    override val capabilities = Capabilities(pdf = true, images = true)

    fun request(input: DocInput): HttpRequest {
        if (apiKey.isBlank()) throw AIError.missingKey
        val parts = buildJsonArray {
            when (input) {
                is DocInput.Image -> addJsonObject { putJsonObject("inline_data") { put("mime_type", input.mime); put("data", Http.b64(input.bytes)) } }
                is DocInput.Pdf -> addJsonObject { putJsonObject("inline_data") { put("mime_type", "application/pdf"); put("data", Http.b64(input.bytes)) } }
                is DocInput.Text -> addJsonObject { put("text", "DOCUMENT TEXT:\n" + input.text) }
            }
            addJsonObject { put("text", Prompt.user + "\n\n" + Prompt.schemaText) }
        }
        val body = buildJsonObject {
            putJsonObject("systemInstruction") { putJsonArray("parts") { addJsonObject { put("text", Prompt.system) } } }
            putJsonArray("contents") { addJsonObject { put("role", "user"); put("parts", parts) } }
            putJsonObject("generationConfig") { put("responseMimeType", "application/json"); put("temperature", 0) }
        }
        val path = if (model.startsWith("models/")) model else "models/$model"
        return HttpRequest("$baseUrl/v1beta/$path:generateContent", "POST", mapOf("x-goog-api-key" to apiKey), body.toString())
    }

    override fun extract(input: DocInput): ExtractionResult {
        val r = http.send(request(input)); Http.check(r)
        return Prompt.parse(parseText(r.body), displayName)
    }

    override fun listModels(): List<String> {
        if (apiKey.isBlank()) throw AIError.missingKey
        val r = http.send(HttpRequest("$baseUrl/v1beta/models?pageSize=200", "GET", mapOf("x-goog-api-key" to apiKey), null)); Http.check(r)
        return (Http.obj(r.body)["models"] as? JsonArray).orEmpty().mapNotNull { it as? JsonObject }
            .filter { m -> (m["supportedGenerationMethods"] as? JsonArray).orEmpty().any { (it as? JsonPrimitive)?.content == "generateContent" } }
            .mapNotNull { (it["name"] as? JsonPrimitive)?.content?.removePrefix("models/") }.sorted()
    }

    override fun chat(system: String, messages: List<ChatMessage>): String {
        val r = http.send(ChatRequests.gemini(baseUrl, model, apiKey, system, messages)); Http.check(r)
        return parseText(r.body)
    }

    companion object {
        const val DEFAULT_MODEL = "gemini-flash-latest"
        fun parseText(body: String): String {
            val o = Http.obj(body)
            (o["promptFeedback"] as? JsonObject)?.get("blockReason")?.let { throw AIError.refused((it as JsonPrimitive).content) }
            val first = (o["candidates"] as? JsonArray)?.firstOrNull() as? JsonObject ?: throw AIError.invalid("no candidates")
            val text = (((first["content"] as? JsonObject)?.get("parts")) as? JsonArray).orEmpty()
                .mapNotNull { ((it as? JsonObject)?.get("text") as? JsonPrimitive)?.content }.joinToString("")
            if (text.isEmpty()) throw AIError.refused((first["finishReason"] as? JsonPrimitive)?.content ?: "empty")
            return text
        }
    }
}

// ---------------- OpenAI-compatible ----------------

data class Preset(val id: String, val name: String, val baseUrl: String, val keyUrl: String?, val hasFreeTier: Boolean) {
    companion object {
        val openRouter = Preset("openrouter", "OpenRouter", "https://openrouter.ai/api/v1", "https://openrouter.ai/keys", true)
        val groq = Preset("groq", "Groq", "https://api.groq.com/openai/v1", "https://console.groq.com/keys", true)
        val mistral = Preset("mistral", "Mistral", "https://api.mistral.ai/v1", "https://console.mistral.ai/api-keys", true)
        val openAI = Preset("openai", "OpenAI", "https://api.openai.com/v1", "https://platform.openai.com/api-keys", false)
        val custom = Preset("custom", "שרת משלך (Ollama / LM Studio)", "http://192.168.1.10:11434/v1", null, true)
    }
}

class OpenAICompatibleProvider(
    private val name: String, private val apiKey: String, val model: String, private val baseUrl: String,
    private val jsonMode: Boolean = true, private val acceptsImages: Boolean = true, private val http: HttpClient = UrlConnectionHttp,
) : RemoteProvider {
    override val displayName get() = "$name ($model)"
    /** PDFs are converted to text/images on the phone first. */
    override val capabilities get() = Capabilities(pdf = false, images = acceptsImages)

    private val headers: Map<String, String>
        get() = buildMap { if (apiKey.isNotBlank()) put("Authorization", "Bearer $apiKey"); put("X-Title", "Vainraich Finance") }

    fun request(input: DocInput, json: Boolean = jsonMode): HttpRequest {
        if (model.isBlank()) throw AIError.invalid("לא נבחר מודל")
        val content = buildJsonArray {
            if (input is DocInput.Text) addJsonObject { put("type", "text"); put("text", "DOCUMENT TEXT:\n" + input.text) }
            addJsonObject { put("type", "text"); put("text", Prompt.user + "\n\n" + Prompt.schemaText) }
            when (input) {
                is DocInput.Image -> {
                    if (!acceptsImages) throw AIError.unsupported("image")
                    addJsonObject { put("type", "image_url"); putJsonObject("image_url") { put("url", "data:${input.mime};base64,${Http.b64(input.bytes)}") } }
                }
                is DocInput.Pdf -> throw AIError.unsupported("pdf")
                is DocInput.Text -> {}
            }
        }
        val body = buildJsonObject {
            put("model", model)
            putJsonArray("messages") {
                addJsonObject { put("role", "system"); put("content", Prompt.system) }
                addJsonObject { put("role", "user"); put("content", content) }
            }
            if (json) putJsonObject("response_format") { put("type", "json_object") }
        }
        return HttpRequest("${baseUrl.trimEnd('/')}/chat/completions", "POST", headers, body.toString())
    }

    override fun extract(input: DocInput): ExtractionResult {
        var r = http.send(request(input))
        if (r.status == 400 && jsonMode && Http.errorMessage(r.body).contains("response_format", true)) r = http.send(request(input, json = false))
        Http.check(r)
        return Prompt.parse(parseText(r.body), displayName)
    }

    override fun chat(system: String, messages: List<ChatMessage>): String {
        val r = http.send(ChatRequests.openAI(baseUrl, model, headers, system, messages)); Http.check(r)
        return parseText(r.body)
    }

    override fun listModels(): List<String> {
        val r = http.send(HttpRequest("${baseUrl.trimEnd('/')}/models", "GET", headers, null)); Http.check(r)
        return (Http.obj(r.body)["data"] as? JsonArray).orEmpty().mapNotNull { ((it as? JsonObject)?.get("id") as? JsonPrimitive)?.content }.sorted()
    }

    companion object {
        fun parseText(body: String): String {
            val msg = (((Http.obj(body)["choices"] as? JsonArray)?.firstOrNull() as? JsonObject)?.get("message") as? JsonObject)
                ?: throw AIError.invalid("no choices")
            (msg["refusal"] as? JsonPrimitive)?.takeIf { it !is JsonNull && it.content.isNotBlank() }?.let { throw AIError.refused(it.content) }
            return when (val c = msg["content"]) {
                is JsonPrimitive -> c.content
                is JsonArray -> c.mapNotNull { ((it as? JsonObject)?.get("text") as? JsonPrimitive)?.content }.joinToString("")
                else -> throw AIError.invalid("empty content")
            }
        }
    }
}

// ---------------- Anthropic (paid) ----------------

class AnthropicProvider(
    private val apiKey: String, model: String = DEFAULT_MODEL,
    private val baseUrl: String = "https://api.anthropic.com", private val http: HttpClient = UrlConnectionHttp,
) : RemoteProvider {
    val model = model.ifBlank { DEFAULT_MODEL }
    override val displayName get() = "Anthropic Claude ($model)"
    override val capabilities = Capabilities(pdf = true, images = true)

    private val headers get() = mapOf("x-api-key" to apiKey, "anthropic-version" to API_VERSION, "anthropic-beta" to "server-side-fallback-2026-07-01")

    fun request(input: DocInput): HttpRequest {
        if (apiKey.isBlank()) throw AIError.missingKey
        val content = buildJsonArray {
            when (input) {
                is DocInput.Image -> addJsonObject { put("type", "image"); putJsonObject("source") { put("type", "base64"); put("media_type", input.mime); put("data", Http.b64(input.bytes)) } }
                is DocInput.Pdf -> addJsonObject { put("type", "document"); putJsonObject("source") { put("type", "base64"); put("media_type", "application/pdf"); put("data", Http.b64(input.bytes)) } }
                is DocInput.Text -> addJsonObject { put("type", "text"); put("text", "DOCUMENT TEXT:\n" + input.text) }
            }
            addJsonObject { put("type", "text"); put("text", Prompt.user) }
        }
        val body = buildJsonObject {
            put("model", model); put("max_tokens", 16000); put("system", Prompt.system)
            putJsonArray("messages") { addJsonObject { put("role", "user"); put("content", content) } }
            putJsonObject("output_config") { putJsonObject("format") { put("type", "json_schema"); put("schema", Prompt.jsonSchema) } }
            put("fallbacks", "default")
        }
        return HttpRequest("$baseUrl/v1/messages", "POST", headers, body.toString())
    }

    override fun extract(input: DocInput): ExtractionResult {
        val r = http.send(request(input)); Http.check(r)
        return Prompt.parse(parseText(r.body), displayName)
    }

    override fun listModels(): List<String> {
        if (apiKey.isBlank()) throw AIError.missingKey
        val r = http.send(HttpRequest("$baseUrl/v1/models", "GET", headers - "anthropic-beta", null)); Http.check(r)
        return (Http.obj(r.body)["data"] as? JsonArray).orEmpty().mapNotNull { ((it as? JsonObject)?.get("id") as? JsonPrimitive)?.content }
    }

    override fun chat(system: String, messages: List<ChatMessage>): String {
        val r = http.send(ChatRequests.anthropic(baseUrl, model, headers, apiKey, system, messages)); Http.check(r)
        return parseText(r.body)
    }

    companion object {
        const val DEFAULT_MODEL = "claude-opus-5-5"
        const val API_VERSION = "2026-10-21"
        fun parseText(body: String): String {
            val o = Http.obj(body)
            if ((o["stop_reason"] as? JsonPrimitive)?.content == "refusal")
                throw AIError.refused((((o["stop_details"] as? JsonObject)?.get("explanation")) as? JsonPrimitive)?.content ?: "refusal")
            val text = (o["content"] as? JsonArray).orEmpty().mapNotNull { it as? JsonObject }.filter { (it["type"] as? JsonPrimitive)?.content == "text" }
                .mapNotNull { (it["text"] as? JsonPrimitive)?.content }.joinToString("")
            if (text.isEmpty()) throw AIError.invalid("empty content")
            return text
        }
    }
}
