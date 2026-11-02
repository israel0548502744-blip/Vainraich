import Foundation

// MARK: - Decimal helpers

public extension Decimal {
    /// Rounds to `scale` fractional digits, half away from zero (`.plain`).
    func rounded(scale: Int = 2) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }

    var isNegativeValue: Bool { self < 0 }
    var magnitudeValue: Decimal { self < 0 ? -self : self }

    /// Parses money text written by humans or models: "1,234.50", "₪ 1,234", "-120", "(120.00)", "1 234,50".
    /// Never goes through `Double`.
    static func parseMoney(_ raw: String) -> Decimal? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
        // Unicode minus signs and trailing minus ("120-") used in some Israeli bank exports.
        s = s.replacingOccurrences(of: "\u{2212}", with: "-").replacingOccurrences(of: "\u{2013}", with: "-")
        let removable = CharacterSet(charactersIn: "₪$€£ \u{00A0}\u{200F}\u{200E}\u{202A}\u{202B}\u{202C}\u{2066}\u{2067}\u{2068}\u{2069}'")
            .union(.letters)
        s = String(s.unicodeScalars.filter { !removable.contains($0) })
        if s.hasSuffix("-") { negative.toggle(); s.removeLast() }
        if s.hasPrefix("-") { negative.toggle(); s.removeFirst() }
        if s.hasPrefix("+") { s.removeFirst() }
        guard !s.isEmpty else { return nil }

        let commaCount = s.filter { $0 == "," }.count
        let dotCount = s.filter { $0 == "." }.count
        if commaCount > 0 && dotCount > 0 {
            // Whichever comes last is the decimal separator.
            if let lastComma = s.lastIndex(of: ","), let lastDot = s.lastIndex(of: "."), lastComma > lastDot {
                s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        } else if commaCount == 1 {
            // "1,234" → thousands; "12,5" / "12,50" → decimal comma.
            let after = s.split(separator: ",", omittingEmptySubsequences: false).last ?? ""
            s = after.count == 3 ? s.replacingOccurrences(of: ",", with: "") : s.replacingOccurrences(of: ",", with: ".")
        } else if commaCount > 1 {
            s = s.replacingOccurrences(of: ",", with: "")
        } else if dotCount > 1 {
            s = s.replacingOccurrences(of: ".", with: "")
        }
        guard s.allSatisfy({ $0.isNumber || $0 == "." }), s.contains(where: { $0.isNumber }) else { return nil }
        guard let value = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return negative ? -value : value
    }

    /// Canonical machine representation ("1234.5" → "1234.50").
    var plainString: String {
        let r = rounded(scale: 2)
        let negative = r < 0
        let units = MoneyFormatter.splitUnits(r.magnitudeValue)
        return (negative ? "-" : "") + "\(units.integer).\(units.fraction)"
    }
}

// MARK: - Codable wrappers that store Decimal as a string

/// Encodes a `Decimal` as a JSON string ("1234.50") so no JSON layer ever converts it through `Double`.
/// Decodes both strings and numbers for robustness.
@propertyWrapper
public struct DecimalString: Codable, Hashable, Sendable {
    public var wrappedValue: Decimal
    public init(wrappedValue: Decimal) { self.wrappedValue = wrappedValue }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self), let d = Decimal.parseMoney(s) {
            wrappedValue = d
        } else if let d = try? c.decode(Decimal.self) {
            wrappedValue = d.rounded(scale: 2)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected decimal amount")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue.plainString)
    }
}

@propertyWrapper
public struct OptionalDecimalString: Codable, Hashable, Sendable {
    public var wrappedValue: Decimal?
    public init(wrappedValue: Decimal?) { self.wrappedValue = wrappedValue }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { wrappedValue = nil; return }
        if let s = try? c.decode(String.self) { wrappedValue = Decimal.parseMoney(s); return }
        wrappedValue = try? c.decode(Decimal.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let v = wrappedValue { try c.encode(v.plainString) } else { try c.encodeNil() }
    }
}

public extension KeyedDecodingContainer {
    /// Lets a missing key decode as `nil` for optional decimal properties.
    func decode(_ type: OptionalDecimalString.Type, forKey key: Key) throws -> OptionalDecimalString {
        try decodeIfPresent(type, forKey: key) ?? OptionalDecimalString(wrappedValue: nil)
    }
}

// MARK: - Formatting

/// Deterministic Israeli money formatting (identical on iOS and Linux, independent of device locale).
public enum MoneyFormatter {
    public static func symbol(for currency: String) -> String {
        switch currency.uppercased() {
        case "ILS": return "₪"
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        default: return currency.uppercased() + " "
        }
    }

    static func splitUnits(_ magnitude: Decimal) -> (integer: String, fraction: String) {
        let r = magnitude.rounded(scale: 2)
        let s = NSDecimalNumber(decimal: r).stringValue // "1234.5" (POSIX format)
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        let integer = String(parts.first ?? "0")
        var fraction = parts.count > 1 ? String(parts[1]) : "00"
        while fraction.count < 2 { fraction += "0" }
        return (integer, String(fraction.prefix(2)))
    }

    static func grouped(_ integer: String) -> String {
        var out = ""
        for (i, ch) in integer.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return String(out.reversed())
    }

    /// "₪1,500" / "₪1,500.50" / "-₪300".
    /// - Parameters:
    ///   - alwaysShowCents: force two decimals even for whole amounts.
    ///   - showPlus: prefix positive values with "+".
    public static func format(_ amount: Decimal, currency: String = "ILS", alwaysShowCents: Bool = false, showPlus: Bool = false) -> String {
        let r = amount.rounded(scale: 2)
        let units = splitUnits(r.magnitudeValue)
        var body = grouped(units.integer)
        if alwaysShowCents || units.fraction != "00" { body += "." + units.fraction }
        let sign = r < 0 ? "-" : (showPlus && r > 0 ? "+" : "")
        return sign + symbol(for: currency) + body
    }

    /// Compact form for chart axes: "₪12.5K", "₪1.2M".
    public static func compact(_ amount: Decimal, currency: String = "ILS") -> String {
        let value = NSDecimalNumber(decimal: amount).doubleValue // display only, never stored
        let sign = value < 0 ? "-" : ""
        let a = abs(value)
        let sym = symbol(for: currency)
        switch a {
        case 1_000_000...: return "\(sign)\(sym)\(trim(a / 1_000_000))M"
        case 1_000...: return "\(sign)\(sym)\(trim(a / 1_000))K"
        default: return "\(sign)\(sym)\(Int(a.rounded()))"
        }
    }

    private static func trim(_ v: Double) -> String {
        let s = String(format: "%.1f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}
