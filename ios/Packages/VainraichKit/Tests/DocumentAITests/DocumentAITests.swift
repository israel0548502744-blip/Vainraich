import XCTest
@testable import DocumentAI
@testable import FinanceCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Records requests and replays a canned response — no network in tests.
final class MockHTTP: HTTPClient, @unchecked Sendable {
    var lastRequest: URLRequest?
    let status: Int
    let body: String
    init(status: Int = 200, body: String) { self.status = status; self.body = body }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "30"])!)
    }
}

let sampleJSON = """
{"document_type":"bank_statement","institution":"בנק לאומי","account_hint":"12-345-678901","currency":"ils","statement_date":"2026-10-31",
 "balances":[{"label":"יתרה ליום 31/10/2026","amount":"5,000.00","as_of":"31/10/2026"}],
 "transactions":[
  {"date":"2026-10-01","description":"משכורת","amount":"9400.00","direction":"in","category_hint":"משכורת","is_card_bill_payment":false,"is_bit":false,"counterparty":null,"reference":"123"},
  {"date":"10/10/2026","description":"ויזה כאל","amount":"1,670.50","direction":"out","category_hint":null,"is_card_bill_payment":true,"is_bit":false,"counterparty":null,"reference":null},
  {"date":"2026-10-12","description":"העברה בביט לנועה","amount":-120,"direction":"in","category_hint":null,"is_card_bill_payment":false,"is_bit":true},
  {"date":"bad","description":"שורה שבורה","amount":"not a number","direction":"out"}
 ],
 "warnings":[]}
"""

final class ExtractionParsingTests: XCTestCase {
    func testParsesLenientJSONWithFences() throws {
        let r = try ExtractionPrompt.parse("Here you go:\n```json\n\(sampleJSON)\n```", producedBy: "test")
        XCTAssertEqual(r.documentKind, .bankStatement)
        XCTAssertEqual(r.currency, "ILS")
        XCTAssertEqual(r.accountHint, "****8901", "Full account numbers are never kept")
        XCTAssertEqual(r.balances.first?.amount, 5000)
        XCTAssertEqual(r.balances.first?.asOf, LocalDate(year: 2026, month: 10, day: 31))
        XCTAssertEqual(r.transactions.count, 3, "Malformed row skipped, not fatal")
        XCTAssertEqual(r.transactions[1].amount, Decimal(string: "1670.50"))
        XCTAssertEqual(r.transactions[1].date, LocalDate(year: 2026, month: 10, day: 10))
        XCTAssertEqual(r.transactions[2].direction, .moneyOut, "Negative amount forces money out")
        XCTAssertEqual(r.transactions[2].amount, 120)
        XCTAssertEqual(r.producedBy, "test")
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try ExtractionPrompt.parse("sorry, I cannot", producedBy: "x"))
    }
}

final class ProviderRequestTests: XCTestCase {
    func testGeminiRequestAndResponse() async throws {
        let response = #"{"candidates":[{"content":{"parts":[{"text":"\#(sampleJSON.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " "))"}]}}]}"#
        let http = MockHTTP(body: response)
        let p = GeminiProvider(apiKey: "KEY", http: http)
        let r = try await p.extract(.pdf(Data("pdf".utf8)))
        XCTAssertEqual(r.transactions.count, 3)
        let req = try XCTUnwrap(http.lastRequest)
        XCTAssertEqual(req.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-goog-api-key"), "KEY")
        XCTAssertNil(req.url?.query, "Key is sent in a header, not the URL")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        let parts = ((body["contents"] as! [[String: Any]])[0]["parts"] as! [[String: Any]])
        XCTAssertEqual((parts[0]["inline_data"] as! [String: Any])["mime_type"] as? String, "application/pdf")
    }

    func testGeminiMissingKey() async {
        do {
            _ = try await GeminiProvider(apiKey: "", http: MockHTTP(body: "{}")).extract(.text("x"))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? AIProviderError, .missingAPIKey)
        }
    }

    func testRateLimitMapped() async {
        let p = GeminiProvider(apiKey: "k", http: MockHTTP(status: 429, body: #"{"error":{"message":"quota"}}"#))
        do {
            _ = try await p.extract(.text("x"))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? AIProviderError, .rateLimited(retryAfterSeconds: 30))
        }
    }

    func testOpenAICompatibleRequest() async throws {
        let escaped = sampleJSON.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ")
        let http = MockHTTP(body: #"{"choices":[{"message":{"role":"assistant","content":"\#(escaped)"}}]}"#)
        let p = OpenAICompatibleProvider(name: "OpenRouter", apiKey: "sk", model: "some/model:free", baseURL: OpenAICompatibleProvider.Preset.openRouter.baseURL, http: http)
        let r = try await p.extract(.image(Data([0xFF, 0xD8]), mimeType: "image/jpeg"))
        XCTAssertEqual(r.transactions.count, 3)
        let req = try XCTUnwrap(http.lastRequest)
        XCTAssertEqual(req.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "some/model:free")
        XCTAssertNotNil(body["response_format"])
    }

    func testOpenAICompatibleRejectsPDF() async {
        let p = OpenAICompatibleProvider(name: "x", apiKey: "k", model: "m", baseURL: URL(string: "https://x.test/v1")!, http: MockHTTP(body: "{}"))
        do {
            _ = try await p.extract(.pdf(Data()))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? AIProviderError, .unsupportedInput("pdf"))
        }
    }

    func testAnthropicRequestShape() async throws {
        let escaped = sampleJSON.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ")
        let http = MockHTTP(body: #"{"content":[{"type":"text","text":"\#(escaped)"}],"stop_reason":"end_turn"}"#)
        let p = AnthropicProvider(apiKey: "ak", http: http)
        _ = try await p.extract(.pdf(Data("%PDF".utf8)))
        let req = try XCTUnwrap(http.lastRequest)
        XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "ak")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertNotNil((body["output_config"] as? [String: Any])?["format"])
        let content = ((body["messages"] as! [[String: Any]])[0]["content"] as! [[String: Any]])
        XCTAssertEqual(content[0]["type"] as? String, "document")
    }

    func testAnthropicRefusal() {
        let data = Data(#"{"content":[],"stop_reason":"refusal","stop_details":{"type":"refusal","explanation":"nope"}}"#.utf8)
        XCTAssertThrowsError(try AnthropicProvider.parseResponse(data)) { XCTAssertEqual($0 as? AIProviderError, .refused("nope")) }
    }
}

final class RedactorTests: XCTestCase {
    func testRedactsIdentifiersButNotAmountsOrDates() {
        let text = "ת.ז. 123456782 חשבון 12-345-678901 כרטיס 4580 1234 5678 9012 סכום 1,234.56 תאריך 15/10/2026 mail a.b@x.com"
        let r = Redactor.redact(text)
        XCTAssertFalse(r.contains("123456782"))
        XCTAssertTrue(r.contains("****6782"))
        XCTAssertTrue(r.contains("****8901"))
        XCTAssertTrue(r.contains("****9012"))
        XCTAssertTrue(r.contains("1,234.56"))
        XCTAssertTrue(r.contains("15/10/2026"))
        XCTAssertFalse(r.contains("a.b@x.com"))
    }
}

final class RuleBasedParserTests: XCTestCase {
    func testParsesBankStatementText() async throws {
        let text = """
        בנק לדוגמה - תנועות בחשבון
        01/10/2026 משכורת 9,400.00 12,400.00
        02/10/2026 שכר דירה 3,800.00 8,600.00
        10/10/2026 ויזה כאל חיוב 1,670.50 6,929.50
        12/10/2026 העברה בביט 120.00 6,809.50
        יתרה ליום 31/10/2026 6,809.50
        """
        let r = try await RuleBasedExtractor().extract(.text(text))
        XCTAssertEqual(r.transactions.count, 4)
        XCTAssertEqual(r.transactions[0].direction, .moneyIn)
        XCTAssertEqual(r.transactions[1].direction, .moneyOut)
        XCTAssertEqual(r.transactions[1].amount, 3800)
        XCTAssertTrue(r.transactions[2].isCardBillPayment)
        XCTAssertTrue(r.transactions[3].isBit)
        XCTAssertEqual(r.balances.first?.amount, Decimal(string: "6809.50"))
        XCTAssertFalse(r.warnings.isEmpty, "Always asks the user to review")
    }
}

final class ImportPlannerTests: XCTestCase {
    let today = LocalDate(year: 2026, month: 11, day: 2)

    func testPlanMapsCardBillToTransferAndDetectsDuplicates() throws {
        let bank = Account(name: "עו״ש", type: .bank, openingBalance: 0, openingDate: LocalDate(year: 2026, month: 9, day: 1))
        let card = Account(name: "ויזה", type: .creditCard, billingDay: 10, paymentAccountID: bank.id)
        let bit = Account(name: "ביט", type: .bit)
        let existingSalary = FinanceTransaction(kind: .income, amount: 9400, accountID: bank.id, title: "משכורת אוקטובר", date: LocalDate(year: 2026, month: 10, day: 1))
        let bitManual = FinanceTransaction(kind: .expense, amount: 120, accountID: bit.id, title: "ביט לנועה", date: LocalDate(year: 2026, month: 10, day: 11))
        let data = FinanceData(accounts: [bank, card, bit], transactions: [existingSalary, bitManual])

        let result = try ExtractionPrompt.parse(sampleJSON, producedBy: "t")
        let plan = ImportPlanner.plan(result: result, targetAccountID: bank.id, data: data, today: today)
        XCTAssertEqual(plan.candidates.count, 3)

        let salary = plan.candidates[0]
        XCTAssertEqual(salary.duplicateOf, existingSalary.id)
        XCTAssertFalse(salary.include, "Duplicates are unselected by default")

        let bill = plan.candidates[1]
        XCTAssertEqual(bill.transaction.kind, .transfer)
        XCTAssertEqual(bill.transaction.counterAccountID, card.id)
        XCTAssertNil(bill.transaction.categoryID)
        XCTAssertTrue(bill.include)

        let bitRow = plan.candidates[2]
        XCTAssertEqual(bitRow.duplicateOf, bitManual.id)
        XCTAssertEqual(bitRow.transaction.paymentMethod, .bit)

        for c in plan.candidates { XCTAssertNoThrow(try c.transaction.validate(in: data)) }

        // Balance check: app balance after import (9400 already there, −1670.50 selected) vs document 5,000.
        let s = try XCTUnwrap(plan.balanceSuggestions.first)
        XCTAssertEqual(s.appBalance, Decimal(string: "7729.50"))
        let adj = try XCTUnwrap(ImportPlanner.adjustment(for: s, accountID: bank.id, today: today))
        XCTAssertEqual(adj.kind, .adjustment)
        XCTAssertTrue(adj.adjustmentIsNegative)
        XCTAssertEqual(adj.amount, Decimal(string: "2729.50"))
    }

    func testReimportIsDetected() throws {
        let bank = Account(name: "b", type: .bank)
        var data = FinanceData(accounts: [bank])
        let result = try ExtractionPrompt.parse(sampleJSON, producedBy: "t")
        let first = ImportPlanner.plan(result: result, targetAccountID: bank.id, data: data, today: today)
        data.transactions += first.candidates.filter(\.include).map(\.transaction)
        let second = ImportPlanner.plan(result: result, targetAccountID: bank.id, data: data, today: today)
        XCTAssertTrue(second.candidates.allSatisfy { !$0.include && $0.duplicateOf != nil })
    }

    func testCategoryGuess() {
        let data = FinanceData()
        let id = ImportPlanner.guessCategory(hint: nil, description: "שופרסל דיל ראשון", kind: .expense, in: data)
        XCTAssertEqual(data.category(id)?.name, "מזון וסופרמרקט")
        let fuel = ImportPlanner.guessCategory(hint: nil, description: "פז חברת נפט", kind: .expense, in: data)
        XCTAssertEqual(data.category(fuel)?.name, "תחבורה ורכב")
    }

    func testCardStatementDebtSign() throws {
        let card = Account(name: "ויזה", type: .creditCard)
        let data = FinanceData(accounts: [card])
        let result = ExtractionResult(documentKind: .creditCardStatement, balances: [ExtractedBalance(label: "יתרת חוב", amount: 300, asOf: nil)],
                                      transactions: [ExtractedTransaction(date: today, description: "סופר", amount: 300, direction: .moneyOut)])
        let plan = ImportPlanner.plan(result: result, targetAccountID: card.id, data: data, today: today)
        XCTAssertEqual(plan.candidates.first?.transaction.kind, .expense)
        XCTAssertEqual(plan.candidates.first?.transaction.paymentMethod, .creditCard)
        XCTAssertEqual(plan.balanceSuggestions.first?.amount, -300)
        XCTAssertEqual(plan.balanceSuggestions.first?.difference, 0, "Document debt matches the app after import")
    }
}
