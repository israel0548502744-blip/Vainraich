import SwiftUI
import Charts
import FinanceCore

struct ReportsView: View {
    @Environment(AppModel.self) private var model
    @State private var month = MonthKey(LocalDate.today())
    @State private var breakdownKind: TransactionKind = .expense
    @State private var share: ShareItem?
    @State private var selectedSlice: String?

    var body: some View {
        let range = month.range
        let current = ReportBuilder.monthly(model.data, endingAt: month, count: 1).first!
        let previous = ReportBuilder.monthly(model.data, endingAt: month.adding(months: -1), count: 1).first!
        let six = ReportBuilder.monthly(model.data, endingAt: month, count: 6)
        let slices = ReportBuilder.byCategory(model.data, kind: breakdownKind, range: range)
        let sources = ReportBuilder.incomeBySource(model.data, range: range)
        ScrollView {
            VStack(spacing: 16) {
                DemoBanner()
                monthHeader
                summaryCard(current, previous)
                trendCard(six)
                breakdownCard(slices)
                if !sources.isEmpty { sourcesCard(sources) }
                receivablesCard
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("דוחות")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { export(.csvTransactions) } label: { Label("תנועות החודש (CSV)", systemImage: "tablecells") }
                    Button { export(.csvMonthly) } label: { Label("סיכום 12 חודשים (CSV)", systemImage: "tablecells.badge.ellipsis") }
                    Button { export(.pdf) } label: { Label("דוח חודשי (PDF)", systemImage: "doc.richtext") }
                } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("ייצוא")
            }
        }
        .sheet(item: $share) { item in ShareSheet(items: [item.url]) }
    }

    private var monthHeader: some View {
        HStack {
            Button { month = month.adding(months: -1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("חודש קודם")
            Spacer()
            Text("\(Labels.monthName(month.month)) \(String(month.year))").font(.title3.weight(.semibold))
            Spacer()
            Button { month = month.adding(months: 1) } label: { Image(systemName: "chevron.left") }
                .disabled(month >= MonthKey(model.today))
                .accessibilityLabel("חודש הבא")
        }
        .padding(.horizontal, 6)
    }

    private func summaryCard(_ m: MonthSummary, _ p: MonthSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                metric("הכנסות", m.income, Theme.actual, change(m.income, p.income))
                metric("הוצאות", m.expenses, Theme.liability, change(m.expenses, p.expenses))
            }
            Divider()
            HStack {
                Text("תזרים נטו").font(.subheadline.weight(.semibold))
                Spacer()
                AmountText(amount: m.net, font: Theme.amountFont(.title3), colorBySign: true, showPlus: true)
            }
            Text("לא כולל העברות בין חשבונות, תשלומי כרטיס אשראי, עדכוני יתרה והלוואות.").font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .card()
    }

    private func metric(_ t: String, _ a: Decimal, _ c: Color, _ delta: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.caption).foregroundStyle(Theme.textSecondary)
            AmountText(amount: a, font: Theme.amountFont(.title3), color: c)
            if let delta { Text(delta).font(.caption2).foregroundStyle(Theme.textSecondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func change(_ now: Decimal, _ before: Decimal) -> String? {
        guard before > 0 else { return nil }
        let pct = ((now - before) / before * 100).doubleValue
        return "\(pct >= 0 ? "▲" : "▼") \(ltr(String(format: "%.0f%%", abs(pct)))) מהחודש הקודם"
    }

    private func trendCard(_ six: [MonthSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "מגמה — 6 חודשים")
            Chart {
                ForEach(six) { m in
                    BarMark(x: .value("חודש", Labels.monthName(m.month.month)), y: .value("סכום", m.income.doubleValue))
                        .foregroundStyle(by: .value("סוג", "הכנסות")).position(by: .value("סוג", "הכנסות"))
                    BarMark(x: .value("חודש", Labels.monthName(m.month.month)), y: .value("סכום", m.expenses.doubleValue))
                        .foregroundStyle(by: .value("סוג", "הוצאות")).position(by: .value("סוג", "הוצאות"))
                    LineMark(x: .value("חודש", Labels.monthName(m.month.month)), y: .value("נטו", m.net.doubleValue))
                        .foregroundStyle(Theme.brand)
                        .symbol(.circle)
                }
            }
            .chartForegroundStyleScale(["הכנסות": Theme.actual, "הוצאות": Theme.liability])
            .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(Decimal(d).ilsCompact) } } } }
            .frame(height: 220)
            Text("הקו מראה את התזרים הנטו בכל חודש.").font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .card()
    }

    private func breakdownCard(_ slices: [BreakdownSlice]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("לפי קטגוריה").font(.headline)
                Spacer()
                Picker("סוג", selection: $breakdownKind) {
                    Text("הוצאות").tag(TransactionKind.expense)
                    Text("הכנסות").tag(TransactionKind.income)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            if slices.isEmpty {
                Text("אין נתונים לחודש הזה.").foregroundStyle(Theme.textSecondary).font(.subheadline)
            } else {
                Chart(slices) { s in
                    SectorMark(angle: .value("סכום", s.amount.doubleValue), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .foregroundStyle(Theme.token(s.colorToken))
                        .opacity(selectedSlice == nil || selectedSlice == s.id ? 1 : 0.35)
                        .cornerRadius(4)
                }
                .chartBackground { _ in
                    VStack(spacing: 2) {
                        let sel = slices.first { $0.id == selectedSlice }
                        Text(sel?.name ?? "סה״כ").font(.caption).foregroundStyle(Theme.textSecondary)
                        AmountText(amount: sel?.amount ?? slices.reduce(Decimal(0)) { $0 + $1.amount }, font: .headline.monospacedDigit())
                    }
                }
                .frame(height: 210)
                ForEach(slices) { s in
                    Button { selectedSlice = selectedSlice == s.id ? nil : s.id } label: {
                        HStack(spacing: 10) {
                            CategoryIcon(icon: s.icon, color: Theme.token(s.colorToken), size: 28)
                            Text(s.name).foregroundStyle(.primary)
                            Spacer()
                            Text(ltr(String(format: "%.0f%%", s.share * 100))).font(.caption).foregroundStyle(Theme.textSecondary)
                            AmountText(amount: s.amount, font: .subheadline.monospacedDigit())
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
    }

    private func sourcesCard(_ sources: [BreakdownSlice]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "הכנסות לפי מקור")
            ForEach(sources) { s in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(s.name, systemImage: s.icon).font(.subheadline)
                        Spacer()
                        AmountText(amount: s.amount, font: .subheadline.monospacedDigit())
                    }
                    GeometryReader { g in
                        Capsule().fill(Theme.actual.opacity(0.8)).frame(width: max(4, g.size.width * s.share), height: 6)
                    }
                    .frame(height: 6)
                }
            }
        }
        .card()
    }

    private var receivablesCard: some View {
        let open = model.data.debts.filter { $0.direction == .receivable }.map { model.debtBalance($0) }.filter(\.isOpen)
        let total = open.reduce(Decimal(0)) { $0 + $1.remaining }
        let overdue = open.filter(\.isOverdue).reduce(Decimal(0)) { $0 + $1.remaining }
        let rate = DebtCalculator.collectionRate(model.data, range: nil)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "גבייה")
            HStack { Text("חובות פתוחים אליי"); Spacer(); AmountText(amount: total, color: Theme.receivable) }
            HStack { Text("מתוכם באיחור"); Spacer(); AmountText(amount: overdue, color: overdue > 0 ? Theme.liability : .primary) }
            if let rate {
                HStack { Text("שיעור גבייה (מכל החובות)"); Spacer(); Text(ltr(String(format: "%.0f%%", rate * 100))).monospacedDigit() }
                ProgressView(value: rate).tint(Theme.actual)
            }
        }
        .font(.subheadline)
        .card()
    }

    // MARK: Export

    enum ExportKind { case csvTransactions, csvMonthly, pdf }

    private func export(_ kind: ExportKind) {
        let dir = FileManager.default.temporaryDirectory
        let stamp = String(format: "%04d-%02d", month.year, month.month)
        do {
            let url: URL
            switch kind {
            case .csvTransactions:
                let list = model.data.transactions.filter { month.range.contains($0.date) }
                url = dir.appendingPathComponent("תנועות-\(stamp).csv")
                try CSVExporter.transactions(list, data: model.data).write(to: url, atomically: true, encoding: .utf8)
            case .csvMonthly:
                url = dir.appendingPathComponent("סיכום-חודשי-\(stamp).csv")
                try CSVExporter.monthly(ReportBuilder.monthly(model.data, endingAt: month, count: 12)).write(to: url, atomically: true, encoding: .utf8)
            case .pdf:
                url = dir.appendingPathComponent("דוח-\(stamp).pdf")
                try ReportPDF.render(model: model, month: month, to: url)
            }
            share = ShareItem(url: url)
        } catch {
            model.errorMessage = "הייצוא נכשל: \(error.localizedDescription)"
        }
    }
}

/// Renders a printable A4-width monthly report.
@MainActor
enum ReportPDF {
    static func render(model: AppModel, month: MonthKey, to url: URL) throws {
        let view = ReportPDFPage(data: model.data, month: month, today: model.today, isDemo: model.mode == .demo)
            .frame(width: 595)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "he_IL"))
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 595, height: nil)
        var thrown: Error?
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { thrown = CocoaError(.fileWriteUnknown); return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        if let thrown { throw thrown }
    }
}

struct ReportPDFPage: View {
    let data: FinanceData
    let month: MonthKey
    let today: LocalDate
    let isDemo: Bool

    var body: some View {
        let m = ReportBuilder.monthly(data, endingAt: month, count: 1).first!
        let six = ReportBuilder.monthly(data, endingAt: month, count: 6)
        let cats = ReportBuilder.byCategory(data, kind: .expense, range: month.range)
        let s = SummaryCalculator.make(data: data, period: month.range, today: today)
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading) {
                    Text("דוח חודשי — \(Labels.monthName(month.month)) \(String(month.year))").font(.title2.bold())
                    Text("הופק ב־\(today.short)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isDemo { Text("נתוני הדגמה").font(.headline).foregroundStyle(.orange) }
            }
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow { Text("הכנסות"); Text(m.income.ils).monospacedDigit() }
                GridRow { Text("הוצאות"); Text(m.expenses.ils).monospacedDigit() }
                GridRow { Text("תזרים נטו").bold(); Text(m.net.ilsSigned).monospacedDigit().bold() }
                Divider().gridCellColumns(2)
                GridRow { Text("כסף זמין (\(today.short))"); Text(s.available.ils).monospacedDigit() }
                GridRow { Text("חוב בכרטיסי אשראי"); Text(s.creditCardLiability.ils).monospacedDigit() }
                GridRow { Text("חובות אליי"); Text(s.receivablesOutstanding.ils).monospacedDigit() }
                GridRow { Text("חובות שלי"); Text(s.payablesOutstanding.ils).monospacedDigit() }
            }
            Chart {
                ForEach(six) { x in
                    BarMark(x: .value("חודש", Labels.monthName(x.month.month)), y: .value("סכום", x.income.doubleValue)).foregroundStyle(by: .value("סוג", "הכנסות")).position(by: .value("סוג", "הכנסות"))
                    BarMark(x: .value("חודש", Labels.monthName(x.month.month)), y: .value("סכום", x.expenses.doubleValue)).foregroundStyle(by: .value("סוג", "הוצאות")).position(by: .value("סוג", "הוצאות"))
                }
            }
            .chartForegroundStyleScale(["הכנסות": Color.green, "הוצאות": Color.red])
            .frame(height: 180)
            Text("הוצאות לפי קטגוריה").font(.headline)
            ForEach(cats) { c in
                HStack { Text(c.name); Spacer(); Text(ltr(String(format: "%.0f%%", c.share * 100))).foregroundStyle(.secondary); Text(c.amount.ils).monospacedDigit() }
                    .font(.subheadline)
            }
            Text("סכומים צפויים אינם נכללים בכסף הזמין. העברות בין חשבונות ותשלומי אשראי אינם נספרים כהוצאה.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(36)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }
}
