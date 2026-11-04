package com.vainraich.core

import com.vainraich.core.ai.*
import kotlinx.serialization.json.*
import org.junit.Test
import java.time.LocalDate
import kotlin.test.*

private class Recorder(val body: String) : HttpClient {
    var last: HttpRequest? = null
    override fun send(r: HttpRequest): HttpResponse { last = r; return HttpResponse(200, body, emptyMap()) }
}

class AssistantTest {
    private val today = LocalDate.of(2026, 11, 4)

    @Test fun parsesActionsAndStripsTags() {
        val raw = """
            בסדר! הנה מה שאני מציע לרשום:
            <action>{"type":"expense","amount":"50","title":"דלק","date":"2026-11-04","category":"תחבורה ורכב"}</action>
            <action>{"type":"add_to_debt","person":"דוד","amount":80,"reason":"הדפסה נוספת"}</action>
            <action>{"type":"new_debt","direction":"i_owe","person":"משה","amount":"1,200","title":"הלוואה","due":"15/12/2026"}</action>
            <action>{"type":"debt_payment","person":"דוד","amount":120}</action>
            <action>{"type":"event","title":"אירוע חתונה","date":"2026-12-01","expected_income":2500}</action>
            <action>{"type":"expense","amount":0,"title":"bad"}</action>
            <action>{not json}</action>
        """.trimIndent()
        val r = Assistant.parse(raw)
        assertEquals("בסדר! הנה מה שאני מציע לרשום:", r.text)
        assertEquals(5, r.actions.size)
        val tx = r.actions[0] as ProposedAction.AddTransaction
        assertEquals(TxKind.EXPENSE, tx.kind); assertEquals(money(50), tx.amount); assertEquals(today, tx.date)
        assertEquals(money(80), (r.actions[1] as ProposedAction.AddCharge).amount)
        val d = r.actions[2] as ProposedAction.AddDebt
        assertEquals(DebtDirection.PAYABLE, d.direction); assertEquals(money(1200), d.amount); assertEquals(LocalDate.of(2026, 12, 15), d.dueDate)
        assertNull((r.actions[3] as ProposedAction.DebtPayment).date)
        assertEquals(money(2500), (r.actions[4] as ProposedAction.AddEvent).expectedIncome)
    }

    @Test fun plainAnswerHasNoActions() {
        val r = Assistant.parse("יש לך 27,798 ₪ זמינים.")
        assertTrue(r.actions.isEmpty()); assertEquals("יש לך 27,798 ₪ זמינים.", r.text)
    }

    @Test fun contextHasTotalsDebtsAndDemoFlag() {
        val data = DemoData.make(today)
        val c = Assistant.context(data, today)
        assertTrue(c.contains("DEMO DATA"))
        assertTrue(c.contains("Available now"))
        assertTrue(c.contains("Open debts"))
        assertTrue(c.contains("אירוע יום הולדת משפחת לוי"))
        assertTrue(c.lines().count { it.contains(" | ") } < 200, "context should stay small")
        assertFalse(Assistant.context(data.copy(isDemo = false), today).contains("DEMO DATA"))
        assertTrue(Assistant.systemPrompt(data, today).contains("<action>"))
    }

    @Test fun resolvesNamesAndDebts() {
        val david = Contact(name = "ג'יבלי דוד")
        val acc = Account(name = "עו\"ש לאומי", type = AccountType.BANK)
        val debt = Debt(direction = DebtDirection.RECEIVABLE, contactId = david.id, title = "הדפסה", originalAmount = money(120), issuedDate = today)
        val data = FinanceData(accounts = listOf(acc), contacts = listOf(david), debts = listOf(debt))
        assertEquals(david.id, Assistant.findContact(data, "דוד")?.id)
        assertEquals(debt.id, Assistant.findOpenDebt(data, "דוד", today)?.id)
        assertNull(Assistant.findOpenDebt(data, "דוד", today, DebtDirection.PAYABLE))
        assertNull(Assistant.findContact(data, "משה"))
        assertEquals(acc.id, Assistant.findAccount(data, "לאומי")?.id)
        assertEquals("e03", Assistant.findCategory(data, "תחבורה ורכב", TxKind.EXPENSE)?.id)
        assertEquals("i02", Assistant.findCategory(data, "עבודה עצמאית", TxKind.INCOME)?.id)

        val bigger = debt.withCharge(money(80), "הדפסה נוספת", today)
        assertEquals(money(200), bigger.originalAmount)
        assertTrue(bigger.notes.contains("04/11/2026"))
    }

    @Test fun chatRequestsPerProvider() {
        val history = listOf(ChatMessage(ChatRole.ASSISTANT, "שלום!"), ChatMessage(ChatRole.USER, "כמה יש לי?"), ChatMessage(ChatRole.ASSISTANT, "100"), ChatMessage(ChatRole.USER, "ומה צפוי?"))

        val g = Recorder("""{"candidates":[{"content":{"parts":[{"text":"שלום"}]}}]}""")
        assertEquals("שלום", GeminiProvider("k", http = g).chat("SYS", history))
        val gb = Json.parseToJsonElement(g.last!!.body!!).jsonObject
        val contents = gb["contents"]!!.jsonArray
        assertEquals(3, contents.size, "leading assistant greeting is dropped")
        assertEquals("user", contents[0].jsonObject["role"]!!.jsonPrimitive.content)
        assertEquals("model", contents[1].jsonObject["role"]!!.jsonPrimitive.content)
        assertTrue(g.last!!.url.endsWith("models/gemini-flash-latest:generateContent"))

        val o = Recorder("""{"choices":[{"message":{"content":"היי"}}]}""")
        assertEquals("היי", OpenAICompatibleProvider("OpenRouter", "k", "m:free", "https://x/v1", http = o).chat("SYS", history))
        val ob = Json.parseToJsonElement(o.last!!.body!!).jsonObject
        assertEquals("system", ob["messages"]!!.jsonArray[0].jsonObject["role"]!!.jsonPrimitive.content)
        assertNull(ob["response_format"])

        val a = Recorder("""{"content":[{"type":"text","text":"אהלן"}],"stop_reason":"end_turn"}""")
        assertEquals("אהלן", AnthropicProvider("k", http = a).chat("SYS", history))
        val ab = Json.parseToJsonElement(a.last!!.body!!).jsonObject
        assertEquals("SYS", ab["system"]!!.jsonPrimitive.content)
        assertNull(ab["output_config"])

        assertFailsWith<AIError> { GeminiProvider("", http = g).chat("s", history) }
    }
}
