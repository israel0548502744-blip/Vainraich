import SwiftUI
import FinanceCore

struct DebtsView: View {
    @Environment(AppModel.self) private var model
    @State private var direction: DebtDirection = .receivable
    @State private var showClosed = false
    @State private var adding = false

    var body: some View {
        let all = model.data.debts.filter { $0.direction == direction }.map { model.debtBalance($0) }
        let open = all.filter(\.isOpen).sorted { ($0.isOverdue ? 0 : 1, $0.debt.dueDate ?? .init(year: 9999, month: 1, day: 1)) < ($1.isOverdue ? 0 : 1, $1.debt.dueDate ?? .init(year: 9999, month: 1, day: 1)) }
        let closed = all.filter { !$0.isOpen }.sorted { $0.debt.createdAt > $1.debt.createdAt }
        List {
            if model.mode == .demo { DemoBanner().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            Section {
                Picker("כיוון", selection: $direction) {
                    Text("חייבים לי").tag(DebtDirection.receivable)
                    Text("אני חייב").tag(DebtDirection.payable)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if !all.isEmpty {
                Section {
                    summary(open: open)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            if !open.isEmpty {
                Section("פתוחים") {
                    ForEach(open, id: \.debt.id) { b in
                        NavigationLink { DebtDetailView(debtID: b.debt.id) } label: { DebtRow(balance: b) }
                    }
                }
            }
            if !closed.isEmpty {
                Section {
                    DisclosureGroup("סגורים (\(closed.count))", isExpanded: $showClosed) {
                        ForEach(closed, id: \.debt.id) { b in
                            NavigationLink { DebtDetailView(debtID: b.debt.id) } label: { DebtRow(balance: b) }
                        }
                    }
                }
            }
            if !model.data.contacts.isEmpty {
                Section("לפי אדם") {
                    NavigationLink { ContactsListView() } label: { Label("היסטוריית תשלומים לכל איש קשר", systemImage: "person.crop.rectangle.stack") }
                }
            }
        }
        .overlay {
            if all.isEmpty {
                EmptyStateView(
                    icon: direction == .receivable ? "person.badge.clock" : "hand.raised",
                    title: direction == .receivable ? "אף אחד לא חייב לך כסף" : "אין חובות פתוחים",
                    message: direction == .receivable ? "רשום כאן כסף שמגיע לך — הלוואות, תשלומים על עבודות — עם תשלומים חלקיים ותזכורות." : "רשום כאן כסף שאתה צריך להחזיר, כדי שייכנס לתחזית ולתזכורות.",
                    actionTitle: "הוספת חוב") { adding = true }
                    .padding(.top, 120)
            }
        }
        .navigationTitle("חובות")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("חוב חדש") } }
        .sheet(isPresented: $adding) { DebtEditor(debt: nil, direction: direction) }
    }

    private func summary(open: [DebtBalance]) -> some View {
        let total = open.reduce(Decimal(0)) { $0 + $1.remaining }
        let overdue = open.filter(\.isOverdue).reduce(Decimal(0)) { $0 + $1.remaining }
        let color = direction == .receivable ? Theme.receivable : Theme.expected
        return VStack(alignment: .leading, spacing: 8) {
            Text(direction == .receivable ? "סה״כ מגיע לי" : "סה״כ אני חייב").font(.subheadline).foregroundStyle(Theme.textSecondary)
            AmountText(amount: total, font: Theme.amountFont(.title), color: color)
            HStack(spacing: 8) {
                StatusBadge(text: "\(open.count) פתוחים", color: color)
                if overdue > 0 { StatusBadge(text: "באיחור \(overdue.ils)", color: Theme.liability, icon: "exclamationmark.circle") }
                if direction == .receivable, let rate = DebtCalculator.collectionRate(model.data, range: nil) {
                    StatusBadge(text: "נגבה \(Int((rate * 100).rounded()))%", color: Theme.actual)
                }
            }
            if direction == .receivable {
                Text("כסף שחייבים לך לא נספר ככסף זמין עד שהוא מתקבל בפועל.").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }
}

struct DebtRow: View {
    @Environment(AppModel.self) private var model
    let balance: DebtBalance

    var body: some View {
        let d = balance.debt
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.data.contact(d.contactID)?.name ?? "").font(.body.weight(.medium))
                    Text(d.title).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    AmountText(amount: balance.isOpen ? balance.remaining : d.originalAmount, font: .body.weight(.semibold).monospacedDigit())
                    if balance.isOverdue {
                        StatusBadge(text: "באיחור", color: Theme.liability)
                    } else if let due = d.dueDate, balance.isOpen {
                        Text("עד \(due.short)").font(.caption2).foregroundStyle(Theme.textSecondary)
                    } else {
                        StatusBadge(text: balance.status.hebrewName, color: balance.status.color)
                    }
                }
            }
            if balance.paid > 0 && balance.isOpen {
                ProgressView(value: balance.progress)
                    .tint(Theme.actual)
                Text("שולם \(balance.paid.ils) מתוך \(d.originalAmount.ils)").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct DebtDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let debtID: UUID
    @State private var paying = false
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        if let debt = model.data.debt(debtID) {
            content(debt)
        } else {
            ContentUnavailableView("החוב נמחק", systemImage: "person.badge.minus")
        }
    }

    private func content(_ debt: Debt) -> some View {
        let b = model.debtBalance(debt)
        let payments = model.data.payments(for: debt.id).reversed()
        let contact = model.data.contact(debt.contactID)
        return List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(debt.direction == .receivable ? "\(contact?.name ?? "") חייב/ת לך" : "אתה חייב ל\(contact?.name ?? "")")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    AmountText(amount: b.remaining, font: Theme.amountFont(.largeTitle), color: debt.direction == .receivable ? Theme.receivable : Theme.expected)
                    ProgressView(value: b.progress).tint(Theme.actual)
                    HStack {
                        Text("סכום מקורי \(debt.originalAmount.ils)")
                        Spacer()
                        Text("שולם \(b.paid.ils)")
                    }
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 8) {
                        StatusBadge(text: b.status.hebrewName, color: b.status.color)
                        if b.isOverdue { StatusBadge(text: "באיחור", color: Theme.liability, icon: "exclamationmark.circle") }
                    }
                }
                .padding(.vertical, 6)
            }
            Section("פרטים") {
                LabeledContent("סיבה", value: debt.title)
                LabeledContent("נוצר", value: debt.issuedDate.short)
                if let due = debt.dueDate { LabeledContent("מועד תשלום", value: due.short) }
                if let e = model.data.event(debt.eventID) {
                    NavigationLink { EventDetailView(eventID: e.id) } label: { LabeledContent("אירוע", value: e.title) }
                }
                if let c = contact {
                    NavigationLink { ContactDetailView(contactID: c.id) } label: { LabeledContent("איש קשר", value: c.name) }
                }
                if !debt.countsAsIncomeOrExpense {
                    Text("הלוואה — התשלומים לא נספרים כהכנסה/הוצאה בדוחות.").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                if !debt.notes.isEmpty { Text(debt.notes).font(.subheadline) }
            }
            if b.isOpen {
                Section {
                    Button { paying = true } label: {
                        Label(debt.direction == .receivable ? "רישום תשלום שהתקבל" : "רישום תשלום ששילמתי", systemImage: "plus.circle.fill")
                    }
                    Menu {
                        Button("סימון כנמחק (לא ייגבה)") { model.setClosedStatus(.writtenOff, for: debt.id) }
                        Button("ביטול החוב") { model.setClosedStatus(.cancelled, for: debt.id) }
                    } label: { Label("סגירה בלי תשלום", systemImage: "xmark.circle") }
                }
            } else if debt.closedStatus != nil {
                Section { Button("פתיחה מחדש") { model.setClosedStatus(nil, for: debt.id) } }
            }
            Section("היסטוריית תשלומים") {
                if payments.isEmpty { Text("עדיין לא נרשמו תשלומים.").foregroundStyle(Theme.textSecondary) }
                ForEach(Array(payments)) { p in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.date.short)
                            if let t = model.data.transactions.first(where: { $0.id == p.transactionID }), let a = model.data.account(t.accountID) {
                                Text(a.name).font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer()
                        AmountText(amount: p.amount, font: .body.weight(.semibold).monospacedDigit(), color: Theme.actual)
                    }
                    .swipeActions {
                        Button(role: .destructive) { model.deletePayment(p.id) } label: { Label("מחיקה", systemImage: "trash") }
                    }
                }
            }
            Section {
                Button("מחיקת החוב", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("מחיקת חוב לא מוחקת כסף שכבר נכנס או יצא מהחשבון.")
            }
        }
        .navigationTitle(debt.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("עריכה") { editing = true } } }
        .sheet(isPresented: $paying) { DebtPaymentSheet(debt: debt, remaining: b.remaining) }
        .sheet(isPresented: $editing) { DebtEditor(debt: debt, direction: debt.direction) }
        .confirmationDialog("למחוק את החוב?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("מחיקה", role: .destructive) { model.deleteDebt(debt.id); dismiss() }
        }
    }
}

struct DebtPaymentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let debt: Debt
    let remaining: Decimal
    @State private var amountText = ""
    @State private var accountID: UUID?
    @State private var date = LocalDate.today()
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyField(title: "סכום", text: $amountText, large: true)
                    HStack {
                        Text("נותר: \(remaining.ils)").font(.caption).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Button("כל היתרה") { amountText = remaining.editingText }.font(.caption)
                    }
                    AccountPicker(title: debt.direction == .receivable ? "לאיזה חשבון נכנס" : "מאיזה חשבון יצא", selection: $accountID)
                    DatePicker("תאריך", selection: $date.asDate, displayedComponents: .date)
                    TextField("הערה", text: $notes)
                } footer: {
                    Text("התשלום משנה את היתרה בפועל בחשבון שנבחר ומקטין את החוב. אפשר לרשום כמה תשלומים חלקיים.")
                }
            }
            .navigationTitle("רישום תשלום")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("רישום", action: save).fontWeight(.semibold) }
            }
            .alert("לא ניתן לרשום", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("הבנתי", role: .cancel) {}
            } message: { Text(error ?? "") }
            .onAppear { accountID = model.defaultAccountID }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let amount = Decimal.parseMoney(amountText)?.magnitudeValue, amount > 0 else { error = ValidationError.nonPositiveAmount.hebrewMessage; return }
        guard let accountID else { error = ValidationError.unknownAccount.hebrewMessage; return }
        do {
            try model.recordDebtPayment(debtID: debt.id, amount: amount, date: date, accountID: accountID, notes: notes)
            model.show("התשלום נרשם")
            dismiss()
        } catch {
            self.error = hebrewMessage(for: error)
        }
    }
}

struct DebtEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let debt: Debt?
    @State private var direction: DebtDirection
    @State private var contactID: UUID?
    @State private var title = ""
    @State private var amountText = ""
    @State private var issued = LocalDate.today()
    @State private var hasDue = true
    @State private var due = LocalDate.today().adding(days: 30)
    @State private var isLoan = false
    @State private var notes = ""
    @State private var alreadyPaidText = ""
    @State private var error: String?

    init(debt: Debt?, direction: DebtDirection) {
        self.debt = debt
        _direction = State(initialValue: debt?.direction ?? direction)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("כיוון", selection: $direction) {
                        Text("חייבים לי").tag(DebtDirection.receivable)
                        Text("אני חייב").tag(DebtDirection.payable)
                    }
                    .pickerStyle(.segmented)
                    .disabled(debt != nil)
                    ContactPicker(title: direction == .receivable ? "מי חייב" : "למי", selection: $contactID, allowNone: false)
                    TextField("על מה (למשל: צילום חתונה, הלוואה)", text: $title)
                    MoneyField(title: "סכום", text: $amountText, large: true)
                }
                Section {
                    DatePicker("נוצר בתאריך", selection: $issued.asDate, displayedComponents: .date)
                    Toggle("יש מועד לתשלום", isOn: $hasDue)
                    if hasDue { DatePicker("מועד", selection: $due.asDate, displayedComponents: .date) }
                    Toggle("זו הלוואה (לא הכנסה/הוצאה)", isOn: $isLoan)
                    TextField("הערות", text: $notes, axis: .vertical).lineLimit(1...4)
                } footer: {
                    Text("הלוואה לחבר או ממנו — ההחזר מגדיל את היתרה בפועל אבל לא נספר כהכנסה בדוחות. עבור תשלום על עבודה, השאר כבוי.")
                }
            }
            .navigationTitle(debt == nil ? "חוב חדש" : "עריכת חוב")
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
        guard let d = debt else { return }
        contactID = d.contactID
        title = d.title
        amountText = d.originalAmount.editingText
        issued = d.issuedDate
        hasDue = d.dueDate != nil
        if let dd = d.dueDate { due = dd }
        isLoan = !d.countsAsIncomeOrExpense
        notes = d.notes
    }

    private func save() {
        guard let contactID else { error = "יש לבחור איש קשר."; return }
        guard let amount = Decimal.parseMoney(amountText)?.magnitudeValue, amount > 0 else { error = ValidationError.nonPositiveAmount.hebrewMessage; return }
        var d = debt ?? Debt(direction: direction, contactID: contactID, title: title, originalAmount: amount)
        d.direction = direction
        d.contactID = contactID
        d.title = title
        d.originalAmount = amount
        d.issuedDate = issued
        d.dueDate = hasDue ? due : nil
        d.countsAsIncomeOrExpense = !isLoan
        d.notes = notes
        do {
            try model.save(d)
            model.show("נשמר")
            dismiss()
        } catch {
            self.error = hebrewMessage(for: error)
        }
    }
}

// MARK: - Contacts

struct ContactsListView: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false
    @State private var newName = ""

    var body: some View {
        List {
            ForEach(model.data.contacts.sorted { $0.name < $1.name }) { c in
                let open = model.data.debts.filter { $0.contactID == c.id }.map { model.debtBalance($0) }.filter(\.isOpen)
                let owedToMe = open.filter { $0.debt.direction == .receivable }.reduce(Decimal(0)) { $0 + $1.remaining }
                let iOwe = open.filter { $0.debt.direction == .payable }.reduce(Decimal(0)) { $0 + $1.remaining }
                NavigationLink { ContactDetailView(contactID: c.id) } label: {
                    HStack {
                        Text(c.name)
                        Spacer()
                        if owedToMe > 0 { AmountText(amount: owedToMe, font: .subheadline.monospacedDigit(), color: Theme.receivable) }
                        if iOwe > 0 { AmountText(amount: -iOwe, font: .subheadline.monospacedDigit(), color: Theme.expected) }
                    }
                }
                .swipeActions {
                    if !model.contactInUse(c.id) {
                        Button(role: .destructive) { model.deleteContact(c.id) } label: { Label("מחיקה", systemImage: "trash") }
                    }
                }
            }
        }
        .overlay {
            if model.data.contacts.isEmpty {
                EmptyStateView(icon: "person.crop.circle", title: "אין אנשי קשר", message: "אנשי קשר נוצרים כשמוסיפים חוב, אירוע או תנועה עם לקוח.")
            }
        }
        .navigationTitle("אנשי קשר")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { adding = true } label: { Image(systemName: "plus") } } }
        .alert("איש קשר חדש", isPresented: $adding) {
            TextField("שם", text: $newName)
            Button("הוספה") {
                let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty { model.addContact(Contact(name: n)) }
                newName = ""
            }
            Button("ביטול", role: .cancel) { newName = "" }
        }
    }
}

struct ContactDetailView: View {
    @Environment(AppModel.self) private var model
    let contactID: UUID
    @State private var openTransaction: FinanceTransaction?

    var body: some View {
        if let c = model.data.contact(contactID) {
            let debts = model.data.debts.filter { $0.contactID == c.id }.map { model.debtBalance($0) }
            let txs = model.data.transactions.filter { $0.contactID == c.id }.sorted { $0.date > $1.date }
            let events = model.data.events.filter { $0.contactID == c.id }.sorted { $0.date > $1.date }
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(c.name).font(.title2.weight(.semibold))
                        if let p = c.phone { Link(destination: URL(string: "tel:\(p.filter { $0.isNumber || $0 == "+" })")!) { Label(ltr(p), systemImage: "phone") } }
                        if let e = c.email { Label(e, systemImage: "envelope").font(.subheadline) }
                    }
                }
                Section("חובות") {
                    if debts.isEmpty { Text("אין חובות").foregroundStyle(Theme.textSecondary) }
                    ForEach(debts, id: \.debt.id) { b in
                        NavigationLink { DebtDetailView(debtID: b.debt.id) } label: { DebtRow(balance: b) }
                    }
                }
                if !events.isEmpty {
                    Section("אירועים") {
                        ForEach(events) { e in NavigationLink { EventDetailView(eventID: e.id) } label: { EventRow(event: e) } }
                    }
                }
                Section("היסטוריית תשלומים") {
                    if txs.isEmpty { Text("אין תנועות").foregroundStyle(Theme.textSecondary) }
                    ForEach(txs) { t in
                        Button { openTransaction = t } label: { TransactionRow(transaction: t) }.buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(c.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $openTransaction) { TransactionEditor(existing: $0) }
        } else {
            ContentUnavailableView("איש הקשר לא נמצא", systemImage: "person.slash")
        }
    }
}
