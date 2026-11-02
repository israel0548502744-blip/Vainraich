import SwiftUI
import FinanceCore

struct EventEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(CalendarService.self) private var calendar
    @Environment(\.dismiss) private var dismiss
    let event: FinanceEvent?

    @State private var title = ""
    @State private var date: LocalDate
    @State private var hasTime = false
    @State private var start = TimeOfDay(hour: 18, minute: 0)
    @State private var end = TimeOfDay(hour: 20, minute: 0)
    @State private var location = ""
    @State private var contactID: UUID?
    @State private var incomeText = ""
    @State private var expenseText = ""
    @State private var notes = ""
    @State private var addToAppleCalendar = false
    @State private var error: String?

    init(event: FinanceEvent?, date: LocalDate) {
        self.event = event
        _date = State(initialValue: event?.date ?? date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("שם האירוע (למשל: צילום חתונה)", text: $title)
                    DatePicker("תאריך", selection: $date.asDate, displayedComponents: .date)
                    Toggle("שעה מוגדרת", isOn: $hasTime)
                    if hasTime {
                        DatePicker("התחלה", selection: Binding(get: { start.asDate }, set: { start = TimeOfDay(date: $0) }), displayedComponents: .hourAndMinute)
                        DatePicker("סיום", selection: Binding(get: { end.asDate }, set: { end = TimeOfDay(date: $0) }), displayedComponents: .hourAndMinute)
                    }
                    TextField("מיקום", text: $location)
                    ContactPicker(title: "לקוח / איש קשר", selection: $contactID)
                }
                Section {
                    MoneyField(title: "הכנסה צפויה", text: $incomeText)
                    MoneyField(title: "הוצאה צפויה", text: $expenseText)
                } header: {
                    Text("כסף")
                } footer: {
                    Text("השאר ריק אם האירוע לא קשור לכסף. הכנסה צפויה נכנסת לתחזית בלבד — היא לא נספרת ככסף זמין עד שתרשום שהתשלום התקבל.")
                }
                Section {
                    TextField("הערות", text: $notes, axis: .vertical).lineLimit(1...5)
                    if calendar.canWrite || calendar.status == .notDetermined {
                        Toggle("להוסיף גם ליומן של האייפון", isOn: $addToAppleCalendar)
                    }
                }
                if event != nil {
                    Section {
                        Button("מחיקת האירוע", role: .destructive) {
                            if let e = event { model.deleteEvent(e.id) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(event == nil ? "אירוע חדש" : "עריכת אירוע")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("שמירה") { Task { await save() } }.fontWeight(.semibold) }
            }
            .alert("לא ניתן לשמור", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("הבנתי", role: .cancel) {}
            } message: { Text(error ?? "") }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let e = event else { return }
        title = e.title
        hasTime = e.startTime != nil
        if let s = e.startTime { start = s }
        if let en = e.endTime { end = en }
        location = e.location
        contactID = e.contactID
        incomeText = e.expectedIncome?.editingText ?? ""
        expenseText = e.expectedExpense?.editingText ?? ""
        notes = e.notes
    }

    private func save() async {
        var e = event ?? FinanceEvent(title: title, date: date)
        e.title = title
        e.date = date
        e.startTime = hasTime ? start : nil
        e.endTime = hasTime ? end : nil
        e.location = location
        e.contactID = contactID
        e.expectedIncome = Decimal.parseMoney(incomeText).map { $0.magnitudeValue }.flatMap { $0 > 0 ? $0 : nil }
        e.expectedExpense = Decimal.parseMoney(expenseText).map { $0.magnitudeValue }.flatMap { $0 > 0 ? $0 : nil }
        e.notes = notes
        do {
            try model.save(e)
            if addToAppleCalendar {
                if calendar.status == .notDetermined { _ = await calendar.requestWriteOnlyAccess() }
                if calendar.canWrite {
                    let id = try? calendar.export(e)
                    if let id, !id.isEmpty { model.setCalendarIdentifier(id, for: e.id) }
                }
            }
            model.show("האירוע נשמר")
            dismiss()
        } catch {
            self.error = hebrewMessage(for: error)
        }
    }
}

struct EventDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(CalendarService.self) private var calendar
    @Environment(\.dismiss) private var dismiss
    let eventID: UUID

    @State private var editing = false
    @State private var recording: TransactionKind?
    @State private var creatingDebt = false
    @State private var openTransaction: FinanceTransaction?
    @State private var message: String?

    var body: some View {
        if let event = model.data.event(eventID) {
            content(event)
        } else {
            ContentUnavailableView("האירוע נמחק", systemImage: "calendar.badge.minus")
        }
    }

    private func content(_ event: FinanceEvent) -> some View {
        let fin = EventCalculator.financials(of: event, transactions: model.data.transactions)
        let status = EventCalculator.paymentStatus(of: event, in: model.data, today: model.today)
        let linked = model.data.transactions(forEvent: event.id).sorted { $0.date > $1.date }
        let debt = model.data.debt(event.debtID)
        return List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.title).font(.title2.weight(.semibold))
                    Label(event.date.weekdayAndDay + (event.startTime.map { " · " + ltr("\($0)") } ?? ""), systemImage: "calendar")
                    if !event.location.isEmpty { Label(event.location, systemImage: "mappin.and.ellipse") }
                    if let c = model.data.contact(event.contactID) { Label(c.name, systemImage: "person") }
                    if event.calendarEventIdentifier != nil { Label("מקושר ליומן האייפון", systemImage: "link").foregroundStyle(Theme.textSecondary) }
                }
                .font(.subheadline)
            }

            if (event.expectedIncome ?? 0) > 0 || (event.expectedExpense ?? 0) > 0 {
                Section("מצב כספי") {
                    if let inc = event.expectedIncome, inc > 0 {
                        HStack { Text("הכנסה צפויה"); Spacer(); AmountText(amount: inc) }
                        HStack { Text("התקבל בפועל"); Spacer(); AmountText(amount: fin.receivedIncome, color: Theme.actual) }
                        HStack {
                            Text("נותר לגבייה")
                            Spacer()
                            AmountText(amount: debt.map { model.debtBalance($0).remaining } ?? fin.outstandingIncome, color: Theme.expected)
                        }
                        HStack { Text("סטטוס"); Spacer(); StatusBadge(text: status.hebrewName, color: status.color) }
                    }
                    if let exp = event.expectedExpense, exp > 0 {
                        HStack { Text("הוצאה צפויה"); Spacer(); AmountText(amount: exp) }
                        HStack { Text("שולם בפועל"); Spacer(); AmountText(amount: fin.paidExpense, color: Theme.liability) }
                    }
                }
            }

            let suggestions = EventMatcher.suggestions(data: model.data, today: model.today)[event.id] ?? []
            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions) { s in
                        if let t = model.data.transactions.first(where: { $0.id == s.transactionID }) {
                            VStack(alignment: .leading, spacing: 6) {
                                TransactionRow(transaction: t)
                                Text(s.reasons.joined(separator: " · ")).font(.caption2).foregroundStyle(Theme.textSecondary)
                                HStack {
                                    Button("כן, זה התשלום") { model.confirmMatch(transactionID: t.id, eventID: event.id); model.show("קושר לאירוע") }
                                        .buttonStyle(.borderedProminent).tint(Theme.actual)
                                    Button("לא קשור") { model.rejectMatch(transactionID: t.id, eventID: event.id) }
                                        .buttonStyle(.bordered)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                } header: {
                    Text("הכנסות שאולי שייכות לאירוע")
                } footer: {
                    Text("שום דבר לא מקושר בלי אישור שלך.")
                }
            }
            if (event.expectedIncome ?? 0) == 0 && linked.filter({ $0.kind == .income }).isEmpty {
                Section {
                    if event.isIncomeEvent == false {
                        Button("זה כן אירוע בתשלום") { model.markAwaitingPayment(event.id, expected: nil) }
                    } else {
                        Button { recording = .income } label: { Label("שילמו לי על האירוע", systemImage: "checkmark.circle") }
                        Button("לא אירוע בתשלום") { model.markNotIncomeEvent(event.id) }.foregroundStyle(Theme.neutral)
                    }
                } header: { Text("תשלום") }
            }

            Section("פעולות") {
                if (event.expectedIncome ?? 0) > 0 && status != .paid {
                    Button { recording = .income } label: { Label("רישום תשלום שהתקבל", systemImage: "checkmark.circle") }
                }
                if (event.expectedIncome ?? 0) > 0 && debt == nil && fin.outstandingIncome > 0 {
                    Button { creatingDebt = true } label: { Label("פתיחת חוב לגבייה (עם תזכורות)", systemImage: "person.badge.clock") }
                }
                Button { recording = .expense } label: { Label("רישום הוצאה לאירוע", systemImage: "arrow.up.right") }
                Button { Task { await exportToCalendar(event) } } label: {
                    Label(event.calendarEventIdentifier == nil ? "הוספה ליומן האייפון" : "עדכון ביומן האייפון", systemImage: "calendar.badge.plus")
                }
                if let debt {
                    NavigationLink { DebtDetailView(debtID: debt.id) } label: { Label("מעבר לחוב: \(debt.title)", systemImage: "person.2") }
                }
            }

            Section("תנועות מקושרות") {
                if linked.isEmpty { Text("עדיין לא נרשמו תשלומים לאירוע.").foregroundStyle(Theme.textSecondary) }
                ForEach(linked) { t in
                    Button { openTransaction = t } label: { TransactionRow(transaction: t) }.buttonStyle(.plain)
                }
            }

            if !event.notes.isEmpty {
                Section("הערות") { Text(event.notes) }
            }
        }
        .navigationTitle("אירוע")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("עריכה") { editing = true } } }
        .sheet(isPresented: $editing) { EventEditor(event: event, date: event.date) }
        .sheet(item: $recording) { kind in
            EventPaymentSheet(event: event, kind: kind, suggested: kind == .income ? (debt.map { model.debtBalance($0).remaining } ?? fin.outstandingIncome) : fin.outstandingExpense)
        }
        .sheet(isPresented: $creatingDebt) { CreateReceivableSheet(event: event) }
        .sheet(item: $openTransaction) { TransactionEditor(existing: $0) }
        .alert("יומן", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("אישור", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func exportToCalendar(_ event: FinanceEvent) async {
        if calendar.status == .notDetermined { _ = await calendar.requestWriteOnlyAccess() }
        guard calendar.canWrite else { message = "אין הרשאה לכתוב ליומן. אפשר לאשר בהגדרות האייפון ← פרטיות ← יומנים."; return }
        do {
            let id = try calendar.export(event)
            if !id.isEmpty { model.setCalendarIdentifier(id, for: event.id) }
            model.show("נשמר ביומן האייפון")
        } catch {
            message = "השמירה ביומן נכשלה."
        }
    }
}

struct EventPaymentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let event: FinanceEvent
    let kind: TransactionKind
    let suggested: Decimal

    @State private var amountText = ""
    @State private var accountID: UUID?
    @State private var date = LocalDate.today()
    @State private var method: PaymentMethod? = .bit
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyField(title: "סכום", text: $amountText, large: true)
                    AccountPicker(title: kind == .income ? "לאיזה חשבון נכנס" : "מאיזה חשבון יצא", selection: $accountID)
                    DatePicker("תאריך", selection: $date.asDate, displayedComponents: .date)
                    Picker("אמצעי תשלום", selection: $method) {
                        Text("לא צוין").tag(PaymentMethod?.none)
                        ForEach(PaymentMethod.allCases, id: \.self) { Text($0.hebrewName).tag(Optional($0)) }
                    }
                } footer: {
                    Text(kind == .income ? "הסכום ייכנס ליתרה בפועל ויקטין את מה שנותר לגבייה." : "ההוצאה תירשם ותקושר לאירוע.")
                }
            }
            .navigationTitle(kind == .income ? "תשלום שהתקבל" : "הוצאה לאירוע")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("רישום", action: save).fontWeight(.semibold) }
            }
            .alert("לא ניתן לרשום", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("הבנתי", role: .cancel) {}
            } message: { Text(error ?? "") }
            .onAppear {
                amountText = suggested > 0 ? suggested.editingText : ""
                accountID = model.defaultAccountID
                if kind == .expense { method = nil }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let amount = Decimal.parseMoney(amountText)?.magnitudeValue, amount > 0 else { error = ValidationError.nonPositiveAmount.hebrewMessage; return }
        guard let accountID else { error = ValidationError.unknownAccount.hebrewMessage; return }
        do {
            try model.recordEventPayment(eventID: event.id, kind: kind, amount: amount, accountID: accountID, date: date, method: method)
            model.show("נרשם")
            dismiss()
        } catch {
            self.error = hebrewMessage(for: error)
        }
    }
}

struct CreateReceivableSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let event: FinanceEvent
    @State private var contactID: UUID?
    @State private var due = LocalDate.today()
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ContactPicker(title: "מי צריך לשלם", selection: $contactID, allowNone: false)
                    DatePicker("מועד לתשלום", selection: $due.asDate, displayedComponents: .date)
                } footer: {
                    Text("החוב יופיע במסך החובות, עם תזכורת אם יעבור מועדו. בתחזית ייספר החוב במקום ההכנסה הצפויה של האירוע — לא פעמיים.")
                }
            }
            .navigationTitle("פתיחת חוב לגבייה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("יצירה") {
                        guard let contactID else { error = "יש לבחור איש קשר."; return }
                        do { try model.createReceivable(for: event.id, contactID: contactID, dueDate: due); model.show("החוב נוצר"); dismiss() }
                        catch { self.error = hebrewMessage(for: error) }
                    }
                }
            }
            .alert("שגיאה", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("הבנתי", role: .cancel) {}
            } message: { Text(error ?? "") }
            .onAppear { contactID = event.contactID; due = max(event.date, model.today) }
        }
    }
}
