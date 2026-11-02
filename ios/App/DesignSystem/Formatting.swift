import SwiftUI
import FinanceCore

/// Wraps text in Unicode left-to-right isolates so "-₪1,500" never flips inside Hebrew text.
func ltr(_ s: String) -> String { "\u{2066}" + s + "\u{2069}" }

extension Decimal {
    /// "₪1,500" (LTR-isolated, safe inside Hebrew sentences).
    var ils: String { ltr(MoneyFormatter.format(self)) }
    var ilsSigned: String { ltr(MoneyFormatter.format(self, showPlus: true)) }
    var ilsCompact: String { ltr(MoneyFormatter.compact(self)) }
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue } // charts only
}

extension LocalDate {
    /// "15/12/2026"
    var short: String { ltr(description) }
    /// "15 בדצמבר 2026"
    var long: String { "\(day) ב\(Labels.monthName(month)) \(year)" }
    /// "יום שלישי, 15 בדצמבר"
    var weekdayAndDay: String { "יום \(Labels.weekdayLong[weekday - 1]), \(day) ב\(Labels.monthName(month))" }
    var monthYear: String { "\(Labels.monthName(month)) \(year)" }

    /// Relative label for lists: היום / מחר / אתמול / date.
    func relative(to today: LocalDate) -> String {
        switch today.days(until: self) {
        case 0: return "היום"
        case 1: return "מחר"
        case -1: return "אתמול"
        case 2...6: return "בעוד \(today.days(until: self)) ימים"
        default: return short
        }
    }
}

extension Binding where Value == LocalDate {
    /// Bridges a `LocalDate` to SwiftUI's `DatePicker`.
    var asDate: Binding<Date> {
        Binding<Date>(get: { wrappedValue.date().addingTimeInterval(12 * 3600) }, set: { wrappedValue = LocalDate($0) })
    }
}

extension Binding where Value == LocalDate? {
    func asDate(default d: LocalDate) -> Binding<Date> {
        Binding<Date>(get: { (wrappedValue ?? d).date().addingTimeInterval(12 * 3600) }, set: { wrappedValue = LocalDate($0) })
    }
}

extension TimeOfDay {
    var asDate: Date {
        LocalDate.financeCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
    init(date: Date) {
        let c = LocalDate.financeCalendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }
}

extension ValidationError {
    var hebrewMessage: String {
        switch self {
        case .emptyTitle: return "יש למלא שם או תיאור."
        case .nonPositiveAmount: return "הסכום חייב להיות גדול מאפס."
        case .unknownAccount: return "יש לבחור חשבון."
        case .transferNeedsDestination: return "בהעברה יש לבחור לאיזה חשבון."
        case .transferToSameAccount: return "אי אפשר להעביר לאותו חשבון."
        case .categoryNotAllowedOnTransfer: return "העברה בין חשבונות לא מקבלת קטגוריה."
        case .categoryKindMismatch: return "הקטגוריה לא מתאימה לסוג התנועה."
        case .currencyMismatch: return "שני החשבונות צריכים להיות באותו מטבע."
        case .recurringOccurrenceMismatch: return "שגיאה בקישור לתשלום הקבוע."
        case .paymentExceedsRemaining(let r): return "הסכום גבוה מהיתרה לתשלום (\(r.ils))."
        case .debtClosed: return "החוב כבר סגור."
        case .eventTimeOrder: return "שעת הסיום מוקדמת משעת ההתחלה."
        case .invalidBillingDay: return "יום החיוב צריך להיות בין 1 ל־31."
        }
    }
}

func hebrewMessage(for error: Error) -> String {
    if let v = error as? ValidationError { return v.hebrewMessage }
    if let a = error as? DocumentAIErrorBridge { return a.message }
    return "אירעה שגיאה: \(error.localizedDescription)"
}

/// Lets features surface their own Hebrew error text through `hebrewMessage(for:)`.
protocol DocumentAIErrorBridge: Error { var message: String { get } }
