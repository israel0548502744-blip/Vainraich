import Foundation

/// A calendar day with no time-of-day and no time zone.
///
/// Financial dates (transaction day, due date, event day) are *days*, not instants.
/// Storing them as `Date` causes off-by-one bugs around midnight and DST, so the
/// engine uses this value type and does all day arithmetic with pure integer math.
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Creates a date, clamping the day into the month (e.g. 31/02 → 28 or 29/02).
    public init(year: Int, month: Int, day: Int) {
        let m = min(max(month, 1), 12)
        self.year = year
        self.month = m
        self.day = min(max(day, 1), LocalDate.daysInMonth(year: year, month: m))
    }

    /// Strict initializer: returns nil for impossible dates instead of clamping.
    public init?(validYear year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1, day <= LocalDate.daysInMonth(year: year, month: month) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    // MARK: - Calendar helpers

    public static func isLeapYear(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        default: return isLeapYear(year) ? 29 : 28
        }
    }

    public var daysInMonth: Int { LocalDate.daysInMonth(year: year, month: month) }

    /// Days since 1970-01-01 (Howard Hinnant's days_from_civil).
    public var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public init(dayNumber z0: Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        self.year = y
        self.month = m
        self.day = d
    }

    public func adding(days: Int) -> LocalDate { LocalDate(dayNumber: dayNumber + days) }

    /// Adds months keeping the day where possible, clamping to the last day of the month.
    public func adding(months: Int) -> LocalDate { adding(months: months, preferredDay: day) }

    public func adding(months: Int, preferredDay: Int) -> LocalDate {
        let total = (year * 12 + (month - 1)) + months
        let y = total >= 0 ? total / 12 : (total - 11) / 12
        let m = total - y * 12 + 1
        return LocalDate(year: y, month: m, day: preferredDay)
    }

    public func adding(years: Int) -> LocalDate { LocalDate(year: year + years, month: month, day: day) }

    public func days(until other: LocalDate) -> Int { other.dayNumber - dayNumber }

    /// 1 = Sunday … 7 = Saturday (matches `Calendar.component(.weekday)`).
    public var weekday: Int {
        // 1970-01-01 was a Thursday (5).
        let w = (dayNumber % 7 + 7) % 7 // 0 = Thursday
        return (w + 4) % 7 + 1
    }

    public var startOfMonth: LocalDate { LocalDate(year: year, month: month, day: 1) }
    public var endOfMonth: LocalDate { LocalDate(year: year, month: month, day: daysInMonth) }

    /// Start of the week, weeks starting on `firstWeekday` (1 = Sunday, Israeli default).
    public func startOfWeek(firstWeekday: Int = 1) -> LocalDate {
        let diff = (weekday - firstWeekday + 7) % 7
        return adding(days: -diff)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // MARK: - Conversion to/from Date

    public static let israelTimeZone = TimeZone(identifier: "Asia/Jerusalem") ?? .current

    public static var financeCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = israelTimeZone
        c.firstWeekday = 1
        c.locale = Locale(identifier: "he_IL")
        return c
    }

    public init(_ date: Date, calendar: Calendar = LocalDate.financeCalendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public static func today(now: Date = Date()) -> LocalDate { LocalDate(now) }

    /// Midnight of this day in the given calendar's time zone.
    public func date(calendar: Calendar = LocalDate.financeCalendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: - Formatting & parsing

    /// ISO-8601 calendar date: `2026-12-15`.
    public var isoString: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Israeli display format: `15/12/2026`.
    public var description: String { String(format: "%02d/%02d/%04d", day, month, year) }

    public init?(iso: String) {
        let parts = iso.trimmingCharacters(in: .whitespaces).prefix(10).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(validYear: y, month: m, day: d)
    }

    /// Parses Israeli day-first formats: `15/12/2026`, `15.12.26`, `1-2-2026`.
    public init?(israeli text: String) {
        let separators = CharacterSet(charactersIn: "/.-")
        let parts = text.trimmingCharacters(in: .whitespaces).components(separatedBy: separators).filter { !$0.isEmpty }
        guard parts.count == 3, let d = Int(parts[0]), let m = Int(parts[1]), var y = Int(parts[2]) else { return nil }
        if y < 100 { y += 2000 }
        self.init(validYear: y, month: m, day: d)
    }

    /// Accepts ISO first, then Israeli day-first.
    public init?(flexible text: String) {
        if let d = LocalDate(iso: text) { self = d; return }
        if let d = LocalDate(israeli: text) { self = d; return }
        return nil
    }
}

extension LocalDate: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let d = LocalDate(iso: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date \(s)")
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(isoString)
    }
}

/// Closed range of days.
public struct DateRange: Hashable, Sendable, Codable {
    public var start: LocalDate
    public var end: LocalDate

    public init(start: LocalDate, end: LocalDate) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    public func contains(_ d: LocalDate) -> Bool { d >= start && d <= end }
    public var dayCount: Int { start.days(until: end) + 1 }

    public static func day(_ d: LocalDate) -> DateRange { DateRange(start: d, end: d) }
    public static func week(containing d: LocalDate) -> DateRange {
        let s = d.startOfWeek()
        return DateRange(start: s, end: s.adding(days: 6))
    }
    public static func month(containing d: LocalDate) -> DateRange { DateRange(start: d.startOfMonth, end: d.endOfMonth) }
    /// `days` days starting today (inclusive): next7 = today…today+6.
    public static func next(_ days: Int, from d: LocalDate) -> DateRange { DateRange(start: d, end: d.adding(days: max(days, 1) - 1)) }

    /// Every day in the range, in order.
    public var days: [LocalDate] { (0..<dayCount).map { start.adding(days: $0) } }
}

/// Time of day for events (no date, no zone).
public struct TimeOfDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var hour: Int
    public var minute: Int
    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }
    public var minutesSinceMidnight: Int { hour * 60 + minute }
    public static func < (l: TimeOfDay, r: TimeOfDay) -> Bool { l.minutesSinceMidnight < r.minutesSinceMidnight }
    public var description: String { String(format: "%02d:%02d", hour, minute) }
}
