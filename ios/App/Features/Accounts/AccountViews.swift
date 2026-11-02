import SwiftUI
import FinanceCore

struct AccountsView: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false
    @State private var showInactive = false

    var body: some View {
        let balances = model.balances
        let active = model.activeAccounts
        let s = model.summary(for: .day(model.today))
        List {
            if model.mode == .demo { DemoBanner().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            if !active.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        mini("זמין", s.available, Theme.actual)
                        mini("אשראי", -s.creditCardLiability, Theme.liability)
                        mini("חיסכון", s.savings, Theme.token("indigo"))
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            ForEach(AccountType.allCases, id: \.self) { type in
                let list = active.filter { $0.type == type }
                if !list.isEmpty {
                    Section(type.hebrewName) {
                        ForEach(list) { a in
                            NavigationLink { AccountDetailView(accountID: a.id) } label: { AccountRow(account: a, balance: balances[a.id] ?? 0) }
                        }
                    }
                }
            }
            let inactive = model.data.accounts.filter { !$0.isActive }
            if !inactive.isEmpty {
                Section {
                    DisclosureGroup("חשבונות לא פעילים (\(inactive.count))", isExpanded: $showInactive) {
                        ForEach(inactive) { a in
                            NavigationLink { AccountDetailView(accountID: a.id) } label: { AccountRow(account: a, balance: balances[a.id] ?? 0) }
                        }
                    }
                }
            }
        }
        .overlay {
            if model.data.accounts.isEmpty {
                EmptyStateView(icon: "building.columns", title: "אין חשבונות",
                               message: "הוסף חשבון בנק, מזומן, ביט או כרטיס אשראי עם היתרה הנוכחית.",
                               actionTitle: "הוספת חשבון") { adding = true }
            }
        }
        .navigationTitle("חשבונות")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("חשבון חדש") } }
        .sheet(isPresented: $adding) { AccountEditor(account: nil) }
    }

    private func mini(_ t: String, _ a: Decimal, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.caption).foregroundStyle(Theme.textSecondary)
            AmountText(amount: a, font: .subheadline.weight(.semibold).monospacedDigit(), color: c)
        }
        .card(padding: 12)
    }
}

struct AccountRow: View {
    let account: Account
    let balance: Decimal

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(icon: account.type.icon, color: account.type.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                HStack(spacing: 6) {
                    if let i = account.institution, !i.isEmpty { Text(i) }
                    if account.type == .creditCard, let d = account.billingDay { Text("חיוב ב־\(d) לחודש") }
                    if !account.includeInAvailable && account.type != .creditCard { Text("לא נספר בזמין") }
                }
                .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            AmountText(amount: balance, font: .body.weight(.semibold).monospacedDigit(), colorBySign: account.type == .creditCard)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AccountDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let accountID: UUID
    @State private var editing = false
    @State private var updatingBalance = false
    @State private var openTransaction: FinanceTransaction?
    @State private var importing = false
    @State private var confirmDelete = false

    var body: some View {
        if let account = model.data.account(accountID) {
            let balance = model.balance(of: account.id)
            let txs = model.data.transactions.filter { $0.accountID == account.id || $0.counterAccountID == account.id }.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(account.type.hebrewName, systemImage: account.type.icon).font(.subheadline).foregroundStyle(account.type.color)
                        AmountText(amount: balance, font: Theme.amountFont(.largeTitle), colorBySign: account.type == .creditCard)
                        if account.type == .creditCard {
                            Text(balance < 0 ? "חוב בכרטיס. ייגבה מ\(model.data.account(account.paymentAccountID)?.name ?? "חשבון הבנק") ביום החיוב." : "אין חוב פתוח בכרטיס.")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                            if let limit = account.creditLimit, limit > 0 {
                                ProgressView(value: min(1, (-balance).doubleValue / limit.doubleValue)) { Text("ניצול מסגרת").font(.caption) }
                                    .tint(Theme.liability)
                            }
                        }
                        if let s = account.lastSyncedAt {
                            Text("עודכן ממסמך: \(LocalDate(s).short)").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    Button { updatingBalance = true } label: { Label("עדכון יתרה לפי הבנק", systemImage: "slider.horizontal.3") }
                    Button { importing = true } label: { Label("ייבוא תנועות ממסמך", systemImage: "doc.viewfinder") }
                }
                Section("תנועות (\(txs.count))") {
                    if txs.isEmpty { Text("אין תנועות בחשבון").foregroundStyle(Theme.textSecondary) }
                    ForEach(txs.prefix(200)) { t in
                        Button { openTransaction = t } label: { TransactionRow(transaction: t) }.buttonStyle(.plain)
                    }
                }
                if !account.notes.isEmpty { Section("הערות") { Text(account.notes) } }
                Section {
                    Button(model.accountHasTransactions(account.id) ? "הפיכה ללא פעיל" : "מחיקת החשבון", role: .destructive) { confirmDelete = true }
                } footer: {
                    if model.accountHasTransactions(account.id) { Text("לחשבון יש היסטוריה, לכן הוא יסומן כלא פעיל ולא יימחק.") }
                }
            }
            .navigationTitle(account.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("עריכה") { editing = true } } }
            .sheet(isPresented: $editing) { AccountEditor(account: account) }
            .sheet(isPresented: $updatingBalance) { BalanceUpdateSheet(account: account, current: balance) }
            .sheet(item: $openTransaction) { TransactionEditor(existing: $0) }
            .sheet(isPresented: $importing) { NavigationStack { DocumentImportView(preselectedAccountID: account.id) } }
            .confirmationDialog("להמשיך?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(model.accountHasTransactions(account.id) ? "סימון כלא פעיל" : "מחיקה", role: .destructive) {
                    let deleting = !model.accountHasTransactions(account.id)
                    model.deleteOrDeactivate(account: account.id)
                    if deleting { dismiss() }
                }
            }
        } else {
            ContentUnavailableView("החשבון נמחק", systemImage: "building.columns")
        }
    }
}

struct BalanceUpdateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let account: Account
    let current: Decimal
    @State private var text = ""
    @State private var date = LocalDate.today()
    @State private var isDebt = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("יתרה באפליקציה", value: current.ils)
                    MoneyField(title: account.type == .creditCard ? "חוב בכרטיס לפי החברה" : "יתרה אמיתית לפי הבנק", text: $text, large: true)
                    if account.type != .creditCard { Toggle("היתרה במינוס", isOn: $isDebt) }
                    DatePicker("נכון לתאריך", selection: $date.asDate, displayedComponents: .date)
                } footer: {
                    Text("ההפרש יירשם כ\"עדכון יתרה\" — לא כהכנסה ולא כהוצאה — כדי שהדוחות יישארו נכונים.")
                }
            }
            .navigationTitle("עדכון יתרה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("עדכון") {
                        guard let v = Decimal.parseMoney(text)?.magnitudeValue else { error = "יש להזין סכום."; return }
                        let target = account.type == .creditCard ? -v : (isDebt ? -v : v)
                        do { try model.setBalance(of: account.id, to: target, on: date); model.show("היתרה עודכנה"); dismiss() }
                        catch { self.error = hebrewMessage(for: error) }
                    }
                }
            }
            .alert("שגיאה", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("הבנתי", role: .cancel) {}
            } message: { Text(error ?? "") }
            .onAppear { text = current.magnitudeValue.editingText; isDebt = current < 0 }
        }
        .presentationDetents([.medium, .large])
    }
}

struct AccountEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let account: Account?

    @State private var name = ""
    @State private var type: AccountType = .bank
    @State private var institution = ""
    @State private var balanceText = ""
    @State private var negative = false
    @State private var includeInAvailable = true
    @State private var limitText = ""
    @State private var billingDay = 10
    @State private var paymentAccountID: UUID?
    @State private var isActive = true
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("סוג", selection: $type) {
                        ForEach(AccountType.allCases, id: \.self) { Label($0.hebrewName, systemImage: $0.icon).tag($0) }
                    }
                    .onChange(of: type) { _, t in if account == nil { includeInAvailable = t.defaultIncludeInAvailable } }
                    TextField("שם (למשל: עו״ש לאומי)", text: $name)
                    if type == .bank || type == .creditCard || type == .savings {
                        TextField(type == .creditCard ? "חברת האשראי" : "בנק / מוסד", text: $institution)
                    }
                }
                if account == nil {
                    Section {
                        MoneyField(title: type == .creditCard ? "חוב נוכחי בכרטיס" : "יתרה נוכחית", text: $balanceText, large: true)
                        if type != .creditCard { Toggle("היתרה במינוס", isOn: $negative) }
                    } footer: {
                        Text(type == .creditCard ? "סכום החיובים שעוד לא ירדו מהבנק. השאר 0 אם אין." : "היתרה כפי שהיא היום. מעכשיו היא תתעדכן לפי התנועות.")
                    }
                }
                if type == .creditCard {
                    Section("כרטיס אשראי") {
                        Stepper("יום חיוב: \(billingDay) בחודש", value: $billingDay, in: 1...31)
                        AccountPicker(title: "משולם מחשבון", selection: $paymentAccountID, excluding: account?.id, allowNone: true)
                        MoneyField(title: "מסגרת אשראי (לא חובה)", text: $limitText)
                    }
                }
                Section {
                    Toggle("נספר בכסף הזמין", isOn: $includeInAvailable).disabled(type == .creditCard)
                    if account != nil { Toggle("חשבון פעיל", isOn: $isActive) }
                    TextField("הערות", text: $notes, axis: .vertical).lineLimit(1...3)
                } footer: {
                    Text("חיסכון ופיקדונות לא נספרים ככסף זמין כברירת מחדל.")
                }
            }
            .navigationTitle(account == nil ? "חשבון חדש" : "עריכת חשבון")
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
        guard let a = account else {
            paymentAccountID = model.activeAccounts.first { $0.type == .bank }?.id
            return
        }
        name = a.name
        type = a.type
        institution = a.institution ?? ""
        includeInAvailable = a.includeInAvailable
        limitText = a.creditLimit?.editingText ?? ""
        billingDay = a.billingDay ?? 10
        paymentAccountID = a.paymentAccountID
        isActive = a.isActive
        notes = a.notes
    }

    private func save() {
        var a = account ?? Account(name: name, type: type, openingDate: model.today)
        a.name = name
        a.type = type
        a.institution = institution.isEmpty ? nil : institution
        a.includeInAvailable = type == .creditCard ? false : includeInAvailable
        a.creditLimit = Decimal.parseMoney(limitText)?.magnitudeValue
        a.billingDay = type == .creditCard ? billingDay : nil
        a.paymentAccountID = type == .creditCard ? paymentAccountID : nil
        a.isActive = isActive
        a.notes = notes
        if account == nil {
            let v = Decimal.parseMoney(balanceText)?.magnitudeValue ?? 0
            a.openingBalance = (type == .creditCard || negative) ? -v : v
            a.openingDate = model.today
        }
        do {
            try model.save(a)
            model.show("החשבון נשמר")
            dismiss()
        } catch {
            self.error = hebrewMessage(for: error)
        }
    }
}

struct CategoriesView: View {
    @Environment(AppModel.self) private var model
    @State private var adding: FinanceCategory.Kind?
    @State private var newName = ""

    var body: some View {
        List {
            ForEach([FinanceCategory.Kind.expense, .income], id: \.self) { kind in
                Section(kind == .expense ? "הוצאות" : "הכנסות") {
                    ForEach(model.data.categories.filter { $0.kind == kind }) { c in
                        HStack {
                            CategoryIcon(icon: c.icon, color: Theme.token(c.colorToken), size: 30)
                            Text(c.name).foregroundStyle(c.isArchived ? Theme.textSecondary : .primary)
                            Spacer()
                            Button(c.isArchived ? "שחזור" : "הסתרה") { var x = c; x.isArchived.toggle(); model.save(x) }
                                .font(.caption).buttonStyle(.bordered)
                        }
                    }
                    Button { adding = kind } label: { Label("קטגוריה חדשה", systemImage: "plus") }
                }
            }
        }
        .navigationTitle("קטגוריות")
        .alert("קטגוריה חדשה", isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) {
            TextField("שם", text: $newName)
            Button("הוספה") {
                let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let k = adding, !n.isEmpty { model.save(FinanceCategory(name: n, kind: k, icon: "tag", colorToken: "teal")) }
                newName = ""
            }
            Button("ביטול", role: .cancel) { newName = "" }
        }
    }
}
