import SwiftUI
import FinanceCore

/// "Did you get paid for this event?" — one card per event that needs an answer.
/// Matches between events and income are only suggestions; nothing is linked until the user confirms.
struct EventPaymentReviewView: View {
    @Environment(AppModel.self) private var model
    @State private var recording: FinanceEvent?
    @State private var awaiting: FinanceEvent?

    var body: some View {
        let questions = model.eventPaymentQuestions
        ScrollView {
            VStack(spacing: 14) {
                DemoBanner()
                if questions.isEmpty {
                    EmptyStateView(icon: "checkmark.seal", title: "הכול מעודכן",
                                   message: "אין אירועים שמחכים לתשובה. כשיופיע אירוע (למשל עם המילה \"אירוע\") או הכנסה שנראית כמו תשלום עליו — הוא יופיע כאן לאישור שלך.")
                        .card()
                } else {
                    Text("מצאתי אירועים שכדאי לבדוק אם שילמו עליהם. שום דבר לא מקושר בלי האישור שלך.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(questions) { q in card(q) }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("תשלומים על אירועים")
        .sheet(item: $recording) { e in
            EventPaymentSheet(event: e, kind: .income, suggested: EventCalculator.financials(of: e, transactions: model.data.transactions).outstandingIncome)
        }
        .sheet(item: $awaiting) { e in AwaitingPaymentSheet(event: e) }
    }

    @ViewBuilder
    private func card(_ q: EventPaymentQuestion) -> some View {
        let e = q.event
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(e.title).font(.headline)
                    HStack(spacing: 6) {
                        Text(e.date.short)
                        if let c = model.data.contact(e.contactID) { Text("· \(c.name)") }
                    }
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let inc = e.expectedIncome, inc > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        AmountText(amount: inc, font: .subheadline.weight(.semibold).monospacedDigit(), color: Theme.expected)
                        if q.outstanding > 0 && q.outstanding != inc { Text("נותר \(q.outstanding.ils)").font(.caption2).foregroundStyle(Theme.textSecondary) }
                    }
                }
            }

            switch q.kind {
            case .possibleMatch:
                Text("נמצאה הכנסה שאולי היא התשלום על האירוע:").font(.subheadline.weight(.medium))
                ForEach(q.suggestions) { s in suggestionRow(s, event: e) }
                Button("אף אחת מהן — אני ארשום ידנית") { recording = e }.font(.footnote)

            case .unpaidAfterEvent:
                Text("האירוע עבר ועוד לא נרשם תשלום. שילמו לך?").font(.subheadline.weight(.medium))
                HStack(spacing: 10) {
                    Button { recording = e } label: { Label("כן, שילמו", systemImage: "checkmark") }
                        .buttonStyle(.borderedProminent).tint(Theme.actual)
                    Button { awaiting = e } label: { Label("עדיין לא", systemImage: "clock") }
                        .buttonStyle(.bordered)
                }

            case .unknownIfPaid:
                Text("זה נראה כמו אירוע בתשלום. שילמו לך עליו?").font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    Button { recording = e } label: { Text("כן, שילמו") }
                        .buttonStyle(.borderedProminent).tint(Theme.actual)
                    Button { awaiting = e } label: { Text("עדיין לא") }
                        .buttonStyle(.bordered)
                    Button { model.markNotIncomeEvent(e.id); model.show("לא אשאל יותר על האירוע הזה") } label: { Text("לא בתשלום") }
                        .buttonStyle(.bordered).tint(Theme.neutral)
                }
                .font(.subheadline)
            }

            NavigationLink { EventDetailView(eventID: e.id) } label: { Text("פרטי האירוע").font(.footnote) }
        }
        .card()
    }

    private func suggestionRow(_ s: EventMatchSuggestion, event: FinanceEvent) -> some View {
        let t = model.data.transactions.first { $0.id == s.transactionID }
        return VStack(alignment: .leading, spacing: 8) {
            if let t {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.subheadline)
                        Text("\(t.date.short) · \(model.data.account(t.accountID)?.name ?? "")").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    AmountText(amount: t.amount, font: .subheadline.weight(.semibold).monospacedDigit(), color: Theme.actual, showPlus: true)
                }
                Text(s.reasons.joined(separator: " · ")).font(.caption2).foregroundStyle(Theme.textSecondary)
                HStack(spacing: 10) {
                    Button {
                        model.confirmMatch(transactionID: t.id, eventID: event.id)
                        model.show("קושר לאירוע — סומן כשולם")
                    } label: { Label("כן, זה התשלום", systemImage: "link") }
                        .buttonStyle(.borderedProminent).tint(Theme.actual)
                    Button {
                        model.rejectMatch(transactionID: t.id, eventID: event.id)
                    } label: { Label("לא קשור", systemImage: "xmark") }
                        .buttonStyle(.bordered)
                }
                .font(.subheadline)
            }
        }
        .padding(12)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
    }
}

/// "Not paid yet": optionally set the expected amount (enters the forecast) and open a receivable with reminders.
struct AwaitingPaymentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let event: FinanceEvent
    @State private var amountText = ""
    @State private var openDebt = false
    @State private var contactID: UUID?
    @State private var due = LocalDate.today().adding(days: 7)
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyField(title: "כמה אמורים לשלם לך", text: $amountText, large: true)
                } footer: {
                    Text("הסכום ייכנס לתחזית כהכנסה צפויה — לא ליתרה בפועל — עד שתאשר שהתקבל.")
                }
                Section {
                    Toggle("לפתוח חוב לגבייה עם תזכורת", isOn: $openDebt)
                    if openDebt {
                        ContactPicker(title: "מי צריך לשלם", selection: $contactID, allowNone: false)
                        DatePicker("עד מתי", selection: $due.asDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("עדיין לא שילמו")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("שמירה", action: save).fontWeight(.semibold) }
            }
            .alert("לא ניתן לשמור", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("הבנתי", role: .cancel) {}
            } message: { Text(error ?? "") }
            .onAppear {
                amountText = event.expectedIncome?.editingText ?? ""
                contactID = event.contactID
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let amount = Decimal.parseMoney(amountText)?.magnitudeValue
        model.markAwaitingPayment(event.id, expected: amount)
        if openDebt {
            guard let contactID else { error = "יש לבחור איש קשר."; return }
            do { try model.createReceivable(for: event.id, contactID: contactID, dueDate: due) }
            catch { self.error = amount == nil ? "כדי לפתוח חוב צריך להזין סכום." : hebrewMessage(for: error); return }
        }
        model.show("נשמר — אזכיר לך")
        dismiss()
    }
}

