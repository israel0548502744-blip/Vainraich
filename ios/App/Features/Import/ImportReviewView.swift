import SwiftUI
import FinanceCore
import DocumentAI

/// Shows what was read from the document. Nothing is saved until the user taps "add".
struct ImportReviewView: View {
    @Environment(AppModel.self) private var model
    let onDone: () -> Void

    @State private var candidates: [ImportCandidate]
    @State private var applyBalance: Set<String> = []
    @State private var editing: ImportCandidate?
    @State private var error: String?
    private let plan: ImportPlan

    init(plan: ImportPlan, onDone: @escaping () -> Void) {
        self.plan = plan
        self.onDone = onDone
        _candidates = State(initialValue: plan.candidates)
    }

    private var selected: [ImportCandidate] { candidates.filter(\.include) }

    var body: some View {
        List {
            Section {
                LabeledContent("סוג מסמך", value: plan.result.documentKind.hebrewName)
                if let i = plan.result.institution { LabeledContent("מוסד", value: i) }
                if let h = plan.result.accountHint { LabeledContent("חשבון / כרטיס", value: ltr(h)) }
                if let d = plan.result.statementDate { LabeledContent("נכון לתאריך", value: d.short) }
                if let by = plan.result.producedBy { LabeledContent("נקרא על ידי", value: by).font(.caption) }
            }

            if !plan.warnings.isEmpty {
                Section {
                    ForEach(plan.warnings, id: \.self) { w in
                        Label(w, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.expected)
                    }
                }
            }

            if !plan.balanceSuggestions.isEmpty {
                Section {
                    ForEach(plan.balanceSuggestions) { s in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.label).font(.subheadline.weight(.semibold))
                            HStack { Text("לפי המסמך"); Spacer(); AmountText(amount: s.amount) }
                            HStack { Text("באפליקציה (אחרי הייבוא)"); Spacer(); AmountText(amount: appBalanceAfterSelection(s)) }
                            let diff = (s.amount - appBalanceAfterSelection(s)).rounded(scale: 2)
                            if diff != 0 {
                                Toggle(isOn: Binding(get: { applyBalance.contains(s.id) }, set: { if $0 { applyBalance.insert(s.id) } else { applyBalance.remove(s.id) } })) {
                                    Text("לעדכן את היתרה לפי המסמך (הפרש \(diff.ilsSigned))").font(.footnote)
                                }
                            } else {
                                Label("היתרה תואמת", systemImage: "checkmark.seal").foregroundStyle(Theme.actual).font(.footnote)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("יתרות")
                }
            }

            Section {
                if candidates.isEmpty { Text("לא נמצאו תנועות.").foregroundStyle(Theme.textSecondary) }
                ForEach($candidates) { $c in
                    HStack(alignment: .top, spacing: 10) {
                        Button { c.include.toggle() } label: {
                            Image(systemName: c.include ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(c.include ? Theme.brand : Theme.neutral)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(c.include ? "נבחר" : "לא נבחר")
                        Button { editing = c } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                TransactionRow(transaction: c.transaction)
                                if let note = c.note {
                                    Text(note).font(.caption2).foregroundStyle(c.duplicateOf != nil ? Theme.expected : Theme.textSecondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .opacity(c.include ? 1 : 0.55)
                }
            } header: {
                HStack {
                    Text("תנועות (\(selected.count) מתוך \(candidates.count))")
                    Spacer()
                    Button(selected.count == candidates.count ? "ביטול הכל" : "בחירת הכל") {
                        let all = selected.count != candidates.count
                        for i in candidates.indices { candidates[i].include = all }
                    }
                    .font(.caption)
                }
            } footer: {
                Text("לחיצה על שורה פותחת עריכה. שורות שנראות כפולות לא מסומנות כברירת מחדל.")
            }
        }
        .navigationTitle("בדיקה לפני שמירה")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: apply) {
                Text(buttonTitle).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selected.isEmpty && applyBalance.isEmpty)
            .padding()
            .background(.bar)
        }
        .sheet(item: $editing) { c in
            TransactionEditor(draft: c.transaction) { updated in
                if let i = candidates.firstIndex(where: { $0.id == c.id }) {
                    candidates[i].transaction = updated
                    candidates[i].include = true
                }
            }
        }
        .alert("לא ניתן לשמור", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("הבנתי", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private var buttonTitle: String {
        var parts: [String] = []
        if !selected.isEmpty { parts.append("הוספת \(selected.count) תנועות") }
        if !applyBalance.isEmpty { parts.append("עדכון יתרה") }
        return parts.isEmpty ? "לא נבחר דבר" : parts.joined(separator: " + ")
    }

    private func appBalanceAfterSelection(_ s: BalanceSuggestion) -> Decimal {
        let current = model.balance(of: plan.targetAccountID)
        return current + selected.reduce(Decimal(0)) { $0 + Ledger.effect(of: $1.transaction, on: plan.targetAccountID) }
    }

    private func apply() {
        let txs = selected.map(\.transaction)
        let adjustments = plan.balanceSuggestions.filter { applyBalance.contains($0.id) }.compactMap { s -> FinanceTransaction? in
            var adjusted = s
            adjusted.appBalance = appBalanceAfterSelection(s)
            return ImportPlanner.adjustment(for: adjusted, accountID: plan.targetAccountID, today: model.today)
        }
        do {
            let n = try model.applyImport(txs, adjustments: adjustments)
            let matches = model.eventPaymentQuestions.filter { $0.kind == .possibleMatch }.count
            model.show(matches > 0 ? "נוספו \(n) רשומות · \(matches) אירועים מחכים לאישור תשלום" : "נוספו \(n) רשומות")
            onDone()
        } catch {
            self.error = hebrewMessage(for: error)
        }
    }
}
