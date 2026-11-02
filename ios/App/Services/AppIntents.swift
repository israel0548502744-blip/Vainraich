import AppIntents
import Foundation
import FinanceCore

/// "כמה כסף יש לי" — answers from the saved data file (works from Siri, Shortcuts, Spotlight and the Action button).
struct AvailableMoneyIntent: AppIntent {
    static let title: LocalizedStringResource = "כמה כסף זמין לי"
    static let description = IntentDescription("מציג את הכסף הזמין עכשיו, וכמה צפוי להיכנס ולצאת עד סוף החודש.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FinanceFileStore(url: AppModel.personalFileURL)
        guard store.exists(), let data = try? store.load() else {
            return .result(dialog: IntentDialog(stringLiteral: "עוד לא הוזנו נתונים באפליקציה."))
        }
        let today = LocalDate.today()
        let s = SummaryCalculator.make(data: data, period: .month(containing: today), today: today)
        let text = "יש לך \(MoneyFormatter.format(s.available)) זמינים. עד סוף החודש צפויים להיכנס \(MoneyFormatter.format(s.expectedIncome)) ולצאת \(MoneyFormatter.format(s.expectedExpenses)), כך שהיתרה החזויה היא \(MoneyFormatter.format(s.projectedBalance))."
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

/// "הוספת הוצאה" — quick expense entry from Siri or a Shortcut.
struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "הוספת הוצאה"
    static let description = IntentDescription("רושם הוצאה בחשבון הראשי.")

    @Parameter(title: "סכום")
    var amount: Double

    @Parameter(title: "תיאור")
    var note: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FinanceFileStore(url: AppModel.personalFileURL)
        guard store.exists(), var data = try? store.load() else {
            return .result(dialog: IntentDialog(stringLiteral: "קודם צריך להוסיף חשבון באפליקציה."))
        }
        // Siri delivers a Double; convert through a 2-decimal string so the stored amount is exact.
        guard let value = Decimal(string: String(format: "%.2f", amount)), value > 0 else {
            return .result(dialog: IntentDialog(stringLiteral: "הסכום לא תקין."))
        }
        guard let account = data.accounts.filter({ $0.isActive && $0.includeInAvailable }).sorted(by: { $0.sortOrder < $1.sortOrder }).first else {
            return .result(dialog: IntentDialog(stringLiteral: "לא נמצא חשבון פעיל."))
        }
        let t = FinanceTransaction(kind: .expense, amount: value, accountID: account.id, title: note.isEmpty ? "הוצאה" : note,
                                   date: .today(), source: .manual)
        data.transactions.append(t)
        try store.save(data)
        return .result(dialog: IntentDialog(stringLiteral: "נרשמה הוצאה של \(MoneyFormatter.format(value)) ב\(account.name)."))
    }
}

struct VainraichShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AvailableMoneyIntent(),
                    phrases: ["כמה כסף יש לי ב\(.applicationName)", "יתרה ב\(.applicationName)"],
                    shortTitle: "כסף זמין",
                    systemImageName: "shekelsign.circle")
        AppShortcut(intent: AddExpenseIntent(),
                    phrases: ["הוספת הוצאה ב\(.applicationName)", "רשום הוצאה ב\(.applicationName)"],
                    shortTitle: "הוספת הוצאה",
                    systemImageName: "minus.circle")
    }
}
