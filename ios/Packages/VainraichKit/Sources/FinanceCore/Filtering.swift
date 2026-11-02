import Foundation

/// Search + filter criteria for the transactions list.
public struct TransactionFilter: Hashable, Sendable {
    public var searchText: String = ""
    public var kinds: Set<TransactionKind> = []
    public var statuses: Set<TransactionStatus> = []
    public var categoryIDs: Set<UUID> = []
    public var accountIDs: Set<UUID> = []
    public var dateRange: DateRange?

    public init(searchText: String = "", kinds: Set<TransactionKind> = [], statuses: Set<TransactionStatus> = [],
                categoryIDs: Set<UUID> = [], accountIDs: Set<UUID> = [], dateRange: DateRange? = nil) {
        self.searchText = searchText
        self.kinds = kinds
        self.statuses = statuses
        self.categoryIDs = categoryIDs
        self.accountIDs = accountIDs
        self.dateRange = dateRange
    }

    public var isActive: Bool {
        !kinds.isEmpty || !statuses.isEmpty || !categoryIDs.isEmpty || !accountIDs.isEmpty || dateRange != nil
    }

    public func matches(_ t: FinanceTransaction, in data: FinanceData) -> Bool {
        if !kinds.isEmpty && !kinds.contains(t.kind) { return false }
        if !statuses.isEmpty && !statuses.contains(t.status) { return false }
        if !categoryIDs.isEmpty && !(t.categoryID.map(categoryIDs.contains) ?? false) { return false }
        if !accountIDs.isEmpty && !accountIDs.contains(t.accountID) && !(t.counterAccountID.map(accountIDs.contains) ?? false) { return false }
        if let r = dateRange, !r.contains(t.date) { return false }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            let haystack = [t.title, t.notes, data.category(t.categoryID)?.name ?? "", data.contact(t.contactID)?.name ?? "",
                            data.account(t.accountID)?.name ?? "", t.amount.plainString]
                .joined(separator: " ")
            if haystack.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) == nil { return false }
        }
        return true
    }

    public func apply(to data: FinanceData) -> [FinanceTransaction] {
        data.transactions.filter { matches($0, in: data) }
            .sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
    }
}

// MARK: - CSV

public enum CSVExporter {
    static func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    /// UTF-8 CSV with BOM (so Excel shows Hebrew correctly). Amounts are signed and plain ("-300.00").
    public static func transactions(_ list: [FinanceTransaction], data: FinanceData) -> String {
        var lines = ["תאריך,תיאור,סוג,סטטוס,סכום,חשבון,לחשבון,קטגוריה,איש קשר,אמצעי תשלום,הערות"]
        for t in list.sorted(by: { $0.date < $1.date }) {
            let signed: Decimal
            switch t.kind {
            case .income: signed = t.amount
            case .expense: signed = -t.amount
            case .transfer: signed = t.amount
            case .adjustment: signed = t.adjustmentIsNegative ? -t.amount : t.amount
            }
            let row = [
                t.date.description, t.title, Labels.kind(t.kind), Labels.status(t.status), signed.plainString,
                data.account(t.accountID)?.name ?? "", data.account(t.counterAccountID)?.name ?? "",
                data.category(t.categoryID)?.name ?? "", data.contact(t.contactID)?.name ?? "",
                t.paymentMethod.map(Labels.paymentMethod) ?? "", t.notes,
            ].map(escape)
            lines.append(row.joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    public static func monthly(_ months: [MonthSummary]) -> String {
        var lines = ["חודש,הכנסות,הוצאות,תזרים נטו"]
        for m in months {
            lines.append([m.month.label, m.income.plainString, m.expenses.plainString, m.net.plainString].joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }
}

/// Hebrew labels shared by the app and exports.
public enum Labels {
    public static func kind(_ k: TransactionKind) -> String {
        switch k {
        case .income: return "הכנסה"
        case .expense: return "הוצאה"
        case .transfer: return "העברה"
        case .adjustment: return "עדכון יתרה"
        }
    }

    public static func status(_ s: TransactionStatus) -> String {
        switch s {
        case .pending: return "ממתין"
        case .completed: return "בוצע"
        case .cancelled: return "בוטל"
        }
    }

    public static func paymentMethod(_ p: PaymentMethod) -> String {
        switch p {
        case .bankTransfer: return "העברה בנקאית"
        case .creditCard: return "כרטיס אשראי"
        case .cash: return "מזומן"
        case .bit: return "ביט"
        case .check: return "צ׳ק"
        case .standingOrder: return "הוראת קבע"
        case .other: return "אחר"
        }
    }

    public static func accountType(_ t: AccountType) -> String {
        switch t {
        case .bank: return "חשבון בנק"
        case .cash: return "מזומן"
        case .bit: return "ביט"
        case .creditCard: return "כרטיס אשראי"
        case .savings: return "חיסכון"
        case .other: return "אחר"
        }
    }

    public static func frequency(_ f: RecurrenceFrequency, interval: Int = 1) -> String {
        switch (f, interval) {
        case (.daily, 1): return "כל יום"
        case (.weekly, 1): return "כל שבוע"
        case (.weekly, 2): return "כל שבועיים"
        case (.monthly, 1): return "כל חודש"
        case (.monthly, 2): return "כל חודשיים"
        case (.yearly, 1): return "כל שנה"
        case (.daily, let n): return "כל \(n) ימים"
        case (.weekly, let n): return "כל \(n) שבועות"
        case (.monthly, let n): return "כל \(n) חודשים"
        case (.yearly, let n): return "כל \(n) שנים"
        }
    }

    public static func debtStatus(_ s: DebtStatus) -> String {
        switch s {
        case .open: return "פתוח"
        case .partiallyPaid: return "שולם חלקית"
        case .paid: return "שולם"
        case .writtenOff: return "נמחק"
        case .cancelled: return "בוטל"
        }
    }

    public static func eventPayment(_ s: EventPaymentStatus) -> String {
        switch s {
        case .none: return "ללא הכנסה"
        case .unpaid: return "לא שולם"
        case .partiallyPaid: return "שולם חלקית"
        case .paid: return "שולם"
        }
    }

    public static func confidence(_ c: ForecastConfidence) -> String {
        switch c {
        case .confirmed: return "מאושר"
        case .expected: return "צפוי"
        case .estimated: return "משוער"
        }
    }

    public static let hebrewMonths = ["ינואר", "פברואר", "מרץ", "אפריל", "מאי", "יוני", "יולי", "אוגוסט", "ספטמבר", "אוקטובר", "נובמבר", "דצמבר"]
    public static let weekdayShort = ["א׳", "ב׳", "ג׳", "ד׳", "ה׳", "ו׳", "ש׳"]
    public static let weekdayLong = ["ראשון", "שני", "שלישי", "רביעי", "חמישי", "שישי", "שבת"]

    public static func monthName(_ m: Int) -> String { hebrewMonths[(max(1, min(12, m))) - 1] }
}
