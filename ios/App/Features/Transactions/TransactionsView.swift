import SwiftUI
import FinanceCore

struct TransactionsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = TransactionFilter()
    @State private var showingFilters = false
    @State private var editing: FinanceTransaction?
    @State private var newKind: TransactionKind?

    var body: some View {
        let list = filter.apply(to: model.data)
        let groups = Dictionary(grouping: list, by: \.date).sorted { $0.key > $1.key }
        List {
            if model.mode == .demo {
                DemoBanner().listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            if filter.isActive {
                Section {
                    HStack {
                        Label("מסונן: \(list.count) תנועות", systemImage: "line.3.horizontal.decrease.circle.fill")
                        Spacer()
                        Button("ניקוי") { filter = TransactionFilter(searchText: filter.searchText) }
                    }
                    .font(.subheadline)
                }
            }
            let pending = list.filter { $0.status == .pending && $0.date <= model.today }
            if !pending.isEmpty && !filter.isActive {
                Section {
                    ForEach(pending) { t in
                        row(t).swipeActions(edge: .leading) {
                            Button { model.confirm(t.id, on: t.date) ; model.show("סומן כבוצע") } label: { Label("בוצע", systemImage: "checkmark") }.tint(Theme.actual)
                        }
                    }
                } header: {
                    Text("ממתינות לאישור")
                } footer: {
                    Text("החלק ימינה כדי לסמן שהתשלום בוצע. עד אז הוא לא משנה את היתרה בפועל.")
                }
            }
            ForEach(groups, id: \.key) { group in
                Section {
                    ForEach(group.value) { t in row(t) }
                } header: {
                    dayHeader(group.key, group.value)
                }
            }
        }
        .overlay {
            if list.isEmpty {
                if model.data.transactions.isEmpty {
                    EmptyStateView(icon: "list.bullet.rectangle", title: "עוד אין תנועות",
                                   message: "הוסף הוצאה או הכנסה, או ייבא דף חשבון מצולם — והן יופיעו כאן.",
                                   actionTitle: "הוספת תנועה") { newKind = .expense }
                } else {
                    ContentUnavailableView.search(text: filter.searchText)
                }
            }
        }
        .searchable(text: $filter.searchText, prompt: "חיפוש לפי תיאור, קטגוריה, חשבון או סכום")
        .navigationTitle("תנועות")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { newKind = .expense } label: { Label("הוצאה", systemImage: "arrow.up.right") }
                    Button { newKind = .income } label: { Label("הכנסה", systemImage: "arrow.down.left") }
                    Button { newKind = .transfer } label: { Label("העברה בין חשבונות", systemImage: "arrow.left.arrow.right") }
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("הוספת תנועה")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { showingFilters = true } label: { Label("סינון", systemImage: "line.3.horizontal.decrease.circle") }
            }
        }
        .sheet(isPresented: $showingFilters) { FilterSheet(filter: $filter) }
        .sheet(item: $editing) { t in TransactionEditor(existing: t) }
        .sheet(item: $newKind) { k in TransactionEditor(kind: k) }
    }

    private func row(_ t: FinanceTransaction) -> some View {
        Button { editing = t } label: { TransactionRow(transaction: t, showDate: false) }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { model.deleteTransaction(t.id) } label: { Label("מחיקה", systemImage: "trash") }
            }
            .contextMenu {
                if t.status == .pending {
                    Button { model.confirm(t.id) } label: { Label("סמן כבוצע היום", systemImage: "checkmark.circle") }
                }
                Button { var c = t; c.id = UUID(); c.date = model.today; c.status = .completed; c.recurringID = nil; c.occurrenceDate = nil; c.externalID = nil; c.attachmentFileName = nil; c.createdAt = Date(); try? model.save(c); model.show("שוכפל להיום") } label: {
                    Label("שכפול להיום", systemImage: "plus.square.on.square")
                }
                Button(role: .destructive) { model.deleteTransaction(t.id) } label: { Label("מחיקה", systemImage: "trash") }
            }
    }

    private func dayHeader(_ date: LocalDate, _ items: [FinanceTransaction]) -> some View {
        let net = items.filter(\.countsInReports).reduce(Decimal(0)) { $0 + ($1.kind == .income ? $1.amount : -$1.amount) }
        return HStack {
            Text(date == model.today ? "היום" : date.weekdayAndDay)
            Spacer()
            if net != 0 { Text(net.ilsSigned).monospacedDigit() }
        }
    }
}

extension TransactionKind: Identifiable { public var id: String { rawValue } }

struct FilterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: TransactionFilter
    @State private var useDates = false
    @State private var start = LocalDate.today().startOfMonth
    @State private var end = LocalDate.today()

    var body: some View {
        NavigationStack {
            Form {
                Section("סוג") {
                    ForEach([TransactionKind.expense, .income, .transfer, .adjustment]) { k in
                        toggleRow(k.hebrewName, filter.kinds.contains(k)) { on in if on { filter.kinds.insert(k) } else { filter.kinds.remove(k) } }
                    }
                }
                Section("סטטוס") {
                    ForEach(TransactionStatus.allCases, id: \.self) { s in
                        toggleRow(s.hebrewName, filter.statuses.contains(s)) { on in if on { filter.statuses.insert(s) } else { filter.statuses.remove(s) } }
                    }
                }
                Section("חשבון") {
                    ForEach(model.data.accounts) { a in
                        toggleRow(a.name, filter.accountIDs.contains(a.id)) { on in if on { filter.accountIDs.insert(a.id) } else { filter.accountIDs.remove(a.id) } }
                    }
                }
                Section("קטגוריה") {
                    ForEach(model.data.categories.filter { !$0.isArchived }) { c in
                        toggleRow(c.name, filter.categoryIDs.contains(c.id)) { on in if on { filter.categoryIDs.insert(c.id) } else { filter.categoryIDs.remove(c.id) } }
                    }
                }
                Section("תאריכים") {
                    Toggle("טווח תאריכים", isOn: $useDates)
                    if useDates {
                        DatePicker("מ־", selection: $start.asDate, displayedComponents: .date)
                        DatePicker("עד", selection: $end.asDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("סינון")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("איפוס") { filter = TransactionFilter(searchText: filter.searchText); useDates = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("הצגה") {
                        filter.dateRange = useDates ? DateRange(start: start, end: end) : nil
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let r = filter.dateRange { useDates = true; start = r.start; end = r.end }
            }
        }
    }

    private func toggleRow(_ title: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Button { set(!on) } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if on { Image(systemName: "checkmark").foregroundStyle(Theme.brand) }
            }
        }
    }
}
