import Foundation

// MARK: - Enums

public enum AccountType: String, Codable, CaseIterable, Sendable {
    case bank, cash, bit, creditCard, savings, other

    /// Whether money in this account counts as "available" by default.
    public var defaultIncludeInAvailable: Bool {
        switch self {
        case .bank, .cash, .bit: return true
        case .creditCard, .savings, .other: return false
        }
    }
}

public enum TransactionKind: String, Codable, CaseIterable, Sendable {
    /// Money in. Counted as income in reports.
    case income
    /// Money out. Counted as expense in reports (including credit-card purchases).
    case expense
    /// Moving money between the user's own accounts — including paying a credit-card bill.
    /// Never counted as income or expense.
    case transfer
    /// Manual balance correction / reconciliation. Never counted as income or expense.
    case adjustment
}

public enum TransactionStatus: String, Codable, CaseIterable, Sendable {
    case pending, completed, cancelled
}

public enum PaymentMethod: String, Codable, CaseIterable, Sendable {
    case bankTransfer, creditCard, cash, bit, check, standingOrder, other
}

public enum TransactionSource: String, Codable, Sendable {
    case manual, recurring, documentImport, csvImport, debtPayment, eventPayment, demo
}

public enum RecurrenceFrequency: String, Codable, CaseIterable, Sendable {
    case daily, weekly, monthly, yearly
}

public enum DebtDirection: String, Codable, CaseIterable, Sendable {
    /// Someone owes the user.
    case receivable
    /// The user owes someone.
    case payable
}

// MARK: - Account

public struct Account: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var type: AccountType
    public var currency: String
    public var institution: String?
    /// Balance at `openingDate`, before any recorded transaction. Negative for card debt.
    @DecimalString public var openingBalance: Decimal
    public var openingDate: LocalDate
    public var includeInAvailable: Bool
    @OptionalDecimalString public var creditLimit: Decimal?
    /// Day of month the card is charged (credit cards).
    public var billingDay: Int?
    /// Bank account that pays this card's bill (credit cards).
    public var paymentAccountID: UUID?
    public var isActive: Bool
    public var notes: String
    public var lastSyncedAt: Date?
    public var sortOrder: Int

    public init(
        id: UUID = UUID(), name: String, type: AccountType, currency: String = "ILS", institution: String? = nil,
        openingBalance: Decimal = 0, openingDate: LocalDate = .today(), includeInAvailable: Bool? = nil,
        creditLimit: Decimal? = nil, billingDay: Int? = nil, paymentAccountID: UUID? = nil, isActive: Bool = true,
        notes: String = "", lastSyncedAt: Date? = nil, sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.currency = currency
        self.institution = institution
        self.openingBalance = openingBalance
        self.openingDate = openingDate
        self.includeInAvailable = includeInAvailable ?? type.defaultIncludeInAvailable
        self.creditLimit = creditLimit
        self.billingDay = billingDay
        self.paymentAccountID = paymentAccountID
        self.isActive = isActive
        self.notes = notes
        self.lastSyncedAt = lastSyncedAt
        self.sortOrder = sortOrder
    }
}

// MARK: - FinanceCategory & Contact

public struct FinanceCategory: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case income, expense }
    public var id: UUID
    public var name: String
    public var kind: Kind
    /// SF Symbol name.
    public var icon: String
    /// Design-system color token name.
    public var colorToken: String
    public var isArchived: Bool

    public init(id: UUID = UUID(), name: String, kind: Kind, icon: String = "tag", colorToken: String = "gray", isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.icon = icon
        self.colorToken = colorToken
        self.isArchived = isArchived
    }
}

public struct Contact: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var phone: String?
    public var email: String?
    public var notes: String
    /// `CNContact.identifier` when picked from the iPhone address book.
    public var systemContactID: String?

    public init(id: UUID = UUID(), name: String, phone: String? = nil, email: String? = nil, notes: String = "", systemContactID: String? = nil) {
        self.id = id
        self.name = name
        self.phone = phone
        self.email = email
        self.notes = notes
        self.systemContactID = systemContactID
    }
}

// MARK: - FinanceTransaction

public struct FinanceTransaction: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: TransactionKind
    public var status: TransactionStatus
    /// Always positive. Direction comes from `kind` (and `adjustmentIsNegative`).
    @DecimalString public var amount: Decimal
    /// For `.adjustment` only: true when the correction lowers the balance.
    public var adjustmentIsNegative: Bool
    public var accountID: UUID
    /// Destination account for `.transfer` (source is `accountID`).
    public var counterAccountID: UUID?
    public var categoryID: UUID?
    public var contactID: UUID?
    public var title: String
    public var date: LocalDate
    public var paymentMethod: PaymentMethod?
    public var notes: String
    public var eventID: UUID?
    public var recurringID: UUID?
    public var occurrenceDate: LocalDate?
    public var source: TransactionSource
    /// Identifier from an imported document/statement — used to skip duplicates.
    public var externalID: String?
    /// File name of an attachment stored in the app's private documents folder.
    public var attachmentFileName: String?
    /// Movement of money that is not real income/expense (e.g. receiving a personal loan).
    public var excludedFromReports: Bool
    /// Links a manual Bit entry to the matching bank line so they are not counted twice.
    public var matchedTransactionID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), kind: TransactionKind, status: TransactionStatus = .completed, amount: Decimal,
        adjustmentIsNegative: Bool = false, accountID: UUID, counterAccountID: UUID? = nil, categoryID: UUID? = nil,
        contactID: UUID? = nil, title: String, date: LocalDate, paymentMethod: PaymentMethod? = nil, notes: String = "",
        eventID: UUID? = nil, recurringID: UUID? = nil, occurrenceDate: LocalDate? = nil, source: TransactionSource = .manual,
        externalID: String? = nil, attachmentFileName: String? = nil, excludedFromReports: Bool = false,
        matchedTransactionID: UUID? = nil, createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.amount = amount
        self.adjustmentIsNegative = adjustmentIsNegative
        self.accountID = accountID
        self.counterAccountID = counterAccountID
        self.categoryID = categoryID
        self.contactID = contactID
        self.title = title
        self.date = date
        self.paymentMethod = paymentMethod
        self.notes = notes
        self.eventID = eventID
        self.recurringID = recurringID
        self.occurrenceDate = occurrenceDate
        self.source = source
        self.externalID = externalID
        self.attachmentFileName = attachmentFileName
        self.excludedFromReports = excludedFromReports
        self.matchedTransactionID = matchedTransactionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// True when this row counts toward income/expense totals.
    public var countsInReports: Bool {
        status == .completed && !excludedFromReports && (kind == .income || kind == .expense)
    }
}

// MARK: - Recurring

public struct RecurringRule: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: TransactionKind
    @DecimalString public var amount: Decimal
    public var accountID: UUID
    public var counterAccountID: UUID?
    public var categoryID: UUID?
    public var contactID: UUID?
    public var title: String
    public var frequency: RecurrenceFrequency
    /// Every N periods (≥ 1). Covers "custom" recurrences such as every 2 weeks.
    public var interval: Int
    /// For monthly/yearly: preferred day (clamped to month length; 31 = last day).
    public var dayOfMonth: Int?
    /// For weekly: weekdays 1 = Sunday … 7 = Saturday. Empty = weekday of `startDate`.
    public var weekdays: [Int]
    public var startDate: LocalDate
    public var endDate: LocalDate?
    public var maxOccurrences: Int?
    public var paymentMethod: PaymentMethod?
    public var isActive: Bool
    /// When true, occurrences up to today are recorded automatically as completed.
    public var autoPost: Bool
    public var notes: String

    public init(
        id: UUID = UUID(), kind: TransactionKind, amount: Decimal, accountID: UUID, counterAccountID: UUID? = nil,
        categoryID: UUID? = nil, contactID: UUID? = nil, title: String, frequency: RecurrenceFrequency, interval: Int = 1,
        dayOfMonth: Int? = nil, weekdays: [Int] = [], startDate: LocalDate, endDate: LocalDate? = nil,
        maxOccurrences: Int? = nil, paymentMethod: PaymentMethod? = nil, isActive: Bool = true, autoPost: Bool = false, notes: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.amount = amount
        self.accountID = accountID
        self.counterAccountID = counterAccountID
        self.categoryID = categoryID
        self.contactID = contactID
        self.title = title
        self.frequency = frequency
        self.interval = max(1, interval)
        self.dayOfMonth = dayOfMonth
        self.weekdays = weekdays
        self.startDate = startDate
        self.endDate = endDate
        self.maxOccurrences = maxOccurrences
        self.paymentMethod = paymentMethod
        self.isActive = isActive
        self.autoPost = autoPost
        self.notes = notes
    }
}

// MARK: - Events

public enum EventPaymentStatus: String, Codable, Sendable {
    /// No expected income on this event.
    case none
    case unpaid
    case partiallyPaid
    case paid
}

public struct FinanceEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var date: LocalDate
    public var startTime: TimeOfDay?
    public var endTime: TimeOfDay?
    public var location: String
    public var contactID: UUID?
    @OptionalDecimalString public var expectedIncome: Decimal?
    @OptionalDecimalString public var expectedExpense: Decimal?
    /// Receivable created for this event's income (forecast then counts the receivable, not the event).
    public var debtID: UUID?
    public var notes: String
    /// `EKEvent.eventIdentifier` when linked to Apple Calendar.
    public var calendarEventIdentifier: String?
    /// The user's answer to "is this a paid event?": nil = not asked yet, true = income expected, false = not a paid event.
    public var isIncomeEvent: Bool?
    /// Income transactions the user said are NOT the payment for this event (never suggested again).
    public var rejectedTransactionIDs: [UUID]?

    public init(
        id: UUID = UUID(), title: String, date: LocalDate, startTime: TimeOfDay? = nil, endTime: TimeOfDay? = nil,
        location: String = "", contactID: UUID? = nil, expectedIncome: Decimal? = nil, expectedExpense: Decimal? = nil,
        debtID: UUID? = nil, notes: String = "", calendarEventIdentifier: String? = nil,
        isIncomeEvent: Bool? = nil, rejectedTransactionIDs: [UUID]? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.contactID = contactID
        self.expectedIncome = expectedIncome
        self.expectedExpense = expectedExpense
        self.debtID = debtID
        self.notes = notes
        self.calendarEventIdentifier = calendarEventIdentifier
        self.isIncomeEvent = isIncomeEvent
        self.rejectedTransactionIDs = rejectedTransactionIDs
    }
}

// MARK: - Debts

public enum DebtStatus: String, Codable, Sendable {
    case open, partiallyPaid, paid, writtenOff, cancelled
}

public struct Debt: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var direction: DebtDirection
    public var contactID: UUID
    public var title: String
    @DecimalString public var originalAmount: Decimal
    public var issuedDate: LocalDate
    public var dueDate: LocalDate?
    /// Manual terminal state. When nil, the status is derived from payments.
    public var closedStatus: DebtStatus?
    public var eventID: UUID?
    /// When false, payments are recorded as money movement that is excluded from income/expense reports
    /// (e.g. lending to or borrowing from a friend).
    public var countsAsIncomeOrExpense: Bool
    public var notes: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(), direction: DebtDirection, contactID: UUID, title: String, originalAmount: Decimal,
        issuedDate: LocalDate = .today(), dueDate: LocalDate? = nil, closedStatus: DebtStatus? = nil, eventID: UUID? = nil,
        countsAsIncomeOrExpense: Bool = true, notes: String = "", createdAt: Date = Date()
    ) {
        self.id = id
        self.direction = direction
        self.contactID = contactID
        self.title = title
        self.originalAmount = originalAmount
        self.issuedDate = issuedDate
        self.dueDate = dueDate
        self.closedStatus = closedStatus
        self.eventID = eventID
        self.countsAsIncomeOrExpense = countsAsIncomeOrExpense
        self.notes = notes
        self.createdAt = createdAt
    }
}

public struct DebtPayment: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var debtID: UUID
    @DecimalString public var amount: Decimal
    public var date: LocalDate
    /// The account transaction created for this payment (moves the real balance).
    public var transactionID: UUID?
    public var notes: String

    public init(id: UUID = UUID(), debtID: UUID, amount: Decimal, date: LocalDate, transactionID: UUID? = nil, notes: String = "") {
        self.id = id
        self.debtID = debtID
        self.amount = amount
        self.date = date
        self.transactionID = transactionID
        self.notes = notes
    }
}

// MARK: - Settings & aggregate

public struct FinanceSettings: Codable, Hashable, Sendable {
    public var baseCurrency: String
    public var includeReceivablesInForecast: Bool
    public var includePayablesInForecast: Bool
    /// Days before a due date to remind.
    public var reminderLeadDays: Int

    public init(baseCurrency: String = "ILS", includeReceivablesInForecast: Bool = true, includePayablesInForecast: Bool = true, reminderLeadDays: Int = 1) {
        self.baseCurrency = baseCurrency
        self.includeReceivablesInForecast = includeReceivablesInForecast
        self.includePayablesInForecast = includePayablesInForecast
        self.reminderLeadDays = reminderLeadDays
    }
}

/// Everything the user has — the unit that is persisted, synced and backed up.
public struct FinanceData: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var accounts: [Account]
    public var transactions: [FinanceTransaction]
    public var categories: [FinanceCategory]
    public var contacts: [Contact]
    public var recurringRules: [RecurringRule]
    public var events: [FinanceEvent]
    public var debts: [Debt]
    public var debtPayments: [DebtPayment]
    public var settings: FinanceSettings
    /// True only for the clearly-labelled demonstration data set.
    public var isDemo: Bool

    public init(
        accounts: [Account] = [], transactions: [FinanceTransaction] = [], categories: [FinanceCategory] = DefaultCategories.all,
        contacts: [Contact] = [], recurringRules: [RecurringRule] = [], events: [FinanceEvent] = [], debts: [Debt] = [],
        debtPayments: [DebtPayment] = [], settings: FinanceSettings = FinanceSettings(), isDemo: Bool = false
    ) {
        self.schemaVersion = FinanceData.currentSchemaVersion
        self.accounts = accounts
        self.transactions = transactions
        self.categories = categories
        self.contacts = contacts
        self.recurringRules = recurringRules
        self.events = events
        self.debts = debts
        self.debtPayments = debtPayments
        self.settings = settings
        self.isDemo = isDemo
    }

    public static let empty = FinanceData()

    public func account(_ id: UUID?) -> Account? { id.flatMap { id in accounts.first { $0.id == id } } }
    public func category(_ id: UUID?) -> FinanceCategory? { id.flatMap { id in categories.first { $0.id == id } } }
    public func contact(_ id: UUID?) -> Contact? { id.flatMap { id in contacts.first { $0.id == id } } }
    public func event(_ id: UUID?) -> FinanceEvent? { id.flatMap { id in events.first { $0.id == id } } }
    public func debt(_ id: UUID?) -> Debt? { id.flatMap { id in debts.first { $0.id == id } } }
    public func payments(for debtID: UUID) -> [DebtPayment] { debtPayments.filter { $0.debtID == debtID }.sorted { $0.date < $1.date } }
    public func transactions(forEvent id: UUID) -> [FinanceTransaction] { transactions.filter { $0.eventID == id } }
}

// MARK: - Default categories

public enum DefaultCategories {
    public static let all: [FinanceCategory] = expense + income

    public static let expense: [FinanceCategory] = [
        FinanceCategory(id: uuid("E0000000-0000-0000-0000-000000000001"), name: "מזון וסופרמרקט", kind: .expense, icon: "cart", colorToken: "green"),
        FinanceCategory(id: uuid("E0000000-0000-0000-0000-000000000002"), name: "מסעדות ובתי קפה", kind: .expense, icon: "fork.knife", colorToken: "orange"),
        FinanceCategory(id: uuid("E0000000-0000-0000-0000-000000000003"), name: "תחבורה ורכב", kind: .expense, icon: "car", colorToken: "blue"),
        FinanceCategory(id: uuid("E0000000-0000-0000-0000-000000000004"), name: "דיור ושכירות", kind: .expense, icon: "house", colorToken: "indigo"),
        FinanceCategory(id: uuid("E0000000-0000-0000-0000-000000000005"), name: "חשבונות ותשתיות", kind: .expense, icon: "bolt", colorToken: "yellow"),
        FinanceCategory(id: uuid("E0000000-0000-0000-0000-000000000006"), name: "תקשורת ומנויים", kind: .expense, icon: "antenna.radiowaves.left.and.right", colorToken: "teal"),
        FinanceCategory(id: uuid("E0000000-0000-0000-0000-000000000007"), name: "בריאות", kind: .expense, icon: "cross.case", colorToken: "red"),
        FinanceCategory(id: uuid("E0000000-0000-0000-0000-000000000008"), name: "קניות וביגוד", kind: .expense, icon: "bag", colorToken: "pink"),
        FinanceCategory(id: uuid("E0000000-0000-0000-0000-000000000009"), name: "חינוך וילדים", kind: .expense, icon: "graduationcap", colorToken: "purple"),
        FinanceCategory(id: uuid("E0000000-0000-0000-0000-00000000000A"), name: "פנאי ובילויים", kind: .expense, icon: "sparkles", colorToken: "mint"),
        FinanceCategory(id: uuid("E0000000-0000-0000-0000-00000000000B"), name: "ציוד ועבודה", kind: .expense, icon: "camera", colorToken: "brown"),
        FinanceCategory(id: uuid("E0000000-0000-0000-0000-00000000000C"), name: "עמלות וריביות", kind: .expense, icon: "percent", colorToken: "gray"),
        FinanceCategory(id: uuid("E0000000-0000-0000-0000-00000000000D"), name: "אחר", kind: .expense, icon: "ellipsis.circle", colorToken: "gray"),
    ]

    public static let income: [FinanceCategory] = [
        FinanceCategory(id: uuid("10000000-0000-0000-0000-000000000001"), name: "משכורת", kind: .income, icon: "briefcase", colorToken: "green"),
        FinanceCategory(id: uuid("10000000-0000-0000-0000-000000000002"), name: "עבודה עצמאית ואירועים", kind: .income, icon: "camera.aperture", colorToken: "teal"),
        FinanceCategory(id: uuid("10000000-0000-0000-0000-000000000003"), name: "החזר חוב", kind: .income, icon: "arrow.uturn.backward", colorToken: "purple"),
        FinanceCategory(id: uuid("10000000-0000-0000-0000-000000000004"), name: "מתנות", kind: .income, icon: "gift", colorToken: "pink"),
        FinanceCategory(id: uuid("10000000-0000-0000-0000-000000000005"), name: "קצבאות והחזרים", kind: .income, icon: "building.columns", colorToken: "blue"),
        FinanceCategory(id: uuid("10000000-0000-0000-0000-000000000006"), name: "אחר", kind: .income, icon: "ellipsis.circle", colorToken: "gray"),
    ]

    public static var otherExpenseID: UUID { expense.last!.id }
    public static var otherIncomeID: UUID { income.last!.id }
    public static var debtRepaymentIncomeID: UUID { income[2].id }

    private static func uuid(_ s: String) -> UUID { UUID(uuidString: s)! }
}
