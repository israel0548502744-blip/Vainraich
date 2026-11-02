import SwiftUI
import FinanceCore

struct RecurringListView: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false
    @State private var editing: RecurringRule?

    var body: some View {
        List {
            let rules = model.data.recurringRules.sorted { $0.title < $1.title }
            if !rules.isEmpty {
                let monthlyOut = rules.filter { $0.isActive && $0.kind == .expense }.reduce(Decimal(0)) { $0 + monthlyEquivalent($1) }
                let monthlyIn = rules.filter { $0.isActive && $0.kind == .income }.reduce(Decimal(0)) { $0 + monthlyEquivalent($1) }
                Section {
                    HStack { Text("הוצאות קבועות בחודש (בערך)"); Spacer(); AmountText(amount: monthlyOut, color: Theme.liability) }
                    HStack { Text("הכנסות קבועות בחודש (בערך)"); Spacer(); AmountText(amount: monthlyIn, color: Theme.actual) }
                }
            }
            ForEach(rules) { r in
                Button { editing = r } label: {
                    HStack(spacing: 12) {
                        CategoryIcon(icon: model.data.category(r.categoryID)?.icon ?? r.kind.icon, color: r.isActive ? Theme.brand : Theme.neutral)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.title).foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                Text(Labels.frequency(r.frequency, interval: r.interval))
                                if let next = RecurrenceEngine.nextOccurrence(of: r, onOrAfter: model.today) {
                                    Text("· הבא: \(next.short)")
                                }
                                if !r.isActive { StatusBadge(text: "מושהה", color: Theme.neutral) }
                                if r.autoPost { StatusBadge(text: "אוטומטי", color: Theme.brand) }
                            }
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        AmountText(amount: r.kind == .income ? r.amount : -r.amount, font: .body.weight(.semibold).monospacedDigit(), colorBySign: r.kind == .income)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { model.deleteRule(r.id, removePendingOccurrences: true) } label: { Label("מחיקה", systemImage: "trash") }
                }
            }
        }
        .overlay {
            if model.data.recurringRules.isEmpty {
                EmptyStateView(icon: "repeat", title: "אין תשלומים קבועים",
                               message: "שכר דירה, מנויים, משכורת — הוסף אותם פעם אחת והם ייכנסו לתחזית בכל חודש, בלי כפילויות.",
                               actionTitle: "הוספת תשלום קבוע") { adding = true }
            }
        }
        .navigationTitle("תשלומים קבועים")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { adding = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $adding) { RecurringRuleEditor(rule: nil) }
        .sheet(item: $editing) { RecurringRuleEditor(rule: $0) }
    }

    private func monthlyEquivalent(_ r: RecurringRule) -> Decimal {
        let n = Decimal(r.interval)
        switch r.frequency {
        case .daily: return r.amount * 30 / n
        case .weekly: return r.amount * Decimal(r.weekdays.isEmpty ? 1 : r.weekdays.count) * 52 / 12 / n
        case .monthly: return r.amount / n
        case .yearly: return r.amount / 12 / n
        }
    }
}

struct RecurringRuleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let rule: RecurringRule?

    @State private var kind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var title = ""
    @State private var accountID: UUID?
    @State private var counterAccountID: UUID?
    @State private var categoryID: UUID?
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var interval = 1
    @State private var dayOfMonth = 1
    @State private var weekdays: Set<Int> = []
    @State private var start = LocalDate.today()
    @State private var endDate: LocalDate?
    @State private var autoPost = false
    @State private var isActive = true
    @State private var method: PaymentMethod?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("סוג", selection: $kind) {
                        Text("הוצאה").tag(TransactionKind.expense)
                        Text("הכנסה").tag(TransactionKind.income)
                        Text("העברה").tag(TransactionKind.transfer)
                    }
                    .pickerStyle(.segmented)
                    MoneyField(title: "סכום", text: $amountText, large: true)
                    TextField("תיאור (למשל: שכר דירה)", text: $title)
                    AccountPicker(title: kind == .transfer ? "מחשבון" : "חשבון", selection: $accountID)
                    if kind == .transfer {
                        AccountPicker(title: "לחשבון", selection: $counterAccountID, excluding: accountID)
                    } else {
                        CategoryPicker(kind: kind == .income ? .income : .expense, selection: $categoryID)
                    }
                    Picker("אמצעי תשלום", selection: $method) {
                        Text("לא צוין").tag(PaymentMethod?.none)
                        ForEach(PaymentMethod.allCases, id: \.self) { Text($0.hebrewName).tag(Optional($0)) }
                    }
                }
                Section("מתי") {
                    Picker("תדירות", selection: $frequency) {
                        Text("יומי").tag(RecurrenceFrequency.daily)
                        Text("שבועי").tag(RecurrenceFrequency.weekly)
                        Text("חודשי").tag(RecurrenceFrequency.monthly)
                        Text("שנתי").tag(RecurrenceFrequency.yearly)
                    }
                    Stepper("כל \(interval) \(frequency == .daily ? "ימים" : frequency == .weekly ? "שבועות" : frequency == .monthly ? "חודשים" : "שנים")", value: $interval, in: 1...24)
                    if frequency == .monthly {
                        Stepper("ביום \(dayOfMonth) בחודש\(dayOfMonth >= 29 ? " (או האחרון)" : "")", value: $dayOfMonth, in: 1...31)
                    }
                    if frequency == .weekly {
                        HStack {
                            ForEach(1...7, id: \.self) { d in
                                Button(Labels.weekdayShort[d - 1]) {
                                    if weekdays.contains(d) { weekdays.remove(d) } else { weekdays.insert(d) }
                                }
                                .buttonStyle(.bordered)
                                .tint(weekdays.contains(d) ? Theme.brand : Theme.neutral)
                                .font(.caption)
                            }
                        }
                    }
                    DatePicker("החל מ־", selection: $start.asDate, displayedComponents: .date)
                    Toggle("עד תאריך", isOn: Binding(get: { endDate != nil }, set: { endDate = $0 ? start.adding(years: 1) : nil }))
                    if endDate != nil { DatePicker("תאריך סיום", selection: $endDate.asDate(default: start), displayedComponents: .date) }
                }
                Section {
                    Toggle("לרשום אוטומטית כבוצע", isOn: $autoPost)
                    Toggle("פעיל", isOn: $isActive)
                } footer: {
                    Text("כל מופע נרשם פעם אחת בלבד. מופעים שכבר נרשמו לא ייווצרו שוב גם אם תשנה את ההגדרות.")
                }
                if rule != nil {
                    Section {
                        Button("מחיקת התשלום הקבוע", role: .destructive) {
                            if let r = rule { model.deleteRule(r.id, removePendingOccurrences: true) }
                            dismiss()
                        }
                    } footer: { Text("תנועות שכבר בוצעו יישארו בהיסטוריה. מופעים ממתינים יימחקו.") }
                }
            }
            .navigationTitle(rule == nil ? "תשלום קבוע חדש" : "עריכת תשלום קבוע")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("שמירה", action: save).fontWeight(.semibold) }
            }
            .alert("לא ניתן לשמור", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("הבנתי", role: .cancel) {}
            } message: { Text(error ?? "") }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let r = rule else {
            accountID = model.defaultAccountID
            dayOfMonth = model.today.day
            return
        }
        kind = r.kind
        amountText = r.amount.editingText
        title = r.title
        accountID = r.accountID
        counterAccountID = r.counterAccountID
        categoryID = r.categoryID
        frequency = r.frequency
        interval = r.interval
        dayOfMonth = r.dayOfMonth ?? r.startDate.day
        weekdays = Set(r.weekdays)
        start = r.startDate
        endDate = r.endDate
        autoPost = r.autoPost
        isActive = r.isActive
        method = r.paymentMethod
    }

    private func save() {
        guard let amount = Decimal.parseMoney(amountText)?.magnitudeValue, amount > 0 else { error = ValidationError.nonPositiveAmount.hebrewMessage; return }
        guard let accountID else { error = ValidationError.unknownAccount.hebrewMessage; return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = ValidationError.emptyTitle.hebrewMessage; return }
        var r = rule ?? RecurringRule(kind: kind, amount: amount, accountID: accountID, title: name, frequency: frequency, startDate: start)
        r.kind = kind
        r.amount = amount
        r.title = name
        r.accountID = accountID
        r.counterAccountID = kind == .transfer ? counterAccountID : nil
        r.categoryID = kind == .transfer ? nil : categoryID
        r.frequency = frequency
        r.interval = interval
        r.dayOfMonth = frequency == .monthly ? dayOfMonth : nil
        r.weekdays = frequency == .weekly ? weekdays.sorted() : []
        r.startDate = start
        r.endDate = endDate
        r.autoPost = autoPost
        r.isActive = isActive
        r.paymentMethod = method
        do {
            try model.save(r)
            model.show("נשמר")
            dismiss()
        } catch {
            self.error = hebrewMessage(for: error)
        }
    }
}
