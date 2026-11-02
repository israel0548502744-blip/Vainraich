import SwiftUI
import FinanceCore

enum CalendarMode: String, CaseIterable, Identifiable {
    case month, week, day
    var id: String { rawValue }
    var title: String {
        switch self {
        case .month: return "חודש"
        case .week: return "שבוע"
        case .day: return "יום"
        }
    }
}

/// Things to draw on a calendar day.
struct DayMarkers {
    var incomeUnpaid = false
    var incomePaid = false
    var incomePartial = false
    var expense = false
    var debtDue = false
    var plainEvent = false
}

struct CalendarScreen: View {
    @Environment(AppModel.self) private var model
    @State private var mode: CalendarMode = .month
    @State private var selected = LocalDate.today()
    @State private var anchor = LocalDate.today()
    @State private var adding = false
    @State private var openEvent: FinanceEvent?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                DemoBanner()
                Picker("תצוגה", selection: $mode) { ForEach(CalendarMode.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented)
                header
                switch mode {
                case .month: monthGrid.card(padding: 10)
                case .week: weekStrip.card(padding: 10)
                case .day: EmptyView()
                }
                legend
                dayDetails
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("יומן")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("אירוע חדש") }
            ToolbarItem(placement: .topBarLeading) { Button("היום") { selected = model.today; anchor = model.today } }
        }
        .sheet(isPresented: $adding) { EventEditor(event: nil, date: selected) }
        .navigationDestination(item: $openEvent) { EventDetailView(eventID: $0.id) }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("הקודם")
            Spacer()
            Text(headerTitle).font(.title3.weight(.semibold))
            Spacer()
            Button { step(1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("הבא")
        }
        .padding(.horizontal, 6)
    }

    private var headerTitle: String {
        switch mode {
        case .month: return anchor.monthYear
        case .week:
            let w = DateRange.week(containing: anchor)
            return "\(w.start.day)–\(w.end.day) ב\(Labels.monthName(w.end.month))"
        case .day: return selected.weekdayAndDay
        }
    }

    private func step(_ n: Int) {
        switch mode {
        case .month: anchor = anchor.startOfMonth.adding(months: n); selected = anchor
        case .week: anchor = anchor.adding(days: 7 * n); selected = anchor
        case .day: selected = selected.adding(days: n); anchor = selected
        }
    }

    // MARK: Markers

    private func markers(for d: LocalDate) -> DayMarkers {
        var m = DayMarkers()
        for e in model.data.events where e.date == d {
            let status = EventCalculator.paymentStatus(of: e, in: model.data, today: model.today)
            switch status {
            case .unpaid: m.incomeUnpaid = true
            case .paid: m.incomePaid = true
            case .partiallyPaid: m.incomePartial = true
            case .none: m.plainEvent = true
            }
            if (e.expectedExpense ?? 0) > 0 { m.expense = true }
        }
        for debt in model.data.debts where debt.dueDate == d {
            if model.debtBalance(debt).isOpen { m.debtDue = true }
        }
        return m
    }

    // MARK: Month

    private var monthGrid: some View {
        let first = anchor.startOfMonth
        let lead = (first.weekday - 1)
        let days = (0..<first.daysInMonth).map { first.adding(days: $0) }
        let cells: [LocalDate?] = Array(repeating: nil, count: lead) + days.map { Optional($0) }
        return VStack(spacing: 6) {
            HStack {
                ForEach(0..<7, id: \.self) { i in
                    Text(Labels.weekdayShort[i]).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, d in
                    if let d { dayCell(d) } else { Color.clear.frame(height: 46) }
                }
            }
        }
    }

    private func dayCell(_ d: LocalDate) -> some View {
        let m = markers(for: d)
        let isSel = d == selected
        let isToday = d == model.today
        return Button { selected = d } label: {
            VStack(spacing: 3) {
                Text("\(d.day)")
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSel ? Color.white : (isToday ? Theme.brand : .primary))
                    .frame(width: 30, height: 30)
                    .background(isSel ? Theme.brand : (isToday ? Theme.brandSoft : .clear), in: Circle())
                HStack(spacing: 2) {
                    if m.incomeUnpaid { dot(Theme.expected) }
                    if m.incomePartial { dot(Theme.token("blue")) }
                    if m.incomePaid { dot(Theme.actual) }
                    if m.expense { dot(Theme.liability) }
                    if m.debtDue { dot(Theme.receivable) }
                    if m.plainEvent { dot(Theme.neutral) }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(d.long)\(m.incomeUnpaid ? ", הכנסה שלא שולמה" : "")\(m.incomePaid ? ", שולם" : "")\(m.debtDue ? ", מועד חוב" : "")")
    }

    private func dot(_ c: Color) -> some View { Circle().fill(c).frame(width: 5, height: 5) }

    // MARK: Week

    private var weekStrip: some View {
        let w = DateRange.week(containing: anchor)
        return HStack(spacing: 2) {
            ForEach(w.days, id: \.self) { d in
                VStack(spacing: 4) {
                    Text(Labels.weekdayShort[d.weekday - 1]).font(.caption2).foregroundStyle(Theme.textSecondary)
                    dayCell(d)
                }
            }
        }
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(Theme.expected, "הכנסה צפויה")
            legendItem(Theme.actual, "שולם")
            legendItem(Theme.liability, "הוצאה")
            legendItem(Theme.receivable, "מועד חוב")
        }
        .font(.caption2)
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity)
    }

    private func legendItem(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 7, height: 7); Text(t) }
    }

    // MARK: Day list

    private var visibleDays: [LocalDate] {
        switch mode {
        case .month, .day: return [selected]
        case .week: return DateRange.week(containing: anchor).days
        }
    }

    private var dayDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(visibleDays, id: \.self) { d in
                let events = model.data.events.filter { $0.date == d }.sorted { ($0.startTime ?? TimeOfDay(hour: 0, minute: 0)) < ($1.startTime ?? TimeOfDay(hour: 0, minute: 0)) }
                let dues = model.data.debts.filter { $0.dueDate == d && model.debtBalance($0).isOpen }
                let items = model.forecast(.day(d)).items.filter { if case .pendingTransaction = $0.source { return true }; if case .recurring = $0.source { return true }; if case .creditCardBill = $0.source { return true }; return false }
                if mode != .week || !(events.isEmpty && dues.isEmpty && (d < model.today || items.isEmpty)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(d == model.today ? "היום · \(d.weekdayAndDay)" : d.weekdayAndDay).font(.headline)
                        if events.isEmpty && dues.isEmpty && (d < model.today || items.isEmpty) {
                            HStack {
                                Text("אין אירועים").foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Button("הוספת אירוע") { selected = d; adding = true }.font(.subheadline)
                            }
                        }
                        ForEach(events) { e in
                            Button { openEvent = e } label: { EventRow(event: e) }.buttonStyle(.plain)
                        }
                        ForEach(dues) { debt in
                            NavigationLink { DebtDetailView(debtID: debt.id) } label: { DebtDueRow(debt: debt) }.buttonStyle(.plain)
                        }
                        if d >= model.today {
                            ForEach(items) { ForecastItemRow(item: $0) }
                        }
                    }
                    .card()
                }
            }
        }
    }
}

struct EventRow: View {
    @Environment(AppModel.self) private var model
    let event: FinanceEvent

    var body: some View {
        let status = EventCalculator.paymentStatus(of: event, in: model.data, today: model.today)
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(status == .none ? Theme.neutral : status.color).frame(width: 4, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if let s = event.startTime { Text(ltr(event.endTime.map { "\(s)–\($0)" } ?? "\(s)")) }
                    if let c = model.data.contact(event.contactID) { Text(c.name) }
                    if !event.location.isEmpty { Text(event.location).lineLimit(1) }
                }
                .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let inc = event.expectedIncome, inc > 0 {
                    AmountText(amount: inc, font: .subheadline.weight(.semibold).monospacedDigit(), color: status.color)
                    StatusBadge(text: status.hebrewName, color: status.color)
                } else if let exp = event.expectedExpense, exp > 0 {
                    AmountText(amount: -exp, font: .subheadline.monospacedDigit(), color: Theme.liability)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct DebtDueRow: View {
    @Environment(AppModel.self) private var model
    let debt: Debt

    var body: some View {
        let b = model.debtBalance(debt)
        HStack(spacing: 12) {
            CategoryIcon(icon: debt.direction == .receivable ? "arrow.down.left.circle" : "arrow.up.right.circle", color: Theme.receivable, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(debt.direction == .receivable ? "\(model.data.contact(debt.contactID)?.name ?? "") אמור להחזיר" : "לשלם ל\(model.data.contact(debt.contactID)?.name ?? "")")
                    .font(.subheadline)
                Text(debt.title).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            AmountText(amount: b.remaining, font: .subheadline.weight(.semibold).monospacedDigit(), color: Theme.receivable)
        }
        .contentShape(Rectangle())
    }
}
