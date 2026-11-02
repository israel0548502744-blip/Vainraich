import Foundation
import FinanceCore

/// What kind of document the user uploaded, as identified by the extractor.
public enum DocumentKind: String, Codable, CaseIterable, Sendable {
    case bankStatement = "bank_statement"
    case creditCardStatement = "credit_card_statement"
    case balanceConfirmation = "balance_confirmation"
    case receipt
    case invoice
    case bitScreenshot = "bit_screenshot"
    case other

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? "other"
        self = DocumentKind(rawValue: raw.lowercased()) ?? .other
    }

    public var hebrewName: String {
        switch self {
        case .bankStatement: return "דף תנועות בנק"
        case .creditCardStatement: return "פירוט כרטיס אשראי"
        case .balanceConfirmation: return "אישור יתרה"
        case .receipt: return "קבלה"
        case .invoice: return "חשבונית"
        case .bitScreenshot: return "צילום מסך מביט"
        case .other: return "מסמך אחר"
        }
    }
}

public enum ExtractedDirection: String, Codable, Sendable {
    /// Money into the account.
    case moneyIn = "in"
    /// Money out of the account.
    case moneyOut = "out"

    public init(from decoder: Decoder) throws {
        let raw = ((try? decoder.singleValueContainer().decode(String.self)) ?? "out").lowercased()
        switch raw {
        case "in", "credit", "income", "זכות": self = .moneyIn
        default: self = .moneyOut
        }
    }
}

/// A balance figure found in the document (e.g. "יתרה ליום 31/10/2026: ₪5,000").
public struct ExtractedBalance: Codable, Hashable, Sendable {
    public var label: String
    @DecimalString public var amount: Decimal
    public var asOf: LocalDate?

    enum CodingKeys: String, CodingKey { case label, amount, asOf = "as_of" }

    public init(label: String, amount: Decimal, asOf: LocalDate?) {
        self.label = label
        self.amount = amount
        self.asOf = asOf
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = (try? c.decode(String.self, forKey: .label)) ?? "יתרה"
        _amount = try c.decode(DecimalString.self, forKey: .amount)
        asOf = c.lenientString(.asOf).flatMap(LocalDate.init(flexible:))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encode(_amount, forKey: .amount)
        try c.encodeIfPresent(asOf?.isoString, forKey: .asOf)
    }
}

/// One line the extractor found. Amount is always positive; `direction` gives the sign.
public struct ExtractedTransaction: Codable, Hashable, Sendable {
    public var date: LocalDate?
    public var description: String
    @DecimalString public var amount: Decimal
    public var direction: ExtractedDirection
    public var categoryHint: String?
    public var isCardBillPayment: Bool
    public var isBit: Bool
    public var counterparty: String?
    public var reference: String?

    enum CodingKeys: String, CodingKey {
        case date, description, amount, direction, counterparty, reference
        case categoryHint = "category_hint"
        case isCardBillPayment = "is_card_bill_payment"
        case isBit = "is_bit"
    }

    public init(date: LocalDate?, description: String, amount: Decimal, direction: ExtractedDirection, categoryHint: String? = nil,
                isCardBillPayment: Bool = false, isBit: Bool = false, counterparty: String? = nil, reference: String? = nil) {
        self.date = date
        self.description = description
        self.amount = amount
        self.direction = direction
        self.categoryHint = categoryHint
        self.isCardBillPayment = isCardBillPayment
        self.isBit = isBit
        self.counterparty = counterparty
        self.reference = reference
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.lenientString(.date).flatMap(LocalDate.init(flexible:))
        description = c.lenientString(.description)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let raw = try c.decode(DecimalString.self, forKey: .amount).wrappedValue
        var dir: ExtractedDirection? = c.lenientString(.direction) == nil ? nil : (try? c.decode(ExtractedDirection.self, forKey: .direction))
        // A negative amount means money out regardless of what the model wrote.
        if raw < 0 { dir = .moneyOut }
        direction = dir ?? .moneyOut
        _amount = DecimalString(wrappedValue: raw.magnitudeValue.rounded(scale: 2))
        categoryHint = c.lenientString(.categoryHint)
        isCardBillPayment = c.lenientBool(.isCardBillPayment)
        isBit = c.lenientBool(.isBit)
        counterparty = c.lenientString(.counterparty)
        reference = c.lenientString(.reference)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(date?.isoString, forKey: .date)
        try c.encode(description, forKey: .description)
        try c.encode(_amount, forKey: .amount)
        try c.encode(direction, forKey: .direction)
        try c.encodeIfPresent(categoryHint, forKey: .categoryHint)
        try c.encode(isCardBillPayment, forKey: .isCardBillPayment)
        try c.encode(isBit, forKey: .isBit)
        try c.encodeIfPresent(counterparty, forKey: .counterparty)
        try c.encodeIfPresent(reference, forKey: .reference)
    }
}

/// Structured result of reading one document.
public struct ExtractionResult: Codable, Hashable, Sendable {
    public var documentKind: DocumentKind
    public var institution: String?
    /// Only the last 4 digits of an account/card number, never the full number.
    public var accountHint: String?
    public var currency: String
    public var statementDate: LocalDate?
    public var balances: [ExtractedBalance]
    public var transactions: [ExtractedTransaction]
    public var warnings: [String]
    /// Which engine produced this (for the review screen).
    public var producedBy: String?

    enum CodingKeys: String, CodingKey {
        case institution, currency, balances, transactions, warnings
        case documentKind = "document_type"
        case accountHint = "account_hint"
        case statementDate = "statement_date"
        case producedBy = "produced_by"
    }

    public init(documentKind: DocumentKind, institution: String? = nil, accountHint: String? = nil, currency: String = "ILS",
                statementDate: LocalDate? = nil, balances: [ExtractedBalance] = [], transactions: [ExtractedTransaction] = [],
                warnings: [String] = [], producedBy: String? = nil) {
        self.documentKind = documentKind
        self.institution = institution
        self.accountHint = accountHint
        self.currency = currency
        self.statementDate = statementDate
        self.balances = balances
        self.transactions = transactions
        self.warnings = warnings
        self.producedBy = producedBy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        documentKind = c.lenientString(.documentKind).flatMap { DocumentKind(rawValue: $0.lowercased()) } ?? .other
        institution = c.lenientString(.institution)
        accountHint = c.lenientString(.accountHint).map(Redactor.lastFour)
        currency = (c.lenientString(.currency) ?? "ILS").uppercased()
        statementDate = c.lenientString(.statementDate).flatMap(LocalDate.init(flexible:))
        // Skip individual malformed rows instead of failing the whole document.
        balances = ((try? c.decodeIfPresent([Lossy<ExtractedBalance>].self, forKey: .balances)) ?? nil)?.compactMap(\.value) ?? []
        transactions = ((try? c.decodeIfPresent([Lossy<ExtractedTransaction>].self, forKey: .transactions)) ?? nil)?.compactMap(\.value) ?? []
        warnings = ((try? c.decodeIfPresent([String].self, forKey: .warnings)) ?? nil) ?? []
        producedBy = c.lenientString(.producedBy)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(documentKind, forKey: .documentKind)
        try c.encodeIfPresent(institution, forKey: .institution)
        try c.encodeIfPresent(accountHint, forKey: .accountHint)
        try c.encode(currency, forKey: .currency)
        try c.encodeIfPresent(statementDate?.isoString, forKey: .statementDate)
        try c.encode(balances, forKey: .balances)
        try c.encode(transactions, forKey: .transactions)
        try c.encode(warnings, forKey: .warnings)
        try c.encodeIfPresent(producedBy, forKey: .producedBy)
    }
}

/// Decodes an element if possible, otherwise yields nil instead of throwing.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

extension KeyedDecodingContainer {
    /// String value, or nil when missing, null, empty or of another type. Numbers are converted to text.
    func lenientString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty || t.lowercased() == "null" ? nil : t
        }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        return nil
    }

    func lenientBool(_ key: Key) -> Bool {
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let s = lenientString(key) { return ["true", "yes", "1", "כן"].contains(s.lowercased()) }
        return false
    }
}
