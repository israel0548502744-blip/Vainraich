import Foundation

/// The instructions and JSON schema shared by every AI provider.
public enum ExtractionPrompt {
    public static let system = """
    You extract financial data from Israeli personal-finance documents: bank statements (דף תנועות / עובר ושב), \
    credit-card statements (פירוט חיובים), balance confirmations (אישור יתרה), receipts, invoices and Bit app screenshots. \
    Documents are usually in Hebrew and amounts are in Israeli New Shekels (₪, ILS) unless stated otherwise.

    Rules:
    - Output ONLY one JSON object that follows the schema. No prose, no markdown fences.
    - Never invent data. If a value is not clearly visible, use null or omit the row and add a short note to "warnings".
    - Dates are day-first in Israel (15/12/26 = 15 December 2026). Output dates as YYYY-MM-DD.
    - "amount" is always a positive decimal string with a dot as decimal separator and no thousands separators, e.g. "1234.50".
    - "direction": "in" when money entered the account (זכות, הפקדה, משכורת, קבלה מ…), "out" when it left (חובה, משיכה, חיוב, רכישה).
      For a credit-card statement, every purchase/charge is "out" and a refund (זיכוי) is "in".
    - "is_card_bill_payment": true for bank lines that pay a credit-card company (e.g. "ויזה", "ישראכרט", "מקס", "כאל", "אמריקן אקספרס", "חיוב כרטיס").
    - "is_bit": true for Bit transfers (e.g. "ביט", "BIT", "העברה בביט").
    - "category_hint": a short Hebrew category such as מזון, מסעדות, תחבורה, דיור, חשבונות, תקשורת, בריאות, קניות, חינוך, פנאי, עמלות, משכורת, החזר, or null.
    - "balances": every stated balance (יתרה, יתרה זמינה, יתרה ליום, יתרת חוב) with its date if shown. A debt balance on a card is positive.
    - "account_hint": ONLY the last 4 digits of the account or card number, never the full number. Never output ID numbers (ת.ז.).
    - Skip summary/total rows; list each transaction once.
    - "document_type": one of bank_statement, credit_card_statement, balance_confirmation, receipt, invoice, bit_screenshot, other.
    """

    public static let user = "Extract the data from this document according to the rules. Return only the JSON object."

    /// JSON Schema (draft 2020-12 subset accepted by structured-output APIs).
    public static let jsonSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["document_type", "institution", "account_hint", "currency", "statement_date", "balances", "transactions", "warnings"],
        "properties": [
            "document_type": ["type": "string", "enum": ["bank_statement", "credit_card_statement", "balance_confirmation", "receipt", "invoice", "bit_screenshot", "other"]],
            "institution": ["type": ["string", "null"]],
            "account_hint": ["type": ["string", "null"]],
            "currency": ["type": "string"],
            "statement_date": ["type": ["string", "null"]],
            "balances": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["label", "amount", "as_of"],
                    "properties": [
                        "label": ["type": "string"],
                        "amount": ["type": "string"],
                        "as_of": ["type": ["string", "null"]],
                    ],
                ],
            ],
            "transactions": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["date", "description", "amount", "direction", "category_hint", "is_card_bill_payment", "is_bit", "counterparty", "reference"],
                    "properties": [
                        "date": ["type": ["string", "null"]],
                        "description": ["type": "string"],
                        "amount": ["type": "string"],
                        "direction": ["type": "string", "enum": ["in", "out"]],
                        "category_hint": ["type": ["string", "null"]],
                        "is_card_bill_payment": ["type": "boolean"],
                        "is_bit": ["type": "boolean"],
                        "counterparty": ["type": ["string", "null"]],
                        "reference": ["type": ["string", "null"]],
                    ],
                ],
            ],
            "warnings": ["type": "array", "items": ["type": "string"]],
        ],
    ]

    /// Human-readable schema appended to prompts for providers without native schema support.
    public static let schemaDescription = """
    JSON shape:
    {"document_type": "...", "institution": string|null, "account_hint": "1234"|null, "currency": "ILS", "statement_date": "YYYY-MM-DD"|null,
     "balances": [{"label": string, "amount": "0.00", "as_of": "YYYY-MM-DD"|null}],
     "transactions": [{"date": "YYYY-MM-DD"|null, "description": string, "amount": "0.00", "direction": "in"|"out",
                       "category_hint": string|null, "is_card_bill_payment": bool, "is_bit": bool, "counterparty": string|null, "reference": string|null}],
     "warnings": [string]}
    """

    /// Extracts the first top-level JSON object from model text (tolerates ```json fences and prose around it).
    public static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var i = start
        while i < text.endIndex {
            let ch = text[i]
            if inString {
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
            } else {
                if ch == "\"" { inString = true }
                if ch == "{" { depth += 1 }
                if ch == "}" {
                    depth -= 1
                    if depth == 0 { return String(text[start...i]) }
                }
            }
            i = text.index(after: i)
        }
        return nil
    }

    /// Parses model output into an `ExtractionResult`.
    public static func parse(_ text: String, producedBy: String) throws -> ExtractionResult {
        guard let json = extractJSONObject(from: text), let data = json.data(using: .utf8) else {
            throw AIProviderError.invalidResponse("לא נמצא JSON בתשובה")
        }
        do {
            var result = try JSONDecoder().decode(ExtractionResult.self, from: data)
            result.producedBy = producedBy
            return result
        } catch {
            throw AIProviderError.invalidResponse("התשובה לא תאמה למבנה הצפוי")
        }
    }
}
