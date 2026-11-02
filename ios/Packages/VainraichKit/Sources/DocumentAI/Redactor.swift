import Foundation

/// Removes identifying numbers from document text before it leaves the phone.
///
/// Masks Israeli ID numbers (9 digits), bank account / card numbers (long digit runs, possibly
/// with dashes or spaces) — keeping only the last 4 digits — and e-mail addresses.
/// Amounts with decimal points and dates are left untouched.
public enum Redactor {
    /// "12-345-678901" → "****8901".
    public static func lastFour(_ s: String) -> String {
        let digits = s.filter(\.isNumber)
        guard digits.count > 4 else { return digits.isEmpty ? s : digits }
        return "****" + digits.suffix(4)
    }

    public static func redact(_ text: String) -> String {
        var out = text
        // Card numbers: 4-4-4-4 groups.
        out = replace(#"\b(?:\d{4}[ -]){3}\d{4}\b"#, in: out) { lastFour($0) }
        // Account-style numbers: 2-3 digit branch + long account, e.g. 12-345-678901 / 345-678901.
        out = replace(#"\b\d{2,3}-\d{3}-\d{4,9}\b"#, in: out) { lastFour($0) }
        // Any run of 7+ digits not part of a decimal amount (IDs, accounts, phone-like numbers).
        out = replace(#"(?<![\d.,])\d{7,}(?![\d]|[.,]\d)"#, in: out) { lastFour($0) }
        // E-mail addresses.
        out = replace(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, in: out) { _ in "[דוא״ל]" }
        return out
    }

    private static func replace(_ pattern: String, in text: String, with transform: (String) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            result += transform(ns.substring(with: m.range))
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
