import SwiftUI
import PhotosUI
import FinanceCore

/// Add / edit a transaction. Can also create a recurring rule, or work as a draft editor for imports.
struct TransactionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let existing: FinanceTransaction?
    /// When set, the editor does not save to the model; it returns the edited draft instead.
    private let onDraftSave: ((FinanceTransaction) -> Void)?

    @State private var kind: TransactionKind
    @State private var amountText = ""
    @State private var title = ""
    @State private var accountID: UUID?
    @State private var counterAccountID: UUID?
    @State private var categoryID: UUID?
    @State private var contactID: UUID?
    @State private var date = LocalDate.today()
    @State private var status: TransactionStatus = .completed
    @State private var method: PaymentMethod?
    @State private var notes = ""
    @State private var excluded = false
    @State private var attachment: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var isRecurring = false
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var interval = 1
    @State private var endDate: LocalDate?
    @State private var autoPost = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var showAttachment = false

    init(kind: TransactionKind = .expense, date: LocalDate? = nil, eventID: UUID? = nil) {
        existing = nil
        onDraftSave = nil
        _kind = State(initialValue: kind)
        if let date { _date = State(initialValue: date) }
    }

    init(existing: FinanceTransaction) {
        self.existing = existing
        onDraftSave = nil
        _kind = State(initialValue: existing.kind)
    }

    init(draft: FinanceTransaction, onSave: @escaping (FinanceTransaction) -> Void) {
        existing = draft
        onDraftSave = onSave
        _kind = State(initialValue: draft.kind)
    }

    private var isNew: Bool { existing == nil }
    private var parsedAmount: Decimal? { Decimal.parseMoney(amountText).map { $0.magnitudeValue } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if kind != .adjustment {
                        Picker("סוג", selection: $kind) {
                            Text("הוצאה").tag(TransactionKind.expense)
                            Text("הכנסה").tag(TransactionKind.income)
                            Text("העברה").tag(TransactionKind.transfer)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: kind) { _, _ in categoryID = nil }
                    }
                    MoneyField(title: "סכום", text: $amountText, large: true)
                    TextField(kind == .transfer ? "תיאור (למשל: תשלום ויזה)" : "תיאור", text: $title)
                }

                Section {
                    AccountPicker(title: kind == .transfer ? "מחשבון" : "חשבון", selection: $accountID)
                    if kind == .transfer {
                        AccountPicker(title: "לחשבון", selection: $counterAccountID, excluding: accountID)
                    } else if kind != .adjustment {
                        CategoryPicker(kind: kind == .income ? .income : .expense, selection: $categoryID)
                    }
                    DatePicker("תאריך", selection: $date.asDate, displayedComponents: .date)
                    Picker("סטטוס", selection: $status) {
                        Text("בוצע").tag(TransactionStatus.completed)
                        Text("ממתין / צפוי").tag(TransactionStatus.pending)
                        if !isNew { Text("בוטל").tag(TransactionStatus.cancelled) }
                    }
                } footer: {
                    footerText
                }

                if kind != .adjustment {
                    Section("פרטים נוספים") {
                        Picker("אמצעי תשלום", selection: $method) {
                            Text("לא צוין").tag(PaymentMethod?.none)
                            ForEach(PaymentMethod.allCases, id: \.self) { Text($0.hebrewName).tag(Optional($0)) }
                        }
                        if kind != .transfer {
                            ContactPicker(title: kind == .income ? "ממי" : "למי", selection: $contactID)
                            Toggle("לא לכלול בדוחות הכנסות/הוצאות", isOn: $excluded)
                        }
                        TextField("הערות", text: $notes, axis: .vertical).lineLimit(1...4)
                    }
                }

                Section("קבלה / מסמך") {
                    if let attachment, let img = AttachmentStore.image(attachment) {
                        Button { showAttachment = true } label: {
                            Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        Button("הסרת הצרופה", role: .destructive) { AttachmentStore.delete(attachment); self.attachment = nil }
                    } else {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("צירוף תמונה של קבלה", systemImage: "paperclip")
                        }
                    }
                }

                if isNew && onDraftSave == nil && kind != .adjustment {
                    Section {
                        Toggle("תשלום קבוע (חוזר)", isOn: $isRecurring)
                        if isRecurring {
                            Picker("תדירות", selection: $frequency) {
                                Text("יומי").tag(RecurrenceFrequency.daily)
                                Text("שבועי").tag(RecurrenceFrequency.weekly)
                                Text("חודשי").tag(RecurrenceFrequency.monthly)
                                Text("שנתי").tag(RecurrenceFrequency.yearly)
                            }
                            Stepper("כל \(interval) \(unitName)", value: $interval, in: 1...24)
                            Toggle("עד תאריך", isOn: Binding(get: { endDate != nil }, set: { endDate = $0 ? date.adding(years: 1) : nil }))
                            if endDate != nil {
                                DatePicker("תאריך סיום", selection: $endDate.asDate(default: date), displayedComponents: .date)
                            }
                            Toggle("לרשום אוטומטית כבוצע", isOn: $autoPost)
                        }
                    } footer: {
                        if isRecurring {
                            Text(autoPost ? "כל מופע יירשם כבוצע ביום שלו (מתאים להוראות קבע)." : "כל מופע יופיע כ\"ממתין\" ביום שלו ותאשר אותו כשהתשלום בוצע. התחזית תכלול את המופעים העתידיים.")
                        }
                    }
                }

                if !isNew && onDraftSave == nil {
                    Section {
                        if let rule = model.data.recurringRules.first(where: { $0.id == existing?.recurringID }) {
                            Label("חלק מתשלום קבוע: \(rule.title) · \(Labels.frequency(rule.frequency, interval: rule.interval))", systemImage: "repeat")
                                .font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                        if model.data.debtPayments.contains(where: { $0.transactionID == existing?.id }) {
                            Label("תשלום של חוב — שינוי כאן יעדכן גם את החוב", systemImage: "person.2")
                                .font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                        Button("מחיקת התנועה", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("שמירה", action: save).fontWeight(.semibold) }
            }
            .alert("לא ניתן לשמור", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("הבנתי", role: .cancel) {}
            } message: { Text(error ?? "") }
            .confirmationDialog("למחוק את התנועה?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("מחיקה", role: .destructive) {
                    if let id = existing?.id { model.deleteTransaction(id) }
                    dismiss()
                }
            }
            .onChange(of: photoItem) { _, item in loadPhoto(item) }
            .sheet(isPresented: $showAttachment) {
                if let attachment, let img = AttachmentStore.image(attachment) {
                    NavigationStack {
                        ScrollView { Image(uiImage: img).resizable().scaledToFit() }
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("סגירה") { showAttachment = false } } }
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    private var unitName: String {
        switch frequency {
        case .daily: return interval == 1 ? "יום" : "ימים"
        case .weekly: return interval == 1 ? "שבוע" : "שבועות"
        case .monthly: return interval == 1 ? "חודש" : "חודשים"
        case .yearly: return interval == 1 ? "שנה" : "שנים"
        }
    }

    private var navTitle: String {
        if onDraftSave != nil { return "עריכת שורה מיובאת" }
        if isNew {
            switch kind {
            case .income: return "הכנסה חדשה"
            case .expense: return "הוצאה חדשה"
            case .transfer: return "העברה חדשה"
            case .adjustment: return "עדכון יתרה"
            }
        }
        return "עריכת תנועה"
    }

    @ViewBuilder private var footerText: some View {
        if kind == .transfer {
            Text("העברה בין החשבונות שלך — כולל תשלום חשבון כרטיס אשראי — לא נספרת כהוצאה, כי ההוצאה כבר נרשמה בזמן הרכישה בכרטיס.")
        } else if let a = model.data.account(accountID), a.type == .creditCard, kind == .expense {
            Text("רכישה באשראי נרשמת כהוצאה עכשיו, וכחוב בכרטיס. הכסף יירד מהבנק ביום החיוב.")
        } else if status == .pending {
            Text("תנועה ממתינה נכללת בתחזית אבל לא משנה את היתרה בפועל עד שתסמן אותה כבוצעה.")
        }
    }

    private func load() {
        if let t = existing {
            amountText = t.amount.editingText
            title = t.title
            accountID = t.accountID
            counterAccountID = t.counterAccountID
            categoryID = t.categoryID
            contactID = t.contactID
            date = t.date
            status = t.status
            method = t.paymentMethod
            notes = t.notes
            excluded = t.excludedFromReports
            attachment = t.attachmentFileName
        } else if accountID == nil {
            accountID = model.defaultAccountID
            if kind == .transfer {
                counterAccountID = model.activeAccounts.first { $0.type == .creditCard }?.id
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                do { attachment = try AttachmentStore.saveImage(img) } catch { self.error = "לא הצלחתי לשמור את התמונה." }
            }
            photoItem = nil
        }
    }

    private func save() {
        guard let amount = parsedAmount, amount > 0 else { error = ValidationError.nonPositiveAmount.hebrewMessage; return }
        guard let accountID else { error = ValidationError.unknownAccount.hebrewMessage; return }
        var finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalTitle.isEmpty {
            finalTitle = model.data.category(categoryID)?.name ?? (kind == .transfer ? "העברה ל\(model.data.account(counterAccountID)?.name ?? "")" : kind.hebrewName)
        }
        let base = existing ?? FinanceTransaction(kind: kind, amount: amount, accountID: accountID, title: finalTitle, date: date)
        var t = base
        t.kind = kind
        t.amount = amount
        t.title = finalTitle
        t.accountID = accountID
        t.counterAccountID = kind == .transfer ? counterAccountID : nil
        t.categoryID = kind == .transfer ? nil : categoryID
        t.contactID = kind == .transfer ? nil : contactID
        t.date = date
        t.status = status
        t.paymentMethod = method
        t.notes = notes
        t.excludedFromReports = excluded
        t.attachmentFileName = attachment

        if let onDraftSave {
            do { try t.validate(in: model.data); onDraftSave(t); dismiss() } catch { self.error = hebrewMessage(for: error) }
            return
        }

        do {
            if isNew && isRecurring {
                let rule = RecurringRule(kind: kind, amount: amount, accountID: accountID, counterAccountID: t.counterAccountID,
                                         categoryID: t.categoryID, contactID: t.contactID, title: finalTitle, frequency: frequency,
                                         interval: interval, dayOfMonth: frequency == .monthly ? date.day : nil, startDate: date,
                                         endDate: endDate, paymentMethod: method, autoPost: autoPost, notes: notes)
                try model.save(rule)
                model.show("התשלום הקבוע נשמר")
            } else {
                try model.save(t)
                model.show(isNew ? "נשמר" : "עודכן")
            }
            dismiss()
        } catch {
            self.error = hebrewMessage(for: error)
        }
    }
}
