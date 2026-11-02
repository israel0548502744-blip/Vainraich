import SwiftUI
import Observation
import FinanceCore

/// Single source of truth for the app. All mutations go through here so that validation,
/// saving and notification rescheduling happen in one place.
@MainActor
@Observable
final class AppModel {
    enum Mode: String { case personal, demo }

    private(set) var data: FinanceData
    private(set) var mode: Mode
    private(set) var today: LocalDate = .today()
    var errorMessage: String?
    var toast: String?

    @ObservationIgnored private let store: FinanceFileStore
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var lastLoadedModification: Date?
    @ObservationIgnored var onDataChanged: (() -> Void)?

    nonisolated static var personalFileURL: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Finance", isDirectory: true).appendingPathComponent("finance.json")
    }

    init(store: FinanceFileStore = FinanceFileStore(url: AppModel.personalFileURL), startInDemo: Bool = false) {
        self.store = store
        self.data = FinanceData()
        self.mode = .personal
        if startInDemo {
            mode = .demo
            data = DemoData.make(today: today)
        } else {
            loadPersonal()
        }
    }

    // MARK: - Loading & saving

    var hasPersonalData: Bool { store.exists() }

    private func loadPersonal() {
        guard store.exists() else { data = FinanceData(); return }
        do {
            data = try store.load()
            lastLoadedModification = modificationDate()
            materializeRecurring()
        } catch {
            errorMessage = "לא הצלחתי לקרוא את קובץ הנתונים. הקובץ לא נמחק — אפשר לשחזר מגיבוי בהגדרות."
            data = FinanceData()
        }
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: store.url.path))?[.modificationDate] as? Date
    }

    /// Picks up changes written by Siri/Shortcuts while the app was in the background.
    func reloadIfChangedExternally() {
        guard mode == .personal, let m = modificationDate(), m != lastLoadedModification, saveTask == nil else { return }
        loadPersonal()
    }

    private func changed() {
        onDataChanged?()
        guard mode == .personal else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    func persistNow() {
        saveTask = nil
        guard mode == .personal else { return }
        do {
            try store.save(data)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: store.url.path)
            lastLoadedModification = modificationDate()
        } catch {
            errorMessage = "השמירה נכשלה: \(error.localizedDescription)"
        }
    }

    func refreshDay() {
        let now = LocalDate.today()
        if now != today { today = now }
        materializeRecurring()
    }

    /// Records every due recurring occurrence exactly once (pending, or completed when auto-post is on).
    func materializeRecurring() {
        let created = RecurrenceEngine.materialize(rules: data.recurringRules, through: today, existing: data.transactions)
        guard !created.isEmpty else { return }
        data.transactions.append(contentsOf: created)
        changed()
    }

    // MARK: - Modes

    func enterDemo() {
        persistNow()
        mode = .demo
        data = DemoData.make(today: today)
        onDataChanged?()
    }

    func exitDemo() {
        mode = .personal
        loadPersonal()
        onDataChanged?()
    }

    func eraseAllPersonalData() {
        saveTask?.cancel()
        saveTask = nil
        try? store.delete()
        AttachmentStore.deleteAll()
        data = FinanceData()
        mode = .personal
        onDataChanged?()
    }

    func replaceAll(with backup: FinanceData) {
        var d = backup
        d.isDemo = false
        data = d
        mode = .personal
        changed()
        persistNow()
    }

    func backupData() throws -> Data { try FinanceFileStore.encode(data) }

    // MARK: - Derived

    var activeAccounts: [Account] { data.accounts.filter(\.isActive).sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) } }
    var balances: [UUID: Decimal] { Ledger.balances(accounts: data.accounts, transactions: data.transactions) }
    func balance(of id: UUID) -> Decimal { data.account(id).map { Ledger.balance(of: $0, transactions: data.transactions) } ?? 0 }
    func summary(for period: DateRange) -> FinancialSummary { SummaryCalculator.make(data: data, period: period, today: today) }
    func forecast(_ range: DateRange) -> Forecast { ForecastEngine.make(data: data, range: range, today: today) }
    func debtBalance(_ d: Debt) -> DebtBalance { DebtCalculator.balance(of: d, payments: data.debtPayments, today: today) }
    var defaultAccountID: UUID? { activeAccounts.first { $0.includeInAvailable }?.id ?? activeAccounts.first?.id }

    func show(_ message: String) {
        toast = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if self?.toast == message { self?.toast = nil }
        }
    }

    // MARK: - Transactions

    func save(_ transaction: FinanceTransaction) throws {
        var t = transaction
        t.title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
        t.amount = t.amount.rounded(scale: 2)
        if t.kind == .transfer { t.categoryID = nil } else { t.counterAccountID = nil }
        try t.validate(in: data)
        t.updatedAt = Date()
        if let i = data.transactions.firstIndex(where: { $0.id == t.id }) {
            data.transactions[i] = t
            // Keep a linked debt payment's amount/date in sync.
            if let p = data.debtPayments.firstIndex(where: { $0.transactionID == t.id }) {
                data.debtPayments[p].amount = t.amount
                data.debtPayments[p].date = t.date
            }
        } else {
            data.transactions.append(t)
        }
        changed()
    }

    func deleteTransaction(_ id: UUID) {
        if let t = data.transactions.first(where: { $0.id == id }), let file = t.attachmentFileName {
            AttachmentStore.delete(file)
        }
        data.transactions.removeAll { $0.id == id }
        data.debtPayments.removeAll { $0.transactionID == id }
        changed()
    }

    func confirm(_ id: UUID, on date: LocalDate? = nil) {
        guard let i = data.transactions.firstIndex(where: { $0.id == id }) else { return }
        data.transactions[i].status = .completed
        if let date { data.transactions[i].date = date }
        data.transactions[i].updatedAt = Date()
        changed()
    }

    func cancel(_ id: UUID) {
        guard let i = data.transactions.firstIndex(where: { $0.id == id }) else { return }
        data.transactions[i].status = .cancelled
        changed()
    }

    // MARK: - Accounts

    func save(_ account: Account) throws {
        var a = account
        a.name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
        try a.validate()
        if a.type != .creditCard { a.billingDay = nil; a.paymentAccountID = nil; a.creditLimit = nil }
        if let i = data.accounts.firstIndex(where: { $0.id == a.id }) {
            data.accounts[i] = a
        } else {
            a.sortOrder = (data.accounts.map(\.sortOrder).max() ?? -1) + 1
            data.accounts.append(a)
        }
        changed()
    }

    func accountHasTransactions(_ id: UUID) -> Bool {
        data.transactions.contains { $0.accountID == id || $0.counterAccountID == id } || data.recurringRules.contains { $0.accountID == id || $0.counterAccountID == id }
    }

    /// Deletes an account without history; otherwise marks it inactive (history is kept).
    func deleteOrDeactivate(account id: UUID) {
        if accountHasTransactions(id) {
            if let i = data.accounts.firstIndex(where: { $0.id == id }) { data.accounts[i].isActive = false }
        } else {
            data.accounts.removeAll { $0.id == id }
        }
        changed()
    }

    /// Sets the real balance by recording an adjustment for the difference.
    func setBalance(of accountID: UUID, to newBalance: Decimal, on date: LocalDate) throws {
        let diff = (newBalance - balance(of: accountID)).rounded(scale: 2)
        guard diff != 0 else { return }
        try save(FinanceTransaction(kind: .adjustment, amount: diff.magnitudeValue, adjustmentIsNegative: diff < 0, accountID: accountID,
                                    title: "עדכון יתרה ידני", date: date))
    }

    // MARK: - Contacts & categories

    @discardableResult
    func addContact(_ c: Contact) -> Contact {
        data.contacts.append(c)
        changed()
        return c
    }

    func addOrFindContact(_ c: Contact) -> Contact {
        if let sys = c.systemContactID, let existing = data.contacts.first(where: { $0.systemContactID == sys }) { return existing }
        if let existing = data.contacts.first(where: { $0.name == c.name }) { return existing }
        return addContact(c)
    }

    func save(_ contact: Contact) {
        if let i = data.contacts.firstIndex(where: { $0.id == contact.id }) { data.contacts[i] = contact } else { data.contacts.append(contact) }
        changed()
    }

    func contactInUse(_ id: UUID) -> Bool {
        data.debts.contains { $0.contactID == id } || data.transactions.contains { $0.contactID == id } || data.events.contains { $0.contactID == id }
    }

    func deleteContact(_ id: UUID) {
        guard !contactInUse(id) else { errorMessage = "אי אפשר למחוק איש קשר שיש לו חובות, אירועים או תנועות."; return }
        data.contacts.removeAll { $0.id == id }
        changed()
    }

    func save(_ category: FinanceCategory) {
        if let i = data.categories.firstIndex(where: { $0.id == category.id }) { data.categories[i] = category } else { data.categories.append(category) }
        changed()
    }

    // MARK: - Recurring

    func save(_ rule: RecurringRule) throws {
        let probe = RecurrenceEngine.makeTransaction(for: rule, on: rule.startDate, status: .pending)
        try probe.validate(in: data)
        if let i = data.recurringRules.firstIndex(where: { $0.id == rule.id }) { data.recurringRules[i] = rule } else { data.recurringRules.append(rule) }
        changed()
        materializeRecurring()
    }

    func deleteRule(_ id: UUID, removePendingOccurrences: Bool) {
        data.recurringRules.removeAll { $0.id == id }
        if removePendingOccurrences {
            data.transactions.removeAll { $0.recurringID == id && $0.status == .pending }
        }
        changed()
    }

    // MARK: - Events

    func save(_ event: FinanceEvent) throws {
        var e = event
        e.title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        try e.validate()
        if let i = data.events.firstIndex(where: { $0.id == e.id }) { data.events[i] = e } else { data.events.append(e) }
        changed()
    }

    func deleteEvent(_ id: UUID) {
        data.events.removeAll { $0.id == id }
        for i in data.transactions.indices where data.transactions[i].eventID == id { data.transactions[i].eventID = nil }
        for i in data.debts.indices where data.debts[i].eventID == id { data.debts[i].eventID = nil }
        changed()
    }

    /// Records money received (or paid) for an event.
    func recordEventPayment(eventID: UUID, kind: TransactionKind, amount: Decimal, accountID: UUID, date: LocalDate, method: PaymentMethod?) throws {
        guard let event = data.event(eventID) else { return }
        if kind == .income, let debtID = event.debtID, data.debt(debtID) != nil {
            try recordDebtPayment(debtID: debtID, amount: amount, date: date, accountID: accountID)
            return
        }
        let category = kind == .income ? DefaultCategories.income[1].id : nil
        try save(FinanceTransaction(kind: kind, amount: amount, accountID: accountID, categoryID: category, contactID: event.contactID,
                                    title: event.title, date: date, paymentMethod: method, eventID: eventID, source: .eventPayment))
    }

    /// Opens a receivable for the unpaid part of an event (so it is tracked in Debts and reminders).
    func createReceivable(for eventID: UUID, contactID: UUID, dueDate: LocalDate?) throws {
        guard let i = data.events.firstIndex(where: { $0.id == eventID }) else { return }
        let fin = EventCalculator.financials(of: data.events[i], transactions: data.transactions)
        guard fin.outstandingIncome > 0 else { throw ValidationError.nonPositiveAmount }
        let debt = Debt(direction: .receivable, contactID: contactID, title: data.events[i].title, originalAmount: fin.outstandingIncome,
                        issuedDate: today, dueDate: dueDate ?? data.events[i].date, eventID: eventID)
        data.debts.append(debt)
        data.events[i].debtID = debt.id
        if data.events[i].contactID == nil { data.events[i].contactID = contactID }
        changed()
    }

    // MARK: - Debts

    func save(_ debt: Debt) throws {
        var d = debt
        d.title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.title.isEmpty { throw ValidationError.emptyTitle }
        if d.originalAmount <= 0 { throw ValidationError.nonPositiveAmount }
        let paid = data.payments(for: d.id).reduce(Decimal(0)) { $0 + $1.amount }
        if d.originalAmount < paid { throw ValidationError.paymentExceedsRemaining(remaining: paid) }
        if let i = data.debts.firstIndex(where: { $0.id == d.id }) { data.debts[i] = d } else { data.debts.append(d) }
        changed()
    }

    func recordDebtPayment(debtID: UUID, amount: Decimal, date: LocalDate, accountID: UUID, notes: String = "") throws {
        let (payment, tx) = try DebtCalculator.recordPayment(debtID: debtID, amount: amount.rounded(scale: 2), date: date,
                                                             accountID: accountID, notes: notes, in: data, today: today)
        data.transactions.append(tx)
        data.debtPayments.append(payment)
        changed()
    }

    func deletePayment(_ id: UUID) {
        guard let p = data.debtPayments.first(where: { $0.id == id }) else { return }
        data.debtPayments.removeAll { $0.id == id }
        if let t = p.transactionID { data.transactions.removeAll { $0.id == t } }
        changed()
    }

    func setClosedStatus(_ status: DebtStatus?, for debtID: UUID) {
        guard let i = data.debts.firstIndex(where: { $0.id == debtID }) else { return }
        data.debts[i].closedStatus = status
        changed()
    }

    /// Deletes a debt and its payment records. Money that actually moved stays in the account history.
    func deleteDebt(_ id: UUID) {
        data.debts.removeAll { $0.id == id }
        data.debtPayments.removeAll { $0.debtID == id }
        for i in data.events.indices where data.events[i].debtID == id { data.events[i].debtID = nil }
        changed()
    }

    // MARK: - Import

    func applyImport(_ transactions: [FinanceTransaction], adjustments: [FinanceTransaction]) throws -> Int {
        var added = 0
        for t in transactions + adjustments {
            try t.validate(in: data)
        }
        for t in transactions + adjustments {
            data.transactions.append(t)
            added += 1
        }
        if let target = transactions.first?.accountID ?? adjustments.first?.accountID,
           let i = data.accounts.firstIndex(where: { $0.id == target }) {
            data.accounts[i].lastSyncedAt = Date()
        }
        changed()
        return added
    }

    func importEvents(_ events: [FinanceEvent]) -> Int {
        let known = Set(data.events.compactMap(\.calendarEventIdentifier))
        let fresh = events.filter { $0.calendarEventIdentifier.map { !known.contains($0) } ?? true }
        data.events.append(contentsOf: fresh)
        if !fresh.isEmpty { changed() }
        return fresh.count
    }

    func setCalendarIdentifier(_ identifier: String?, for eventID: UUID) {
        guard let i = data.events.firstIndex(where: { $0.id == eventID }) else { return }
        data.events[i].calendarEventIdentifier = identifier
        changed()
    }

    func updateSettings(_ s: FinanceSettings) {
        data.settings = s
        changed()
    }
}
