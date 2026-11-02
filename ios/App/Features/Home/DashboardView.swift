import SwiftUI
import Charts
import FinanceCore

enum DashboardPeriod: String, CaseIterable, Identifiable {
    case today, week, month, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "היום"
        case .week: return "השבוע"
        case .month: return "החודש"
        case .custom: return "טווח"
        }
    }
}

enum QuickAdd: String, Identifiable {
    case expense, income, transfer, event, debt, scan
    var id: String { rawValue }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var period: DashboardPeriod = .month
    @State private var customStart = LocalDate.today()
    @State private var customEnd = LocalDate.today().adding(days: 30)
    @State private var showingCustom = false
    @State private var quickAdd: QuickAdd?

    private var range: DateRange {
        switch period {
        case .today: return .day(model.today)
        case .week: return .week(containing: model.today)
        case .month: return .month(containing: model.today)
        case .custom: return DateRange(start: customStart, end: customEnd)
        }
    }

    var body: some View {
        let s = model.summary(for: range)
        ScrollView {
            VStack(spacing: 16) {
                DemoBanner()
                if model.data.accounts.isEmpty {
                    EmptyStateView(icon: "building.columns", title: "בוא נתחיל",
                                   message: "הוסף חשבון בנק, מזומן או ביט עם היתרה הנוכחית — וכל המספרים כאן יתעדכנו.",
                                   actionTitle: "הוספת חשבון") { quickAdd = nil; addAccount = true }
                        .card()
                } else {
                    periodPicker
                    heroCard(s)
                    equationCard(s)
                    if let neg = s.forecast.firstNegativeDay { negativeWarning(neg) }
                    tiles(s)
                    forecastChart(s.forecast)
                    upcoming(s.forecast)
                    monthlyFlow
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("הכסף שלי")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { quickAdd = .expense } label: { Label("הוצאה", systemImage: "arrow.up.right") }
                    Button { quickAdd = .income } label: { Label("הכנסה", systemImage: "arrow.down.left") }
                    Button { quickAdd = .transfer } label: { Label("העברה / תשלום כרטיס", systemImage: "arrow.left.arrow.right") }
                    Divider()
                    Button { quickAdd = .event } label: { Label("אירוע", systemImage: "calendar.badge.plus") }
                    Button { quickAdd = .debt } label: { Label("חוב / גבייה", systemImage: "person.badge.clock") }
                    Divider()
                    Button { quickAdd = .scan } label: { Label("ייבוא ממסמך", systemImage: "doc.viewfinder") }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .accessibilityLabel("הוספה")
            }
        }
        .sheet(item: $quickAdd) { item in
            switch item {
            case .expense: TransactionEditor(kind: .expense)
            case .income: TransactionEditor(kind: .income)
            case .transfer: TransactionEditor(kind: .transfer)
            case .event: EventEditor(event: nil, date: model.today)
            case .debt: DebtEditor(debt: nil, direction: .receivable)
            case .scan: NavigationStack { DocumentImportView() }
            }
        }
        .sheet(isPresented: $addAccount) { AccountEditor(account: nil) }
        .sheet(isPresented: $showingCustom) { customRangeSheet }
        .refreshable { model.refreshDay() }
    }

    @State private var addAccount = false

    // MARK: Sections

    private var periodPicker: some View {
        Picker("תקופה", selection: $period) {
            ForEach(DashboardPeriod.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .onChange(of: period) { _, p in if p == .custom { showingCustom = true } }
        .accessibilityLabel("תקופת תצוגה")
    }

    private var customRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("מתאריך", selection: $customStart.asDate, displayedComponents: .date)
                DatePicker("עד תאריך", selection: $customEnd.asDate, in: customStart.date()..., displayedComponents: .date)
            }
            .navigationTitle("טווח מותאם")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("אישור") { showingCustom = false } } }
        }
        .presentationDetents([.medium])
    }

    private func heroCard(_ s: FinancialSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("כסף זמין עכשיו", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.actual)
                Spacer()
                Text(model.today.weekdayAndDay).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            AmountText(amount: s.available, font: Theme.amountFont(.largeTitle), color: s.available < 0 ? Theme.liability : .primary)
            Text("כסף שנמצא בפועל בחשבונות, במזומן ובביט — בלי הכנסות צפויות.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                ForEach([AccountType.bank, .cash, .bit, .other], id: \.self) { type in
                    if let v = s.availableByType[type] {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(type.hebrewName, systemImage: type.icon).font(.caption2).foregroundStyle(Theme.textSecondary)
                            AmountText(amount: v, font: .footnote.weight(.semibold).monospacedDigit())
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func equationCard(_ s: FinancialSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("צפי עד \(range.end == model.today ? "סוף היום" : range.end.short)").font(.headline)
                Spacer()
                NavigationLink { ForecastView() } label: { Text("תחזית מלאה").font(.subheadline) }
            }
            equationRow("כסף זמין", s.available, Theme.actual, "=")
            equationRow("צפוי להיכנס", s.expectedIncome, Theme.expected, "+")
            equationRow("צפוי לצאת", s.expectedExpenses, Theme.liability, "−")
            Divider()
            HStack {
                Text("יתרה חזויה").font(.subheadline.weight(.semibold))
                Spacer()
                AmountText(amount: s.projectedBalance, font: Theme.amountFont(.title3), colorBySign: true)
            }
            let est = s.forecast.total(.estimated, sign: .plus)
            if est > 0 {
                Text("כולל \(est.ils) שאחרים אמורים להחזיר לך (משוער).").font(.caption).foregroundStyle(Theme.receivable)
            }
        }
        .card()
    }

    private func equationRow(_ title: String, _ amount: Decimal, _ color: Color, _ op: String) -> some View {
        HStack {
            Text(op).font(.body.monospaced()).foregroundStyle(Theme.textSecondary).frame(width: 18)
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.subheadline)
            Spacer()
            AmountText(amount: amount, font: .subheadline.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    private func negativeWarning(_ day: ForecastDay) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.liability)
            VStack(alignment: .leading, spacing: 4) {
                Text("היתרה צפויה לרדת מתחת לאפס").font(.subheadline.weight(.semibold))
                Text("ב־\(day.date.long) היתרה החזויה היא \(day.projectedBalance.ils). כדאי להקדים גבייה או לדחות תשלום.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.liability.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func tiles(_ s: FinancialSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(title: "חוב בכרטיסי אשראי", amount: s.creditCardLiability, icon: "creditcard", color: Theme.liability,
                     subtitle: "ירד מהבנק ביום החיוב")
            StatTile(title: "חייבים לי", amount: s.receivablesOutstanding, icon: "person.2", color: Theme.receivable,
                     subtitle: s.overdueReceivables > 0 ? "באיחור: \(s.overdueReceivables.ils)" : "לא כלול בכסף הזמין")
            StatTile(title: "אני חייב", amount: s.payablesOutstanding, icon: "hand.raised", color: Theme.expected)
            StatTile(title: "תזרים \(period.title)", amount: s.periodNetCashFlow, icon: "arrow.up.arrow.down",
                     color: s.periodNetCashFlow < 0 ? Theme.liability : Theme.actual,
                     subtitle: "נכנס \(s.periodIncome.ils) · יצא \(s.periodExpenses.ils)")
        }
    }

    private func forecastChart(_ f: Forecast) -> some View {
        ForecastChartCard(forecast: f.days.count >= 7 ? f : model.forecast(.next(30, from: model.today)))
    }

    private func upcoming(_ f: Forecast) -> some View {
        let items = model.forecast(.next(14, from: model.today)).items.prefix(6)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "תשלומים קרובים")
            if items.isEmpty {
                Text("אין תשלומים צפויים בשבועיים הקרובים.").font(.subheadline).foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(Array(items)) { item in ForecastItemRow(item: item) }
            }
        }
        .card()
    }

    private var monthlyFlow: some View {
        let months = ReportBuilder.monthly(model.data, endingAt: MonthKey(model.today), count: 6)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "הכנסות והוצאות — 6 חודשים")
            Chart {
                ForEach(months) { m in
                    BarMark(x: .value("חודש", Labels.monthName(m.month.month)), y: .value("סכום", m.income.doubleValue))
                        .foregroundStyle(by: .value("סוג", "הכנסות"))
                        .position(by: .value("סוג", "הכנסות"))
                    BarMark(x: .value("חודש", Labels.monthName(m.month.month)), y: .value("סכום", m.expenses.doubleValue))
                        .foregroundStyle(by: .value("סוג", "הוצאות"))
                        .position(by: .value("סוג", "הוצאות"))
                }
            }
            .chartForegroundStyleScale(["הכנסות": Theme.actual, "הוצאות": Theme.liability])
            .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(Decimal(d).ilsCompact) } } } }
            .frame(height: 180)
        }
        .card()
    }
}

/// One expected item with its confidence.
struct ForecastItemRow: View {
    @Environment(AppModel.self) private var model
    let item: ForecastItem

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(item.confidence.color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.date.relative(to: model.today))
                    StatusBadge(text: item.confidence.hebrewName, color: item.confidence.color)
                    if item.isOverdue { StatusBadge(text: "באיחור", color: Theme.liability) }
                }
                .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            AmountText(amount: item.amount, font: .subheadline.weight(.semibold).monospacedDigit(), colorBySign: true, showPlus: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Interactive projected-balance chart (actual vs confirmed-only).
struct ForecastChartCard: View {
    let forecast: Forecast
    @State private var selected: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("יתרה חזויה").font(.headline)
                Spacer()
                if let sel = selectedDay {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(sel.date.short).font(.caption2).foregroundStyle(Theme.textSecondary)
                        AmountText(amount: sel.projectedBalance, font: .subheadline.weight(.semibold).monospacedDigit(), colorBySign: true)
                    }
                }
            }
            Chart {
                ForEach(forecast.days) { d in
                    AreaMark(x: .value("תאריך", d.date.date()), y: .value("יתרה", d.projectedBalance.doubleValue))
                        .foregroundStyle(LinearGradient(colors: [Theme.brand.opacity(0.25), Theme.brand.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("תאריך", d.date.date()), y: .value("יתרה", d.projectedBalance.doubleValue), series: .value("סדרה", "הכול"))
                        .foregroundStyle(Theme.brand)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("תאריך", d.date.date()), y: .value("יתרה", d.confirmedBalance.doubleValue), series: .value("סדרה", "מאושר"))
                        .foregroundStyle(Theme.actual.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .interpolationMethod(.monotone)
                }
                RuleMark(y: .value("אפס", 0)).foregroundStyle(Theme.liability.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                if let sel = selectedDay {
                    RuleMark(x: .value("נבחר", sel.date.date())).foregroundStyle(Theme.neutral.opacity(0.4))
                    PointMark(x: .value("נבחר", sel.date.date()), y: .value("יתרה", sel.projectedBalance.doubleValue)).foregroundStyle(Theme.brand)
                }
            }
            .chartXSelection(value: $selected)
            .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(Decimal(d).ilsCompact) } } } }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { v in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.defaultDigits)) } }
            .frame(height: 200)
            HStack(spacing: 14) {
                legend(Theme.brand, "כולל צפוי ומשוער", dashed: false)
                legend(Theme.actual, "רק מאושר", dashed: true)
            }
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("גרף יתרה חזויה. בסוף התקופה: \(forecast.endingBalance.ils)")
    }

    private var selectedDay: ForecastDay? {
        guard let selected else { return nil }
        let d = LocalDate(selected)
        return forecast.days.first { $0.date == d }
    }

    private func legend(_ c: Color, _ t: String, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(c).frame(width: 14, height: dashed ? 2 : 3)
            Text(t)
        }
    }
}
