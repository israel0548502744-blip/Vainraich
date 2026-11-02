import Foundation

/// A possible "this income is the payment for that event" link. Never applied without the user's approval.
public struct EventMatchSuggestion: Identifiable, Hashable, Sendable {
    public var id: String { "\(eventID)-\(transactionID)" }
    public var eventID: UUID
    public var transactionID: UUID
    public var score: Int
    /// Hebrew reasons shown to the user ("אותו סכום", "אותו לקוח"…).
    public var reasons: [String]
}

/// An event the app needs the user's answer about: "did you get paid for this?".
public struct EventPaymentQuestion: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        /// Found income that looks like the payment — confirm or reject.
        case possibleMatch
        /// The event has passed and expected income is still open — was it paid?
        case unpaidAfterEvent
        /// The title suggests a paid event ("אירוע", "חתונה"…) but no amount was entered — is it a paid event?
        case unknownIfPaid
    }

    public var id: UUID { event.id }
    public var event: FinanceEvent
    public var kind: Kind
    public var suggestions: [EventMatchSuggestion]
    /// Expected income not yet received (0 when unknown).
    public var outstanding: Decimal
}

/// Finds income that probably belongs to events, and events whose payment status needs the user's answer.
///
/// Rules:
/// * Every event whose title contains "אירוע" (or a typical paid-gig word) is checked for income, even without an amount.
/// * Candidate income: not linked to any event, not cancelled, from 14 days before to 45 days after the event.
/// * Scored by amount, client, words in the description and timing; weak matches are not shown.
/// * Transactions the user rejected for an event are never suggested for it again.
/// * Each transaction is suggested for at most one event (the best match).
public enum EventMatcher {
    /// Words that usually mean a paid event. "אירוע" is the main trigger requested by the user.
    public static let incomeKeywords = ["אירוע", "אירועים", "חתונה", "חתונת", "בר מצווה", "בת מצווה", "ברית", "הופעה", "צילום", "צילומי", "הפקה", "כנס", "סדנה", "יום הולדת", "אירוסין", "חינה"]

    public static func looksLikeIncomeEvent(_ title: String) -> Bool {
        let t = title.lowercased()
        return incomeKeywords.contains { t.contains($0) }
    }

    /// Whether this event should be checked for payments at all.
    public static func isCandidate(_ e: FinanceEvent) -> Bool {
        if e.isIncomeEvent == false { return false }
        return (e.expectedIncome ?? 0) > 0 || e.isIncomeEvent == true || looksLikeIncomeEvent(e.title)
    }

    static let window = (before: 14, after: 45)
    static let minimumScore = 30

    static func significantWords(_ s: String) -> Set<String> {
        let stop: Set<String> = ["של", "עם", "על", "את", "תשלום", "העברה", "הכנסה", "מאת", "עבור", "אירוע", "ביט", "bit"]
        let cleaned = s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return Set(String(cleaned).split(separator: " ").map(String.init).filter { $0.count >= 3 && !stop.contains($0) })
    }

    /// Hebrew attaches prefixes to words ("מלוי" = "from Levi"), so a word also matches after removing one prefix letter.
    static let hebrewPrefixes: Set<Character> = ["מ", "ב", "ל", "ו", "ה", "ש", "כ"]

    static func stems(_ w: String) -> Set<String> {
        var out: Set<String> = [w]
        if w.count >= 4, let f = w.first, hebrewPrefixes.contains(f) { out.insert(String(w.dropFirst())) }
        return out
    }

    static func commonWords(_ a: Set<String>, _ b: Set<String>) -> Set<String> {
        var result = Set<String>()
        for x in a {
            let sx = stems(x)
            if b.contains(where: { !stems($0).isDisjoint(with: sx) }) { result.insert(x) }
        }
        return result
    }

    public static func score(event e: FinanceEvent, transaction t: FinanceTransaction, outstanding: Decimal, data: FinanceData) -> (Int, [String]) {
        var score = 0
        var reasons: [String] = []
        if let expected = e.expectedIncome, expected > 0 {
            if t.amount == outstanding && outstanding > 0 { score += 50; reasons.append("אותו סכום שנותר לגבות") }
            else if t.amount == expected { score += 45; reasons.append("אותו סכום כמו ההכנסה הצפויה") }
            else if t.amount < expected && t.amount * 4 >= expected { score += 10; reasons.append("יכול להיות תשלום חלקי או מקדמה") }
        }
        if let c = e.contactID {
            if t.contactID == c {
                score += 35; reasons.append("אותו לקוח")
            } else if let name = data.contact(c)?.name, !name.isEmpty {
                let first = name.split(separator: " ").first.map(String.init) ?? name
                let text = (t.title + " " + t.notes).lowercased()
                if first.count >= 2 && text.contains(first.lowercased()) { score += 25; reasons.append("שם הלקוח מופיע בתיאור") }
            }
        }
        let common = commonWords(significantWords(e.title), significantWords(t.title + " " + t.notes))
        if !common.isEmpty { score += 20; reasons.append("מילים משותפות: \(common.sorted().joined(separator: ", "))") }
        let days = e.date.days(until: t.date)
        if (0...7).contains(days) { score += 10; reasons.append(days == 0 ? "התקבל ביום האירוע" : "התקבל \(days) ימים אחרי האירוע") }
        else if (-14 ... -1).contains(days) { score += 5; reasons.append("התקבל לפני האירוע (מקדמה?)") }
        if t.categoryID == DefaultCategories.income[1].id { score += 5 }
        return (score, reasons)
    }

    /// Best suggestions per event (each transaction offered for one event only).
    public static func suggestions(data: FinanceData, today: LocalDate) -> [UUID: [EventMatchSuggestion]] {
        let linkedToDebtPayment = Set(data.debtPayments.compactMap(\.transactionID))
        let pool = data.transactions.filter {
            $0.kind == .income && $0.status != .cancelled && $0.eventID == nil && !linkedToDebtPayment.contains($0.id)
        }
        var all: [EventMatchSuggestion] = []
        for e in data.events where isCandidate(e) {
            let fin = EventCalculator.financials(of: e, transactions: data.transactions)
            if let expected = e.expectedIncome, expected > 0, fin.receivedIncome >= expected { continue } // already fully paid
            let rejected = Set(e.rejectedTransactionIDs ?? [])
            for t in pool where !rejected.contains(t.id) {
                let d = e.date.days(until: t.date)
                guard d >= -window.before && d <= window.after else { continue }
                let (s, reasons) = score(event: e, transaction: t, outstanding: fin.outstandingIncome, data: data)
                if s >= minimumScore { all.append(EventMatchSuggestion(eventID: e.id, transactionID: t.id, score: s, reasons: reasons)) }
            }
        }
        // Greedy: strongest pairs first; a transaction is offered once.
        var usedTx = Set<UUID>()
        var result: [UUID: [EventMatchSuggestion]] = [:]
        for s in all.sorted(by: { ($0.score, $0.transactionID.uuidString) > ($1.score, $1.transactionID.uuidString) }) where !usedTx.contains(s.transactionID) {
            usedTx.insert(s.transactionID)
            result[s.eventID, default: []].append(s)
        }
        return result
    }

    /// Everything that needs the user's answer, most urgent first.
    public static func questions(data: FinanceData, today: LocalDate) -> [EventPaymentQuestion] {
        let sugg = suggestions(data: data, today: today)
        var out: [EventPaymentQuestion] = []
        for e in data.events where isCandidate(e) {
            let fin = EventCalculator.financials(of: e, transactions: data.transactions)
            let s = sugg[e.id] ?? []
            let hasDebt = e.debtID.flatMap { data.debt($0) } != nil
            if !s.isEmpty {
                out.append(EventPaymentQuestion(event: e, kind: .possibleMatch, suggestions: s, outstanding: fin.outstandingIncome))
                continue
            }
            guard e.date <= today, !hasDebt else { continue }
            if let expected = e.expectedIncome, expected > 0 {
                if fin.outstandingIncome > 0 {
                    out.append(EventPaymentQuestion(event: e, kind: .unpaidAfterEvent, suggestions: [], outstanding: fin.outstandingIncome))
                }
            } else if e.isIncomeEvent == nil && fin.receivedIncome == 0 {
                out.append(EventPaymentQuestion(event: e, kind: .unknownIfPaid, suggestions: [], outstanding: 0))
            }
        }
        let order: [EventPaymentQuestion.Kind] = [.possibleMatch, .unpaidAfterEvent, .unknownIfPaid]
        return out.sorted { (order.firstIndex(of: $0.kind)!, $1.event.date) < (order.firstIndex(of: $1.kind)!, $0.event.date) }
    }
}
