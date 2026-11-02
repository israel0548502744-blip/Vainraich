import Foundation
import FinanceCore

/// Free, offline extractor that works on text (from on-device OCR or a PDF's text layer) without any AI.
/// Less accurate than an AI model — every result is marked for review.
public struct RuleBasedExtractor: DocumentExtractor {
    public init() {}

    public var displayName: String { "זיהוי בסיסי במכשיר (ללא בינה מלאכותית)" }
    public var capabilities: ProviderCapabilities { ProviderCapabilities(acceptsPDF: false, acceptsImages: false, runsOnDevice: true) }

    public func extract(_ input: DocumentInput) async throws -> ExtractionResult {
        guard case .text(let text) = input else { throw AIProviderError.unsupportedInput(input.kindDescription) }
        return RuleBasedExtractor.parse(text)
    }

    static let datePattern = #"(?<!\d)(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})(?!\d)"#
    /// Money with exactly two decimals (statement style), optional thousands separators and sign.
    static let amountPattern = #"(?<![\d/.])-?\d{1,3}(?:,\d{3})*\.\d{2}-?(?![\d/])|(?<![\d/.])-?\d+\.\d{2}-?(?![\d/])"#

    static let incomeWords = ["משכורת", "זיכוי", "הפקדה", "העברה מ", "קבלה", "החזר", "ריבית זכות", "מענק", "קצבה"]
    static let cardWords = ["ויזה", "visa", "ישראכרט", "isracard", "מקס", "max it", "כאל", "cal ", "אמריקן", "american express", "דיינרס", "חיוב כרטיס", "כרטיסי אשראי"]
    static let bitWords = ["ביט", "bit"]

    public static func parse(_ text: String) -> ExtractionResult {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let dateRe = try! NSRegularExpression(pattern: datePattern)
        let amountRe = try! NSRegularExpression(pattern: amountPattern)

        var rows: [ExtractedTransaction] = []
        var balances: [ExtractedBalance] = []
        var previousBalance: Decimal?
        let lowerAll = text.lowercased()
        let isCardStatement = lowerAll.contains("פירוט") && cardWords.contains { lowerAll.contains($0) }

        for line in lines {
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            let dates = dateRe.matches(in: line, range: full).compactMap { LocalDate(israeli: ns.substring(with: $0.range)) }
            let amountMatches = amountRe.matches(in: line, range: full)
            let amounts = amountMatches.compactMap { Decimal.parseMoney(ns.substring(with: $0.range)) }
            let lower = line.lowercased()

            if lower.contains("יתרה") && !amounts.isEmpty && dates.count <= 1 && !lower.contains("ש\"ח ל") {
                balances.append(ExtractedBalance(label: String(line.prefix(40)), amount: amounts.last!, asOf: dates.first))
                continue
            }
            guard let date = dates.first, !amounts.isEmpty else { continue }

            // Description = the line without dates and numbers.
            var desc = line
            for m in (dateRe.matches(in: line, range: full) + amountMatches).sorted(by: { $0.range.location > $1.range.location }) {
                desc = (desc as NSString).replacingCharacters(in: m.range, with: " ")
            }
            desc = desc.replacingOccurrences(of: "₪", with: " ")
                .components(separatedBy: .whitespaces).filter { !$0.isEmpty && !$0.allSatisfy { $0.isNumber || $0 == "-" } }
                .joined(separator: " ")

            var amount: Decimal
            var direction: ExtractedDirection
            if amounts.count >= 2 {
                // Typical bank row: … amount … running balance.
                amount = amounts[amounts.count - 2]
                let balance = amounts.last!
                if let prev = previousBalance {
                    direction = balance >= prev ? .moneyIn : .moneyOut
                } else {
                    direction = amount < 0 ? .moneyOut : (incomeWords.contains { lower.contains($0) } ? .moneyIn : .moneyOut)
                }
                previousBalance = balance
            } else {
                amount = amounts[0]
                direction = amount < 0 ? .moneyOut : (incomeWords.contains { lower.contains($0) } && !isCardStatement ? .moneyIn : .moneyOut)
            }
            if isCardStatement && lower.contains("זיכוי") { direction = .moneyIn }
            amount = amount.magnitudeValue
            guard amount > 0 else { continue }

            rows.append(ExtractedTransaction(
                date: date, description: desc.isEmpty ? "תנועה" : desc, amount: amount, direction: direction,
                isCardBillPayment: !isCardStatement && direction == .moneyOut && cardWords.contains { lower.contains($0) },
                isBit: bitWords.contains { lower.range(of: "\\b\($0)\\b", options: .regularExpression) != nil || lower.contains($0 + " ") }
            ))
        }

        var warnings = ["הנתונים זוהו ללא בינה מלאכותית — כדאי לעבור על כל שורה לפני האישור."]
        if rows.isEmpty && balances.isEmpty { warnings.append("לא זוהו תנועות או יתרות בטקסט.") }
        let kind: DocumentKind = isCardStatement ? .creditCardStatement : (rows.isEmpty && !balances.isEmpty ? .balanceConfirmation : (rows.isEmpty ? .other : .bankStatement))
        return ExtractionResult(documentKind: kind, currency: "ILS", balances: balances, transactions: rows, warnings: warnings,
                                producedBy: "זיהוי בסיסי במכשיר")
    }
}
