import SwiftUI
import FinanceCore

// MARK: - Card

struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.padding
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.separator.opacity(0.25), lineWidth: 0.5))
    }
}

extension View {
    func card(padding: CGFloat = Theme.padding) -> some View { modifier(CardModifier(padding: padding)) }
}

// MARK: - Amount

/// Money text. Optionally colored by sign. Always LTR-isolated and monospaced.
struct AmountText: View {
    let amount: Decimal
    var font: Font = .body.monospacedDigit()
    var colorBySign = false
    var color: Color? = nil
    var showPlus = false

    var body: some View {
        Text(showPlus ? amount.ilsSigned : amount.ils)
            .font(font)
            .foregroundStyle(resolvedColor)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(accessibilityText)
    }

    private var resolvedColor: Color {
        if let color { return color }
        guard colorBySign else { return .primary }
        return amount < 0 ? Theme.liability : (amount > 0 ? Theme.actual : .primary)
    }

    private var accessibilityText: String {
        let abs = MoneyFormatter.format(amount.magnitudeValue).replacingOccurrences(of: "₪", with: "")
        return (amount < 0 ? "מינוס " : "") + abs + " שקלים"
    }
}

// MARK: - Stat tile

struct StatTile: View {
    let title: String
    let amount: Decimal
    let icon: String
    let color: Color
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.14), in: Circle())
                Text(title).font(.footnote).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            AmountText(amount: amount, font: Theme.amountFont(.title3), color: color)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Badge

struct StatusBadge: View {
    let text: String
    let color: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: Capsule())
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.subheadline)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.brand)
                .frame(width: 80, height: 80)
                .background(Theme.brandSoft, in: Circle())
            Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(action: action) { Text(actionTitle).frame(maxWidth: 260) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Demo banner

struct DemoBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.mode == .demo {
            HStack(spacing: 10) {
                Image(systemName: "theatermasks.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("מצב הדגמה").font(.subheadline.weight(.bold))
                    Text("הנתונים כאן לדוגמה בלבד ואינם נשמרים.").font(.caption)
                }
                Spacer()
                Button("לנתונים שלי") { model.exitDemo() }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(Theme.expected.gradient, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("מצב הדגמה. הנתונים לדוגמה בלבד.")
        }
    }
}

// MARK: - Icons

struct CategoryIcon: View {
    let icon: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Transaction row

struct TransactionRow: View {
    @Environment(AppModel.self) private var model
    let transaction: FinanceTransaction
    var showDate = true

    var body: some View {
        let t = transaction
        let cat = model.data.category(t.categoryID)
        HStack(spacing: 12) {
            CategoryIcon(icon: iconName(cat), color: iconColor(cat))
            VStack(alignment: .leading, spacing: 3) {
                Text(t.title).font(.body).lineLimit(1)
                HStack(spacing: 6) {
                    Text(subtitle(cat)).lineLimit(1)
                    if t.status == .pending { StatusBadge(text: "ממתין", color: Theme.expected) }
                    if t.status == .cancelled { StatusBadge(text: "בוטל", color: Theme.neutral) }
                    if t.attachmentFileName != nil { Image(systemName: "paperclip") }
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            AmountText(amount: signedAmount, font: .body.weight(.semibold).monospacedDigit(), color: amountColor, showPlus: t.kind == .income)
                .strikethrough(t.status == .cancelled)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var signedAmount: Decimal {
        switch transaction.kind {
        case .income: return transaction.amount
        case .expense: return -transaction.amount
        case .transfer: return transaction.amount
        case .adjustment: return transaction.adjustmentIsNegative ? -transaction.amount : transaction.amount
        }
    }

    private var amountColor: Color {
        if transaction.status != .completed { return Theme.expected }
        switch transaction.kind {
        case .income: return Theme.actual
        case .expense: return .primary
        case .transfer, .adjustment: return Theme.neutral
        }
    }

    private func iconName(_ c: FinanceCategory?) -> String {
        switch transaction.kind {
        case .transfer: return "arrow.left.arrow.right"
        case .adjustment: return "slider.horizontal.3"
        default: return c?.icon ?? (transaction.kind == .income ? "arrow.down.left" : "arrow.up.right")
        }
    }

    private func iconColor(_ c: FinanceCategory?) -> Color {
        switch transaction.kind {
        case .transfer, .adjustment: return Theme.neutral
        default: return c.map { Theme.token($0.colorToken) } ?? Theme.neutral
        }
    }

    private func subtitle(_ c: FinanceCategory?) -> String {
        let t = transaction
        var parts: [String] = []
        if showDate { parts.append(t.date.relative(to: model.today)) }
        if t.kind == .transfer {
            parts.append("\(model.data.account(t.accountID)?.name ?? "") ← \(model.data.account(t.counterAccountID)?.name ?? "")")
        } else {
            if let c { parts.append(c.name) }
            if let a = model.data.account(t.accountID) { parts.append(a.name) }
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Toast

struct ToastView: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.actual)
            Text(text).font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}
