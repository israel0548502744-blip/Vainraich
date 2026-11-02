import SwiftUI
import FinanceCore

struct ForecastView: View {
    @Environment(AppModel.self) private var model
    @State private var days = 30
    @State private var customEnd = LocalDate.today().adding(days: 60)
    @State private var useCustom = false

    private var range: DateRange {
        useCustom ? DateRange(start: model.today, end: max(customEnd, model.today)) : .next(days, from: model.today)
    }

    var body: some View {
        let f = model.forecast(range)
        List {
            Section {
                Picker("טווח", selection: Binding(get: { useCustom ? 0 : days }, set: { v in
                    if v == 0 { useCustom = true } else { useCustom = false; days = v }
                })) {
                    Text("7 ימים").tag(7)
                    Text("30 ימים").tag(30)
                    Text("90 ימים").tag(90)
                    Text("מותאם").tag(0)
                }
                .pickerStyle(.segmented)
                if useCustom {
                    DatePicker("עד תאריך", selection: $customEnd.asDate, in: model.today.date()..., displayedComponents: .date)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                ForecastChartCard(forecast: f)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("סיכום") {
                row("כסף זמין היום", f.startingBalance, Theme.actual)
                row("מאושר — נכנס", f.total(.confirmed, sign: .plus), Theme.actual)
                row("מאושר — יוצא", -f.total(.confirmed, sign: .minus), Theme.liability)
                row("צפוי — נכנס", f.total(.expected, sign: .plus), Theme.expected)
                row("צפוי — יוצא", -f.total(.expected, sign: .minus), Theme.expected)
                row("משוער — חובות אליי", f.total(.estimated, sign: .plus), Theme.receivable)
                HStack {
                    Text("יתרה חזויה בסוף הטווח").font(.headline)
                    Spacer()
                    AmountText(amount: f.endingBalance, font: .headline.monospacedDigit(), colorBySign: true)
                }
                HStack {
                    Text("רק על בסיס מאושר").font(.subheadline)
                    Spacer()
                    AmountText(amount: f.endingConfirmedBalance, font: .subheadline.monospacedDigit(), colorBySign: true)
                }
                if let neg = f.firstNegativeDay {
                    Label("ב־\(neg.date.short) היתרה צפויה לרדת ל־\(neg.projectedBalance.ils)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.liability).font(.subheadline)
                } else if let low = f.lowestDay {
                    Label("הנקודה הנמוכה: \(low.projectedBalance.ils) ב־\(low.date.short)", systemImage: "arrow.down.to.line")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }

            Section {
                Toggle("לכלול חובות שאחרים חייבים לי", isOn: Binding(
                    get: { model.data.settings.includeReceivablesInForecast },
                    set: { var s = model.data.settings; s.includeReceivablesInForecast = $0; model.updateSettings(s) }))
                Toggle("לכלול חובות שאני חייב", isOn: Binding(
                    get: { model.data.settings.includePayablesInForecast },
                    set: { var s = model.data.settings; s.includePayablesInForecast = $0; model.updateSettings(s) }))
            } footer: {
                Text("מאושר = תנועות שהזנת עם סכום ותאריך וחיובי כרטיס ידועים. צפוי = תשלומים קבועים ואירועים. משוער = כסף שתלוי באחרים. אף אחד מהם לא נספר ככסף זמין עד שהוא מתקבל בפועל.")
            }

            Section("מה צפוי (\(f.items.count))") {
                if f.items.isEmpty {
                    Text("אין פריטים צפויים בטווח הזה.").foregroundStyle(Theme.textSecondary)
                }
                ForEach(f.items) { ForecastItemRow(item: $0) }
            }
        }
        .navigationTitle("תחזית תזרים")
    }

    private func row(_ t: String, _ a: Decimal, _ c: Color) -> some View {
        HStack {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(t)
            Spacer()
            AmountText(amount: a, font: .body.monospacedDigit())
        }
    }
}
