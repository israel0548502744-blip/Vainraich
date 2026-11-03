package com.vainraich.core

import com.vainraich.core.ai.*
import kotlinx.serialization.json.*
import org.junit.Test
import java.time.LocalDate
import kotlin.test.*

private val sample = """
{"document_type":"bank_statement","institution":"בנק לאומי","account_hint":"12-345-678901","currency":"ils","statement_date":"2026-10-31",
 "balances":[{"label":"יתרה ליום 31/10/2026","amount":"5,000.00","as_of":"31/10/2026"}],
 "transactions":[
  {"date":"2026-10-01","description":"משכורת","amount":"9400.00","direction":"in","category_hint":"משכורת","is_card_bill_payment":false,"is_bit":false,"counterparty":null,"reference":"123"},
  {"date":"10/10/2026","description":"ויזה כאל","amount":"1,670.50","direction":"out","category_hint":null,"is_card_bill_payment":true,"is_bit":false},
  {"date":"2026-10-12","description":"העברה בביט לנועה","amount":-120,"direction":"in","is_bit":true},
  {"date":"bad","description":"שבור","amount":"x","direction":"out"}
 ],"warnings":[]}
""".trimIndent()

private class Mock(val status: Int = 200, val body: String) : HttpClient {
    var last: HttpRequest? = null
    override fun send(r: HttpRequest): HttpResponse { last = r; return HttpResponse(status, body, mapOf("Retry-After" to "30")) }
}

private fun quoted(s: String) = JsonPrimitive(s).toString()

class AiTest {
    private val today = LocalDate.of(2026, 11, 2)

    @Test fun lenientParse() {
        val r = Prompt.parse("Here:\n```json\n$sample\n```", "t")
        assertEquals(DocumentKind.BANK_STATEMENT, r.kind)
        assertEquals("ILS", r.currency)
        assertEquals("****8901", r.accountHint)
        assertEquals(money(5000), r.balances.first().amount)
        assertEquals(3, r.transactions.size)
        assertEquals(money("1670.50"), r.transactions[1].amount)
        assertFalse(r.transactions[2].moneyIn)
        assertFailsWith<AIError> { Prompt.parse("no json", "x") }
    }

    @Test fun geminiRequest() {
        val m = Mock(body = """{"candidates":[{"content":{"parts":[{"text":${quoted(sample)}}]}}]}""")
        val r = GeminiProvider("KEY", http = m).extract(DocInput.Pdf("pdf".toByteArray()))
        assertEquals(3, r.transactions.size)
        assertEquals("https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent", m.last!!.url)
        assertEquals("KEY", m.last!!.headers["x-goog-api-key"])
        assertFailsWith<AIError> { GeminiProvider("", http = m).extract(DocInput.Text("x")) }
        val limited = assertFailsWith<AIError> { GeminiProvider("k", http = Mock(429, """{"error":{"message":"quota"}}""")).extract(DocInput.Text("x")) }
        assertTrue(limited.hebrew.contains("30"))
    }

    @Test fun openAICompatibleAndAnthropic() {
        val m = Mock(body = """{"choices":[{"message":{"content":${quoted(sample)}}}]}""")
        OpenAICompatibleProvider("OpenRouter", "sk", "x/y:free", Preset.openRouter.baseUrl, http = m).extract(DocInput.Image(byteArrayOf(1), "image/jpeg"))
        assertEquals("https://openrouter.ai/api/v1/chat/completions", m.last!!.url)
        assertEquals("Bearer sk", m.last!!.headers["Authorization"])
        assertFailsWith<AIError> { OpenAICompatibleProvider("x", "k", "m", "https://x", http = m).extract(DocInput.Pdf(byteArrayOf())) }
        val a = Mock(body = """{"content":[{"type":"text","text":${quoted(sample)}}],"stop_reason":"end_turn"}""")
        AnthropicProvider("ak", http = a).extract(DocInput.Pdf("%PDF".toByteArray()))
        assertEquals("2026-10-21", a.last!!.headers["anthropic-version"])
        val body = Json.parseToJsonElement(a.last!!.body!!).jsonObject
        assertEquals("claude-opus-5-5", body["model"]!!.jsonPrimitive.content)
        assertNotNull(body["output_config"])
    }

    @Test fun redactor() {
        val r = Redactor.redact("ת.ז. 123456782 חשבון 12-345-678901 כרטיס 4580 1234 5678 9012 סכום 1,234.56 תאריך 15/10/2026 a.b@x.com")
        assertFalse(r.contains("123456782")); assertTrue(r.contains("****6782")); assertTrue(r.contains("****8901")); assertTrue(r.contains("****9012"))
        assertTrue(r.contains("1,234.56")); assertTrue(r.contains("15/10/2026")); assertFalse(r.contains("a.b@x.com"))
    }

    @Test fun ruleBased() {
        val text = """
            01/10/2026 משכורת 9,400.00 12,400.00
            02/10/2026 שכר דירה 3,800.00 8,600.00
            10/10/2026 ויזה כאל חיוב 1,670.50 6,929.50
            12/10/2026 העברה בביט 120.00 6,809.50
            יתרה ליום 31/10/2026 6,809.50
        """.trimIndent()
        val r = RuleBasedExtractor().extract(DocInput.Text(text))
        assertEquals(4, r.transactions.size)
        assertTrue(r.transactions[0].moneyIn); assertFalse(r.transactions[1].moneyIn)
        assertTrue(r.transactions[2].isCardBillPayment); assertTrue(r.transactions[3].isBit)
        assertEquals(money("6809.50"), r.balances.first().amount)
    }

    @Test fun importPlanner() {
        val bank = Account(name = "עו״ש", type = AccountType.BANK, openingDate = LocalDate.of(2026, 9, 1))
        val card = Account(name = "ויזה", type = AccountType.CREDIT_CARD, billingDay = 10, paymentAccountId = bank.id)
        val bit = Account(name = "ביט", type = AccountType.BIT)
        val salary = Transaction(kind = TxKind.INCOME, amount = money(9400), accountId = bank.id, title = "משכורת", date = LocalDate.of(2026, 10, 1))
        val bitTx = Transaction(kind = TxKind.EXPENSE, amount = money(120), accountId = bit.id, title = "ביט לנועה", date = LocalDate.of(2026, 10, 11))
        var data = FinanceData(accounts = listOf(bank, card, bit), transactions = listOf(salary, bitTx))
        val plan = ImportPlanner.plan(Prompt.parse(sample, "t"), bank.id, data, today)
        assertEquals(salary.id, plan.candidates[0].duplicateOf); assertFalse(plan.candidates[0].include)
        assertEquals(TxKind.TRANSFER, plan.candidates[1].transaction.kind); assertEquals(card.id, plan.candidates[1].transaction.counterAccountId)
        assertEquals(bitTx.id, plan.candidates[2].duplicateOf)
        val s = plan.balances.first()
        assertEquals(money("7729.50"), s.appBalance)
        assertEquals(money("2729.50"), ImportPlanner.adjustment(s, bank.id, today)!!.amount)
        // Re-import detection
        data = data.copy(transactions = data.transactions + plan.candidates.filter { it.include }.map { it.transaction })
        assertTrue(ImportPlanner.plan(Prompt.parse(sample, "t"), bank.id, data, today).candidates.all { !it.include })
        assertEquals("מזון וסופרמרקט", data.category(ImportPlanner.guessCategory(null, "שופרסל דיל", TxKind.EXPENSE, data))?.name)
    }
}
