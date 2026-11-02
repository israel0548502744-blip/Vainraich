import SwiftUI
import FinanceCore

/// First-run flow: real data (accounts, recurring, upcoming income, first event) or the labelled demo.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var step = 0

    // Accounts
    @State private var bankName = "עו״ש"
    @State private var bankBalance = ""
    @State private var bankNegative = false
    @State private var cash = ""
    @State private var bit = ""
    @State private var hasCard = false
    @State private var cardName = "כרטיס אשראי"
    @State private var cardDebt = ""
    @State private var cardDay = 10
    // Recurring
    struct RecurringDraft: Identifiable { let id = UUID(); var title: String; var amount: String; var day: Int }
    @State private var recurring: [RecurringDraft] = [RecurringDraft(title: "שכר דירה", amount: "", day: 1)]
    // Income
    @State private var incomeTitle = ""
    @State private var incomeAmount = ""
    @State private var incomeDate = LocalDate.today().adding(days: 7)
    // Event
    @State private var eventTitle = ""
    @State private var eventDate = LocalDate.today().adding(days: 14)
    @State private var eventIncome = ""
    @State private var eventContact = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0: welcome
                case 1: accountsStep
                case 2: recurringStep
                case 3: incomeStep
                case 4: eventStep
                default: doneStep
                }
            }
            .animation(.easeInOut, value: step)
            .toolbar {
                if step > 0 && step < 5 {
                    ToolbarItem(placement: .cancellationAction) { Button("חזרה") { step -= 1 } }
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 6) { ForEach(1..<5) { i in Capsule().fill(i <= step ? Theme.brand : Theme.separator).frame(width: 22, height: 4) } }
                    }
                }
            }
            .alert("שגיאה", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("הבנתי", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 64)).foregroundStyle(Theme.brand)
                    .padding(.top, 40)
                Text("הכספים שלי").font(.largeTitle.weight(.bold))
                Text("תשובה ברורה אחת: כמה כסף יש לך באמת, כמה צפוי להיכנס, כמה אתה חייב — ואיך זה ייראה בעוד חודש.")
                    .font(.title3).foregroundStyle(Theme.textSecondary)
                VStack(alignment: .leading, spacing: 16) {
                    feature("checkmark.seal", Theme.actual, "כסף אמיתי מול צפוי", "הכנסה צפויה לעולם לא מתערבבת ביתרה שלך.")
                    feature("calendar", Theme.expected, "אירועים ותשלומים", "יומן עם הכנסות צפויות, סטטוס תשלום ותזכורות.")
                    feature("person.2", Theme.receivable, "מי חייב לך", "תשלומים חלקיים, היסטוריה לכל אדם ותזכורות איחור.")
                    feature("doc.viewfinder", Theme.brand, "קריאת מסמכים", "צלם אישור יתרה או דף חשבון — והנתונים נכנסים לבדיקה.")
                }
                VStack(spacing: 12) {
                    Button { step = 1 } label: { Text("להתחיל עם הנתונים שלי").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    Button { model.enterDemo() } label: { Text("להציץ בהדגמה").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).controlSize(.large)
                    Text("הנתונים נשמרים רק באייפון שלך. ההדגמה מסומנת בבירור ולא נשמרת.")
                        .font(.caption).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
            }
            .padding(24)
        }
    }

    private func feature(_ icon: String, _ c: Color, _ t: String, _ d: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            CategoryIcon(icon: icon, color: c, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.headline)
                Text(d).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var accountsStep: some View {
        Form {
            Section {
                Text("כמה כסף יש לך היום?").font(.title2.weight(.bold))
                Text("הכנס יתרות נוכחיות. אפשר לדלג ולהוסיף אחר כך, או לייבא אישור יתרה.").foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Color.clear)
            Section("חשבון בנק") {
                TextField("שם", text: $bankName)
                MoneyField(title: "יתרה", text: $bankBalance)
                Toggle("במינוס", isOn: $bankNegative)
            }
            Section("מזומן וביט") {
                LabeledContent("מזומן") { MoneyField(title: "0", text: $cash) }
                LabeledContent("ביט") { MoneyField(title: "0", text: $bit) }
            }
            Section {
                Toggle("יש לי כרטיס אשראי", isOn: $hasCard)
                if hasCard {
                    TextField("שם הכרטיס", text: $cardName)
                    LabeledContent("חוב שעוד לא ירד") { MoneyField(title: "0", text: $cardDebt) }
                    Stepper("יום חיוב: \(cardDay)", value: $cardDay, in: 1...31)
                }
            } footer: {
                Text("רכישות באשראי נספרות כהוצאה מיד, והכסף יורד מהבנק רק ביום החיוב — בלי ספירה כפולה.")
            }
            Section { nextButton("המשך") { saveAccounts() } }
        }
    }

    private var recurringStep: some View {
        Form {
            Section {
                Text("הוצאות קבועות").font(.title2.weight(.bold))
                Text("שכר דירה, מנויים, הלוואות — הם ייכנסו לתחזית בכל חודש.").foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Color.clear)
            ForEach($recurring) { $r in
                Section {
                    TextField("מה", text: $r.title)
                    MoneyField(title: "סכום חודשי", text: $r.amount)
                    Stepper("ביום \(r.day) בחודש", value: $r.day, in: 1...31)
                }
            }
            Section {
                Button { recurring.append(RecurringDraft(title: "", amount: "", day: 1)) } label: { Label("עוד הוצאה קבועה", systemImage: "plus") }
            }
            Section { nextButton("המשך") { saveRecurring() } }
        }
    }

    private var incomeStep: some View {
        Form {
            Section {
                Text("הכנסה צפויה").font(.title2.weight(.bold))
                Text("משכורת או תשלום שאתה מחכה לו. הוא ייכנס לתחזית — לא ליתרה.").foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Color.clear)
            Section {
                TextField("מה (למשל: משכורת)", text: $incomeTitle)
                MoneyField(title: "סכום", text: $incomeAmount)
                DatePicker("מתי", selection: $incomeDate.asDate, displayedComponents: .date)
            }
            Section { nextButton("המשך") { saveIncome() } }
        }
    }

    private var eventStep: some View {
        Form {
            Section {
                Text("האירוע הראשון").font(.title2.weight(.bold))
                Text("עבודה, הופעה, צילום — עם הכנסה צפויה ולקוח.").foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Color.clear)
            Section {
                TextField("שם האירוע", text: $eventTitle)
                DatePicker("תאריך", selection: $eventDate.asDate, displayedComponents: .date)
                MoneyField(title: "הכנסה צפויה", text: $eventIncome)
                TextField("לקוח", text: $eventContact)
            }
            Section { nextButton("סיום") { saveEvent() } }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 72)).foregroundStyle(Theme.actual)
            Text("הכול מוכן").font(.largeTitle.weight(.bold))
            Text("טיפ: אפשר לצלם אישור יתרה או דף חשבון במסך ״עוד ← ייבוא ממסמך״.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button { model.persistNow(); hasOnboarded = true } label: { Text("למסך הבית").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(24)
    }

    private func nextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }

    // MARK: Saving

    private func amount(_ s: String) -> Decimal? { Decimal.parseMoney(s).map { $0.magnitudeValue } }

    private func saveAccounts() {
        do {
            var bankID: UUID?
            if !bankName.trimmingCharacters(in: .whitespaces).isEmpty, let v = amount(bankBalance) {
                let a = Account(name: bankName, type: .bank, openingBalance: bankNegative ? -v : v, openingDate: model.today)
                try model.save(a)
                bankID = a.id
            }
            if let v = amount(cash) { try model.save(Account(name: "מזומן", type: .cash, openingBalance: v, openingDate: model.today)) }
            if let v = amount(bit) { try model.save(Account(name: "ביט", type: .bit, openingBalance: v, openingDate: model.today)) }
            if hasCard {
                try model.save(Account(name: cardName, type: .creditCard, openingBalance: -(amount(cardDebt) ?? 0), openingDate: model.today,
                                       billingDay: cardDay, paymentAccountID: bankID))
            }
            step = model.data.accounts.isEmpty ? 5 : 2
        } catch { self.error = hebrewMessage(for: error) }
    }

    private func saveRecurring() {
        guard let account = model.defaultAccountID else { step = 3; return }
        do {
            for r in recurring {
                guard let v = amount(r.amount), v > 0, !r.title.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                var start = LocalDate(year: model.today.year, month: model.today.month, day: r.day)
                if start < model.today { start = start.adding(months: 1, preferredDay: r.day) }
                try model.save(RecurringRule(kind: .expense, amount: v, accountID: account, title: r.title, frequency: .monthly,
                                             dayOfMonth: r.day, startDate: start))
            }
            step = 3
        } catch { self.error = hebrewMessage(for: error) }
    }

    private func saveIncome() {
        if let v = amount(incomeAmount), v > 0, let account = model.defaultAccountID {
            let title = incomeTitle.trimmingCharacters(in: .whitespaces).isEmpty ? "הכנסה צפויה" : incomeTitle
            do {
                try model.save(FinanceTransaction(kind: .income, status: .pending, amount: v, accountID: account, title: title, date: incomeDate))
            } catch { self.error = hebrewMessage(for: error); return }
        }
        step = 4
    }

    private func saveEvent() {
        let title = eventTitle.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty {
            var contactID: UUID?
            let name = eventContact.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { contactID = model.addOrFindContact(Contact(name: name)).id }
            do {
                try model.save(FinanceEvent(title: title, date: eventDate, contactID: contactID, expectedIncome: amount(eventIncome)))
            } catch { self.error = hebrewMessage(for: error); return }
        }
        step = 5
    }
}
