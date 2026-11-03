package com.vainraich.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.math.BigDecimal
import java.time.LocalDate
import java.util.UUID

typealias SMoney = @Serializable(with = MoneySerializer::class) BigDecimal
typealias SDate = @Serializable(with = LocalDateSerializer::class) LocalDate

fun newId(): String = UUID.randomUUID().toString()

@Serializable
enum class AccountType {
    @SerialName("bank") BANK, @SerialName("cash") CASH, @SerialName("bit") BIT,
    @SerialName("creditCard") CREDIT_CARD, @SerialName("savings") SAVINGS, @SerialName("other") OTHER;

    val defaultIncludeInAvailable: Boolean get() = this == BANK || this == CASH || this == BIT
}

@Serializable
enum class TxKind {
    /** Money in; counted as income. */
    @SerialName("income") INCOME,
    /** Money out; counted as expense (including credit-card purchases). */
    @SerialName("expense") EXPENSE,
    /** Between the user's own accounts (incl. paying a card bill). Never income/expense. */
    @SerialName("transfer") TRANSFER,
    /** Manual balance correction. Never income/expense. */
    @SerialName("adjustment") ADJUSTMENT
}

@Serializable
enum class TxStatus { @SerialName("pending") PENDING, @SerialName("completed") COMPLETED, @SerialName("cancelled") CANCELLED }

@Serializable
enum class PaymentMethod {
    @SerialName("bankTransfer") BANK_TRANSFER, @SerialName("creditCard") CREDIT_CARD, @SerialName("cash") CASH,
    @SerialName("bit") BIT, @SerialName("check") CHECK, @SerialName("standingOrder") STANDING_ORDER, @SerialName("other") OTHER
}

@Serializable
enum class TxSource {
    @SerialName("manual") MANUAL, @SerialName("recurring") RECURRING, @SerialName("documentImport") DOCUMENT_IMPORT,
    @SerialName("csvImport") CSV_IMPORT, @SerialName("debtPayment") DEBT_PAYMENT, @SerialName("eventPayment") EVENT_PAYMENT,
    @SerialName("demo") DEMO
}

@Serializable
enum class Frequency { @SerialName("daily") DAILY, @SerialName("weekly") WEEKLY, @SerialName("monthly") MONTHLY, @SerialName("yearly") YEARLY }

@Serializable
enum class DebtDirection { @SerialName("receivable") RECEIVABLE, @SerialName("payable") PAYABLE }

@Serializable
enum class DebtStatus {
    @SerialName("open") OPEN, @SerialName("partiallyPaid") PARTIALLY_PAID, @SerialName("paid") PAID,
    @SerialName("writtenOff") WRITTEN_OFF, @SerialName("cancelled") CANCELLED
}

@Serializable
data class Account(
    val id: String = newId(),
    val name: String,
    val type: AccountType,
    val currency: String = "ILS",
    val institution: String? = null,
    /** Balance at [openingDate] before any recorded transaction. Negative for card debt. */
    val openingBalance: SMoney = ZERO,
    val openingDate: SDate = LocalDate.now(),
    val includeInAvailable: Boolean = type.defaultIncludeInAvailable,
    val creditLimit: SMoney? = null,
    /** Credit cards: day of month the bill is charged. */
    val billingDay: Int? = null,
    /** Credit cards: bank account that pays the bill. */
    val paymentAccountId: String? = null,
    val isActive: Boolean = true,
    val notes: String = "",
    val lastSyncedAt: Long? = null,
    val sortOrder: Int = 0,
)

@Serializable
enum class CategoryKind { @SerialName("income") INCOME, @SerialName("expense") EXPENSE }

@Serializable
data class Category(
    val id: String = newId(),
    val name: String,
    val kind: CategoryKind,
    val icon: String = "tag",
    val colorToken: String = "gray",
    val isArchived: Boolean = false,
)

@Serializable
data class Contact(
    val id: String = newId(),
    val name: String,
    val phone: String? = null,
    val email: String? = null,
    val notes: String = "",
    val systemContactId: String? = null,
)

@Serializable
data class Transaction(
    val id: String = newId(),
    val kind: TxKind,
    val status: TxStatus = TxStatus.COMPLETED,
    /** Always positive; direction comes from [kind]. */
    val amount: SMoney,
    val adjustmentIsNegative: Boolean = false,
    val accountId: String,
    /** Destination for transfers. */
    val counterAccountId: String? = null,
    val categoryId: String? = null,
    val contactId: String? = null,
    val title: String,
    val date: SDate,
    val paymentMethod: PaymentMethod? = null,
    val notes: String = "",
    val eventId: String? = null,
    val recurringId: String? = null,
    val occurrenceDate: SDate? = null,
    val source: TxSource = TxSource.MANUAL,
    val externalId: String? = null,
    val attachmentFile: String? = null,
    /** Real money movement that is not income/expense (e.g. a personal loan). */
    val excludedFromReports: Boolean = false,
    val matchedTransactionId: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
) {
    val countsInReports: Boolean
        get() = status == TxStatus.COMPLETED && !excludedFromReports && (kind == TxKind.INCOME || kind == TxKind.EXPENSE)
}

@Serializable
data class RecurringRule(
    val id: String = newId(),
    val kind: TxKind,
    val amount: SMoney,
    val accountId: String,
    val counterAccountId: String? = null,
    val categoryId: String? = null,
    val contactId: String? = null,
    val title: String,
    val frequency: Frequency,
    /** Every N periods (custom recurrence). */
    val interval: Int = 1,
    /** Monthly/yearly preferred day (clamped; 31 = last day). */
    val dayOfMonth: Int? = null,
    /** Weekly: 1 = Sunday … 7 = Saturday. Empty = weekday of start date. */
    val weekdays: List<Int> = emptyList(),
    val startDate: SDate,
    val endDate: SDate? = null,
    val maxOccurrences: Int? = null,
    val paymentMethod: PaymentMethod? = null,
    val isActive: Boolean = true,
    /** Record occurrences as completed automatically. */
    val autoPost: Boolean = false,
    val notes: String = "",
)

@Serializable
data class TimeOfDay(val hour: Int, val minute: Int) : Comparable<TimeOfDay> {
    val minutes: Int get() = hour * 60 + minute
    override fun compareTo(other: TimeOfDay) = minutes.compareTo(other.minutes)
    override fun toString() = "%02d:%02d".format(hour, minute)
}

@Serializable
enum class EventPaymentStatus { NONE, UNPAID, PARTIALLY_PAID, PAID }

@Serializable
data class FinanceEvent(
    val id: String = newId(),
    val title: String,
    val date: SDate,
    val startTime: TimeOfDay? = null,
    val endTime: TimeOfDay? = null,
    val location: String = "",
    val contactId: String? = null,
    val expectedIncome: SMoney? = null,
    val expectedExpense: SMoney? = null,
    /** Receivable opened for this event; the forecast then counts the receivable instead. */
    val debtId: String? = null,
    val notes: String = "",
    /** Android CalendarContract event id when linked. */
    val calendarEventId: Long? = null,
    /** User's answer: null = not asked, true = paid event, false = not a paid event. */
    val isIncomeEvent: Boolean? = null,
    /** Income the user said is NOT for this event. */
    val rejectedTransactionIds: List<String> = emptyList(),
)

@Serializable
data class Debt(
    val id: String = newId(),
    val direction: DebtDirection,
    val contactId: String,
    val title: String,
    val originalAmount: SMoney,
    val issuedDate: SDate = LocalDate.now(),
    val dueDate: SDate? = null,
    /** Manual terminal state; otherwise derived from payments. */
    val closedStatus: DebtStatus? = null,
    val eventId: String? = null,
    /** False for loans: payments move real money but are not income/expense. */
    val countsAsIncomeOrExpense: Boolean = true,
    val notes: String = "",
    val createdAt: Long = System.currentTimeMillis(),
)

@Serializable
data class DebtPayment(
    val id: String = newId(),
    val debtId: String,
    val amount: SMoney,
    val date: SDate,
    val transactionId: String? = null,
    val notes: String = "",
)

@Serializable
data class FinanceSettings(
    val baseCurrency: String = "ILS",
    val includeReceivablesInForecast: Boolean = true,
    val includePayablesInForecast: Boolean = true,
    val reminderLeadDays: Int = 1,
)

/** Everything the user has — persisted as one JSON document. */
@Serializable
data class FinanceData(
    val schemaVersion: Int = CURRENT_SCHEMA,
    val accounts: List<Account> = emptyList(),
    val transactions: List<Transaction> = emptyList(),
    val categories: List<Category> = DefaultCategories.all,
    val contacts: List<Contact> = emptyList(),
    val recurringRules: List<RecurringRule> = emptyList(),
    val events: List<FinanceEvent> = emptyList(),
    val debts: List<Debt> = emptyList(),
    val debtPayments: List<DebtPayment> = emptyList(),
    val settings: FinanceSettings = FinanceSettings(),
    /** True only for the clearly-labelled demonstration data. */
    val isDemo: Boolean = false,
) {
    fun account(id: String?) = id?.let { i -> accounts.firstOrNull { it.id == i } }
    fun category(id: String?) = id?.let { i -> categories.firstOrNull { it.id == i } }
    fun contact(id: String?) = id?.let { i -> contacts.firstOrNull { it.id == i } }
    fun event(id: String?) = id?.let { i -> events.firstOrNull { it.id == i } }
    fun debt(id: String?) = id?.let { i -> debts.firstOrNull { it.id == i } }
    fun transaction(id: String?) = id?.let { i -> transactions.firstOrNull { it.id == i } }
    fun paymentsFor(debtId: String) = debtPayments.filter { it.debtId == debtId }.sortedBy { it.date }
    fun transactionsForEvent(id: String) = transactions.filter { it.eventId == id }

    companion object { const val CURRENT_SCHEMA = 1 }
}

object DefaultCategories {
    val expense = listOf(
        Category("e01", "מזון וסופרמרקט", CategoryKind.EXPENSE, "cart", "green"),
        Category("e02", "מסעדות ובתי קפה", CategoryKind.EXPENSE, "restaurant", "orange"),
        Category("e03", "תחבורה ורכב", CategoryKind.EXPENSE, "car", "blue"),
        Category("e04", "דיור ושכירות", CategoryKind.EXPENSE, "home", "indigo"),
        Category("e05", "חשבונות ותשתיות", CategoryKind.EXPENSE, "bolt", "yellow"),
        Category("e06", "תקשורת ומנויים", CategoryKind.EXPENSE, "wifi", "teal"),
        Category("e07", "בריאות", CategoryKind.EXPENSE, "health", "red"),
        Category("e08", "קניות וביגוד", CategoryKind.EXPENSE, "bag", "pink"),
        Category("e09", "חינוך וילדים", CategoryKind.EXPENSE, "school", "purple"),
        Category("e10", "פנאי ובילויים", CategoryKind.EXPENSE, "star", "mint"),
        Category("e11", "ציוד ועבודה", CategoryKind.EXPENSE, "camera", "brown"),
        Category("e12", "עמלות וריביות", CategoryKind.EXPENSE, "percent", "gray"),
        Category("e13", "אחר", CategoryKind.EXPENSE, "more", "gray"),
    )
    val income = listOf(
        Category("i01", "משכורת", CategoryKind.INCOME, "work", "green"),
        Category("i02", "עבודה עצמאית ואירועים", CategoryKind.INCOME, "camera", "teal"),
        Category("i03", "החזר חוב", CategoryKind.INCOME, "undo", "purple"),
        Category("i04", "מתנות", CategoryKind.INCOME, "gift", "pink"),
        Category("i05", "קצבאות והחזרים", CategoryKind.INCOME, "bank", "blue"),
        Category("i06", "אחר", CategoryKind.INCOME, "more", "gray"),
    )
    val all = expense + income
    const val SELF_EMPLOYED_INCOME = "i02"
}
