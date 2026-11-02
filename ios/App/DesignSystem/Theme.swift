import SwiftUI
import UIKit
import FinanceCore

/// Design tokens. Every color has a light and a dark variant.
enum Theme {
    // MARK: Colors

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Brand: deep teal.
    static let brand = dynamic(light: 0x0F7675, dark: 0x2DD4BF)
    static let brandSoft = dynamic(light: 0xE6F4F2, dark: 0x0E2E2C)

    /// Semantic money colors — used consistently everywhere.
    static let actual = dynamic(light: 0x15803D, dark: 0x4ADE80)      // money you have
    static let expected = dynamic(light: 0xB45309, dark: 0xFBBF24)    // money expected
    static let receivable = dynamic(light: 0x6D28D9, dark: 0xA78BFA)  // owed to you
    static let liability = dynamic(light: 0xB91C1C, dark: 0xF87171)   // you owe
    static let neutral = dynamic(light: 0x475569, dark: 0x94A3B8)

    static let background = Color(UIColor.systemGroupedBackground)
    static let card = Color(UIColor.secondarySystemGroupedBackground)
    static let elevated = Color(UIColor.tertiarySystemGroupedBackground)
    static let separator = Color(UIColor.separator)
    static let textSecondary = Color(UIColor.secondaryLabel)

    static func token(_ name: String) -> Color {
        switch name {
        case "green": return dynamic(light: 0x16A34A, dark: 0x4ADE80)
        case "orange": return dynamic(light: 0xEA580C, dark: 0xFB923C)
        case "blue": return dynamic(light: 0x2563EB, dark: 0x60A5FA)
        case "indigo": return dynamic(light: 0x4F46E5, dark: 0x818CF8)
        case "yellow": return dynamic(light: 0xCA8A04, dark: 0xFACC15)
        case "teal": return dynamic(light: 0x0D9488, dark: 0x2DD4BF)
        case "red": return dynamic(light: 0xDC2626, dark: 0xF87171)
        case "pink": return dynamic(light: 0xDB2777, dark: 0xF472B6)
        case "purple": return dynamic(light: 0x7C3AED, dark: 0xA78BFA)
        case "mint": return dynamic(light: 0x059669, dark: 0x34D399)
        case "brown": return dynamic(light: 0x92400E, dark: 0xD6A26A)
        default: return dynamic(light: 0x64748B, dark: 0x94A3B8)
        }
    }

    static let chartPalette: [Color] = ["teal", "orange", "blue", "purple", "pink", "yellow", "indigo", "mint", "red", "brown", "gray"].map(token)

    // MARK: Layout

    static let cornerRadius: CGFloat = 20
    static let smallRadius: CGFloat = 12
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 12

    // MARK: Typography

    static func amountFont(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .rounded).weight(.semibold).monospacedDigit()
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension AccountType {
    var icon: String {
        switch self {
        case .bank: return "building.columns"
        case .cash: return "banknote"
        case .bit: return "iphone.gen3"
        case .creditCard: return "creditcard"
        case .savings: return "lock.shield"
        case .other: return "wallet.pass"
        }
    }
    var color: Color {
        switch self {
        case .bank: return Theme.token("blue")
        case .cash: return Theme.token("green")
        case .bit: return Theme.token("teal")
        case .creditCard: return Theme.liability
        case .savings: return Theme.token("indigo")
        case .other: return Theme.neutral
        }
    }
    var hebrewName: String { Labels.accountType(self) }
}

extension ForecastConfidence {
    var color: Color {
        switch self {
        case .confirmed: return Theme.actual
        case .expected: return Theme.expected
        case .estimated: return Theme.receivable
        }
    }
    var hebrewName: String { Labels.confidence(self) }
}

extension EventPaymentStatus {
    var color: Color {
        switch self {
        case .none: return Theme.neutral
        case .unpaid: return Theme.expected
        case .partiallyPaid: return Theme.token("blue")
        case .paid: return Theme.actual
        }
    }
    var hebrewName: String { Labels.eventPayment(self) }
}

extension DebtStatus {
    var hebrewName: String { Labels.debtStatus(self) }
    var color: Color {
        switch self {
        case .open: return Theme.expected
        case .partiallyPaid: return Theme.token("blue")
        case .paid: return Theme.actual
        case .writtenOff, .cancelled: return Theme.neutral
        }
    }
}

extension TransactionKind {
    var hebrewName: String { Labels.kind(self) }
    var icon: String {
        switch self {
        case .income: return "arrow.down.left"
        case .expense: return "arrow.up.right"
        case .transfer: return "arrow.left.arrow.right"
        case .adjustment: return "slider.horizontal.3"
        }
    }
}

extension TransactionStatus {
    var hebrewName: String { Labels.status(self) }
}

extension PaymentMethod {
    var hebrewName: String { Labels.paymentMethod(self) }
}
