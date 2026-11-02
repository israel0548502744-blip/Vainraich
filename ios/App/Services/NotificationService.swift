import Foundation
import UserNotifications
import Observation
import FinanceCore

/// Local reminders (no server needed): due payments, overdue debts, upcoming events,
/// pending/recurring items and negative-balance warnings. Rebuilt whenever data changes.
@MainActor
@Observable
final class NotificationService {
    enum Kind: String, CaseIterable, Identifiable {
        case paymentDue, debtOverdue, eventUpcoming, recurringDue, negativeForecast
        var id: String { rawValue }
        var title: String {
            switch self {
            case .paymentDue: return "תשלומים שמגיע מועדם"
            case .debtOverdue: return "חובות שעבר מועדם"
            case .eventUpcoming: return "אירועים קרובים"
            case .recurringDue: return "תשלומים קבועים"
            case .negativeForecast: return "אזהרת יתרה שלילית"
            }
        }
        var key: String { "notify.\(rawValue)" }
    }

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var scheduledCount = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    private let prefix = "vr."

    nonisolated static var reminderHour: Int {
        get { UserDefaults.standard.object(forKey: "notify.hour") as? Int ?? 9 }
        set { UserDefaults.standard.set(newValue, forKey: "notify.hour") }
    }

    nonisolated static func isEnabled(_ kind: Kind) -> Bool { UserDefaults.standard.object(forKey: kind.key) as? Bool ?? true }
    nonisolated static func setEnabled(_ kind: Kind, _ on: Bool) { UserDefaults.standard.set(on, forKey: kind.key) }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return granted
    }

    /// Debounced rescheduling.
    func scheduleSoon(for data: FinanceData, today: LocalDate, isDemo: Bool) {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.reschedule(for: data, today: today, isDemo: isDemo)
        }
    }

    func reschedule(for data: FinanceData, today: LocalDate, isDemo: Bool) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        await refreshAuthorization()
        // Never schedule reminders for demonstration data.
        guard !isDemo, authorization == .authorized || authorization == .provisional else { scheduledCount = 0; return }

        let requests = NotificationService.plan(for: data, today: today, hour: NotificationService.reminderHour, isEnabled: NotificationService.isEnabled)
        for r in requests.prefix(60) { // iOS keeps at most 64 pending local notifications per app
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            var comps = DateComponents(year: r.date.year, month: r.date.month, day: r.date.day, hour: r.hour, minute: 0)
            comps.timeZone = LocalDate.israelTimeZone
            let req = UNNotificationRequest(identifier: prefix + r.id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(req)
        }
        scheduledCount = min(requests.count, 60)
    }

    struct Planned: Hashable {
        var id: String
        var date: LocalDate
        var hour: Int
        var title: String
        var body: String
    }

    /// Pure planning logic (testable): which reminders to show and when.
    nonisolated static func plan(for data: FinanceData, today: LocalDate, hour: Int, isEnabled: (Kind) -> Bool) -> [Planned] {
        var out: [Planned] = []
        let horizon = today.adding(days: 45)
        let lead = max(0, data.settings.reminderLeadDays)

        func add(_ id: String, _ date: LocalDate, _ title: String, _ body: String, hour h: Int = hour) {
            var d = date
            if d < today { d = today }
            // Skip a time that has already passed today.
            if d == today {
                let nowHour = LocalDate.financeCalendar.component(.hour, from: Date())
                if nowHour >= h { return }
            }
            if d <= horizon { out.append(Planned(id: id, date: d, hour: h, title: title, body: body)) }
        }

        let balances = DebtCalculator.balances(data, today: today)
        for b in balances where b.isOpen && b.remaining > 0 {
            guard let due = b.debt.dueDate else { continue }
            let who = data.contact(b.debt.contactID)?.name ?? ""
            let amount = MoneyFormatter.format(b.remaining)
            if isEnabled(.paymentDue) {
                let text = b.debt.direction == .receivable ? "\(who) אמור/ה להחזיר \(amount) — \(b.debt.title)" : "צריך לשלם ל\(who) \(amount) — \(b.debt.title)"
                add("due-\(b.debt.id)", due.adding(days: -lead), lead == 0 ? "מועד תשלום היום" : "מועד תשלום מתקרב", text)
            }
            if isEnabled(.debtOverdue) {
                let text = b.debt.direction == .receivable ? "\(who) עדיין חייב/ת \(amount) (\(b.debt.title))" : "עדיין לא שילמת ל\(who) \(amount)"
                add("over-\(b.debt.id)", max(due.adding(days: 1), today), "חוב שעבר מועדו", text)
            }
        }

        if isEnabled(.eventUpcoming) {
            for e in data.events where e.date >= today && e.date <= horizon {
                var body = e.title
                if let t = e.startTime { body += " ב־\(t)" }
                if let inc = e.expectedIncome, inc > 0 { body += " · הכנסה צפויה \(MoneyFormatter.format(inc))" }
                add("evt-\(e.id)", e.date.adding(days: -1), "מחר: \(e.title)", body, hour: 20)
                let fin = EventCalculator.financials(of: e, transactions: data.transactions)
                if fin.outstandingIncome > 0 && e.debtID == nil {
                    add("evt-pay-\(e.id)", e.date.adding(days: 1), "האם התקבל תשלום?", "על \(e.title): \(MoneyFormatter.format(fin.outstandingIncome)) עדיין פתוח")
                }
            }
        }

        if isEnabled(.recurringDue) {
            for t in data.transactions where t.status == .pending && t.date >= today && t.date <= horizon {
                add("pend-\(t.id)", t.date, t.kind == .income ? "הכנסה צפויה היום" : "תשלום צפוי היום", "\(t.title): \(MoneyFormatter.format(t.amount))")
            }
            for rule in data.recurringRules where rule.isActive && !rule.autoPost {
                if let next = RecurrenceEngine.nextOccurrence(of: rule, onOrAfter: today), next <= horizon,
                   !data.transactions.contains(where: { $0.recurringID == rule.id && $0.occurrenceDate == next }) {
                    add("rec-\(rule.id)-\(next.isoString)", next, "תשלום קבוע היום", "\(rule.title): \(MoneyFormatter.format(rule.amount))")
                }
            }
        }

        if isEnabled(.negativeForecast) {
            let f = ForecastEngine.make(data: data, range: .next(30, from: today), today: today)
            if let neg = f.firstNegativeDay {
                add("neg-\(neg.date.isoString)", max(today, neg.date.adding(days: -3)), "אזהרה: היתרה צפויה לרדת מתחת לאפס",
                    "ב־\(neg.date) היתרה החזויה היא \(MoneyFormatter.format(neg.projectedBalance)).")
            }
        }
        return out.sorted { ($0.date, $0.hour) < ($1.date, $1.hour) }
    }
}
