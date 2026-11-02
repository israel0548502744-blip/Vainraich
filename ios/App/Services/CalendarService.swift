import Foundation
import EventKit
import Observation
import FinanceCore

/// Apple Calendar integration through EventKit. Never reads or writes without explicit permission,
/// and imported events never get income automatically.
@MainActor
@Observable
final class CalendarService {
    @ObservationIgnored private let store = EKEventStore()
    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    static let appCalendarTitle = "הכספים שלי"

    var canRead: Bool { status == .fullAccess }
    var canWrite: Bool { status == .fullAccess || status == .writeOnly }

    var statusText: String {
        switch status {
        case .fullAccess: return "גישה מלאה (ייבוא וייצוא)"
        case .writeOnly: return "הוספה בלבד (ייצוא)"
        case .denied: return "הגישה נדחתה — אפשר לשנות בהגדרות האייפון"
        case .restricted: return "הגישה חסומה במכשיר"
        case .notDetermined: return "עדיין לא אושרה גישה"
        default: return "לא ידוע"
        }
    }

    func refresh() { status = EKEventStore.authorizationStatus(for: .event) }

    func requestFullAccess() async -> Bool {
        let ok = (try? await store.requestFullAccessToEvents()) ?? false
        refresh()
        return ok
    }

    func requestWriteOnlyAccess() async -> Bool {
        let ok = (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        refresh()
        return ok
    }

    func calendars() -> [EKCalendar] {
        guard canRead else { return [] }
        return store.calendars(for: .event).sorted { $0.title < $1.title }
    }

    /// Reads events and converts them (no income/expense is assumed).
    func importableEvents(calendarIDs: Set<String>, range: DateRange) -> [FinanceEvent] {
        guard canRead else { return [] }
        let cals = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !cals.isEmpty else { return [] }
        let start = range.start.date()
        let end = range.end.adding(days: 1).date()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: cals)
        return store.events(matching: predicate).map { ek in
            let cal = LocalDate.financeCalendar
            return FinanceEvent(
                title: ek.title ?? "אירוע",
                date: LocalDate(ek.startDate, calendar: cal),
                startTime: ek.isAllDay ? nil : TimeOfDay(date: ek.startDate),
                endTime: ek.isAllDay ? nil : TimeOfDay(date: ek.endDate),
                location: ek.location ?? "",
                notes: ek.notes ?? "",
                calendarEventIdentifier: ek.eventIdentifier
            )
        }
    }

    private func targetCalendar() throws -> EKCalendar {
        if canRead, let existing = store.calendars(for: .event).first(where: { $0.title == Self.appCalendarTitle && $0.allowsContentModifications }) {
            return existing
        }
        if canRead, let source = store.defaultCalendarForNewEvents?.source {
            let cal = EKCalendar(for: .event, eventStore: store)
            cal.title = Self.appCalendarTitle
            cal.source = source
            cal.cgColor = CGColor(red: 0.06, green: 0.46, blue: 0.46, alpha: 1)
            try store.saveCalendar(cal, commit: true)
            return cal
        }
        guard let def = store.defaultCalendarForNewEvents else { throw CocoaError(.featureUnsupported) }
        return def
    }

    /// Creates or updates the Apple Calendar copy of an event. Returns its identifier.
    func export(_ event: FinanceEvent) throws -> String {
        guard canWrite else { throw CocoaError(.userCancelled) }
        var ek: EKEvent?
        if canRead, let id = event.calendarEventIdentifier { ek = store.event(withIdentifier: id) }
        let e = ek ?? EKEvent(eventStore: store)
        if ek == nil { e.calendar = try targetCalendar() }
        e.title = event.title
        e.location = event.location.isEmpty ? nil : event.location
        let cal = LocalDate.financeCalendar
        let day = event.date.date(calendar: cal)
        if let s = event.startTime {
            e.isAllDay = false
            e.startDate = cal.date(byAdding: .minute, value: s.minutesSinceMidnight, to: day)
            let endMinutes = event.endTime?.minutesSinceMidnight ?? (s.minutesSinceMidnight + 60)
            e.endDate = cal.date(byAdding: .minute, value: max(endMinutes, s.minutesSinceMidnight + 15), to: day)
        } else {
            e.isAllDay = true
            e.startDate = day
            e.endDate = day
        }
        var notes: [String] = []
        if let i = event.expectedIncome, i > 0 { notes.append("הכנסה צפויה: \(MoneyFormatter.format(i))") }
        if let x = event.expectedExpense, x > 0 { notes.append("הוצאה צפויה: \(MoneyFormatter.format(x))") }
        if !event.notes.isEmpty { notes.append(event.notes) }
        e.notes = notes.isEmpty ? nil : notes.joined(separator: "\n")
        e.timeZone = LocalDate.israelTimeZone
        try store.save(e, span: .thisEvent, commit: true)
        return e.eventIdentifier ?? event.calendarEventIdentifier ?? ""
    }
}
