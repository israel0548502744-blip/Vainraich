import Foundation
import FinanceCore

/// One proposed row on the review screen. Nothing is saved until the user approves.
public struct ImportCandidate: Identifiable, Hashable, Sendable {
    public var id: UUID { transaction.id }
    public var include: Bool
    public var transaction: FinanceTransaction
    /// An existing transaction this row seems to repeat.
    public var duplicateOf: UUID?
    /// Short Hebrew explanation shown under the row.
    public var note: String?
    public var source: ExtractedTransaction
}

/// "The document says the balance is X, the app says Y".
public struct BalanceSuggestion: Identifiable, Hashable, Sendable {
    public var id: String { label + amount.plainString }
    public var label: String
    /// Balance in the app's sign convention (card debt is negative).
    public var amount: Decimal
    public var asOf: LocalDate?
    /// App balance after importing the selected rows.
    public var appBalance: Decimal
    public var difference: Decimal { amount - appBalance }
}

public struct ImportPlan: Sendable {
    public var targetAccountID: UUID
    public var candidates: [ImportCandidate]
    public var balanceSuggestions: [BalanceSuggestion]
    public var warnings: [String]
    public var result: ExtractionResult
}

public enum ImportPlanner {
    /// Keyword → default category name fragments.
    static let categoryKeywords: [(keywords: [String], category: String)] = [
        (["מזון", "סופר", "שופרסל", "רמי לוי", "יוחננוף", "ויקטורי", "אושר עד", "מגה", "טיב טעם"], "מזון"),
        (["מסעד", "קפה", "וולט", "wolt", "תן ביס", "מקדונלד", "פיצה", "בורגר"], "מסעדות"),
        (["תחבורה", "דלק", "פז", "סונול", "דור אלון", "דלק ", "רב קו", "רכבת", "חניה", "פנגו", "סלופארק", "gett", "מונית"], "תחבורה"),
        (["דיור", "שכר דירה", "שכירות", "ארנונה", "ועד בית", "משכנתא"], "דיור"),
        (["חשבונות", "חשמל", "מים", "גז", "תאגיד"], "חשבונות"),
        (["תקשורת", "סלקום", "פרטנר", "הוט", "בזק", "גולן", "פלאפון", "yes", "נטפליקס", "netflix", "spotify", "apple.com", "icloud"], "תקשורת"),
        (["בריאות", "מכבי", "כללית", "מאוחדת", "לאומית", "סופר-פארם", "סופר פארם", "בית מרקחת"], "בריאות"),
        (["קניות", "זארה", "h&m", "קסטרו", "עלי אקספרס", "aliexpress", "amazon", "אמזון", "איקאה"], "קניות"),
        (["חינוך", "גן", "בית ספר", "חוג", "אוניברסיט"], "חינוך"),
        (["פנאי", "קולנוע", "סינמה", "הופעה", "חדר כושר"], "פנאי"),
        (["עמלה", "עמלות", "ריבית", "דמי ניהול"], "עמלות"),
        (["משכורת", "שכר"], "משכורת"),
        (["החזר", "ביטוח לאומי", "קצבה", "מס הכנסה"], "קצבאות"),
    ]

    public static func guessCategory(hint: String?, description: String, kind: TransactionKind, in data: FinanceData) -> UUID? {
        let wanted: FinanceCategory.Kind = kind == .income ? .income : .expense
        let cats = data.categories.filter { $0.kind == wanted && !$0.isArchived }
        let text = ((hint ?? "") + " " + description).lowercased()
        // Exact user-category name mention first.
        if let c = cats.first(where: { text.contains($0.name.lowercased()) }) { return c.id }
        for (keywords, fragment) in categoryKeywords where keywords.contains(where: { text.contains($0) }) {
            if let c = cats.first(where: { $0.name.contains(fragment) }) { return c.id }
        }
        return nil
    }

    public static func externalID(for row: ExtractedTransaction, accountID: UUID) -> String {
        let desc = row.description.lowercased().filter { !$0.isWhitespace }
        return "doc:\(accountID.uuidString.prefix(8)):\(row.date?.isoString ?? "-"):\(row.amount.plainString):\(row.direction.rawValue):\(desc.prefix(40))"
    }

    public static func plan(result: ExtractionResult, targetAccountID: UUID, data: FinanceData, today: LocalDate) -> ImportPlan {
        var warnings = result.warnings
        guard let target = data.account(targetAccountID) else {
            return ImportPlan(targetAccountID: targetAccountID, candidates: [], balanceSuggestions: [], warnings: ["החשבון שנבחר לא נמצא"], result: result)
        }
        if result.currency != target.currency {
            warnings.append("המסמך במטבע \(result.currency) והחשבון במטבע \(target.currency) — בדוק את הסכומים.")
        }
        let isCard = target.type == .creditCard
        let cardForBills = data.accounts.first { $0.type == .creditCard && $0.isActive && $0.paymentAccountID == target.id }
            ?? data.accounts.first { $0.type == .creditCard && $0.isActive }
        let bitAccountIDs = Set(data.accounts.filter { $0.type == .bit }.map(\.id))
        let existingExternal = Set(data.transactions.compactMap(\.externalID))

        var candidates: [ImportCandidate] = []
        var seenInDocument = Set<String>()

        for row in result.transactions where row.amount > 0 {
            var note: String?
            let date = row.date ?? result.statementDate ?? today
            if row.date == nil { note = "לא זוהה תאריך — נקבע \(date)" }

            var kind: TransactionKind = row.direction == .moneyIn ? .income : .expense
            var counter: UUID?
            var method: PaymentMethod? = isCard ? .creditCard : nil
            if !isCard && row.isCardBillPayment && row.direction == .moneyOut {
                if let card = cardForBills {
                    kind = .transfer
                    counter = card.id
                    note = "חיוב כרטיס אשראי — נרשם כהעברה ל\(card.name) כדי שלא תיספר הוצאה כפולה"
                } else {
                    note = "נראה כמו חיוב כרטיס אשראי. כדאי להוסיף את הכרטיס כחשבון כדי למנוע ספירה כפולה."
                }
            }
            if row.isBit { method = .bit }

            let ext = externalID(for: row, accountID: target.id)
            var tx = FinanceTransaction(
                kind: kind, status: date > today ? .pending : .completed, amount: row.amount, accountID: target.id,
                counterAccountID: counter, categoryID: kind == .transfer ? nil : guessCategory(hint: row.categoryHint, description: row.description, kind: kind, in: data),
                title: row.description.isEmpty ? (kind == .income ? "הכנסה" : "הוצאה") : row.description, date: date,
                paymentMethod: method, notes: row.reference.map { "אסמכתא: \($0)" } ?? "", source: .documentImport, externalID: ext
            )

            // Duplicate detection.
            var duplicate: UUID?
            if existingExternal.contains(ext) {
                duplicate = data.transactions.first { $0.externalID == ext }?.id
                note = "כבר יובא בעבר"
            } else if let match = data.transactions.first(where: { t in
                t.status != .cancelled && t.amount == row.amount && abs(t.date.days(until: date)) <= 1 &&
                (t.accountID == target.id || t.counterAccountID == target.id) &&
                Ledger.effect(of: t, on: target.id).isNegativeValue == (row.direction == .moneyOut)
            }) {
                duplicate = match.id
                note = "דומה לתנועה קיימת: \(match.title) (\(match.date))"
            } else if row.isBit, let match = data.transactions.first(where: { t in
                bitAccountIDs.contains(t.accountID) && t.amount == row.amount && abs(t.date.days(until: date)) <= 3 && t.status != .cancelled
            }) {
                duplicate = match.id
                tx.matchedTransactionID = match.id
                note = "נראה שכבר נרשם בביט: \(match.title)"
            }
            if seenInDocument.contains(ext) {
                note = "מופיע פעמיים במסמך — בדוק אם זו אותה תנועה"
            }
            seenInDocument.insert(ext)

            candidates.append(ImportCandidate(include: duplicate == nil, transaction: tx, duplicateOf: duplicate, note: note, source: row))
        }

        let current = Ledger.balance(of: target, transactions: data.transactions)
        let selectedEffect = candidates.filter(\.include).reduce(Decimal(0)) { $0 + Ledger.effect(of: $1.transaction, on: target.id) }
        let suggestions = result.balances.map { b -> BalanceSuggestion in
            // Card statements state the debt as a positive number; the app stores card debt as negative.
            let amount = isCard && b.amount > 0 ? -b.amount : b.amount
            return BalanceSuggestion(label: b.label, amount: amount, asOf: b.asOf, appBalance: current + selectedEffect)
        }
        return ImportPlan(targetAccountID: target.id, candidates: candidates, balanceSuggestions: suggestions, warnings: warnings, result: result)
    }

    /// A balance-correction transaction that makes the app match the document.
    public static func adjustment(for s: BalanceSuggestion, accountID: UUID, today: LocalDate) -> FinanceTransaction? {
        let diff = s.difference.rounded(scale: 2)
        guard diff != 0 else { return nil }
        return FinanceTransaction(kind: .adjustment, amount: diff.magnitudeValue, adjustmentIsNegative: diff < 0, accountID: accountID,
                                  title: "התאמת יתרה לפי מסמך", date: s.asOf ?? today, notes: s.label, source: .documentImport)
    }
}
