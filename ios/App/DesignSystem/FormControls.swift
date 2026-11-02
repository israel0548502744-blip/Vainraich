import SwiftUI
import FinanceCore

/// Text field for money. Keeps the raw text so the user can type freely; parses with `Decimal.parseMoney`.
struct MoneyField: View {
    let title: String
    @Binding var text: String
    var large = false

    var body: some View {
        HStack(spacing: 6) {
            Text("₪").font(large ? Theme.amountFont(.title) : .body).foregroundStyle(Theme.textSecondary)
            TextField(title, text: $text)
                .keyboardType(.decimalPad)
                .font(large ? Theme.amountFont(.title) : .body.monospacedDigit())
                .multilineTextAlignment(.leading)
                .environment(\.layoutDirection, .leftToRight)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityLabel(title)
    }
}

extension Decimal {
    /// Text for editing fields ("1234.5" → "1234.50", whole numbers without decimals).
    var editingText: String {
        let r = rounded(scale: 2)
        let s = r.plainString
        return s.hasSuffix(".00") ? String(s.dropLast(3)) : s
    }
}

/// Picker of accounts.
struct AccountPicker: View {
    @Environment(AppModel.self) private var model
    let title: String
    @Binding var selection: UUID?
    var excluding: UUID? = nil
    var allowNone = false

    var body: some View {
        Picker(title, selection: $selection) {
            if allowNone || selection == nil { Text("לא נבחר").tag(UUID?.none) }
            ForEach(model.activeAccounts.filter { $0.id != excluding }) { a in
                Label(a.name, systemImage: a.type.icon).tag(Optional(a.id))
            }
        }
    }
}

/// Picker of categories of one kind.
struct CategoryPicker: View {
    @Environment(AppModel.self) private var model
    let kind: FinanceCategory.Kind
    @Binding var selection: UUID?

    var body: some View {
        Picker("קטגוריה", selection: $selection) {
            Text("ללא קטגוריה").tag(UUID?.none)
            ForEach(model.data.categories.filter { $0.kind == kind && !$0.isArchived }) { c in
                Label(c.name, systemImage: c.icon).tag(Optional(c.id))
            }
        }
        .pickerStyle(.navigationLink)
    }
}

/// Picker of contacts with inline creation.
struct ContactPicker: View {
    @Environment(AppModel.self) private var model
    let title: String
    @Binding var selection: UUID?
    var allowNone = true
    @State private var newName = ""
    @State private var showingNew = false
    @State private var showingSystemPicker = false

    var body: some View {
        Picker(title, selection: $selection) {
            if allowNone || selection == nil { Text("ללא").tag(UUID?.none) }
            ForEach(model.data.contacts.sorted { $0.name < $1.name }) { c in
                Text(c.name).tag(Optional(c.id))
            }
        }
        Button { showingNew = true } label: { Label("איש קשר חדש", systemImage: "person.badge.plus") }
        Button { showingSystemPicker = true } label: { Label("בחירה מאנשי הקשר באייפון", systemImage: "person.crop.circle") }
            .alert("איש קשר חדש", isPresented: $showingNew) {
                TextField("שם", text: $newName)
                Button("הוספה") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { selection = model.addContact(Contact(name: name)).id }
                    newName = ""
                }
                Button("ביטול", role: .cancel) { newName = "" }
            }
            .sheet(isPresented: $showingSystemPicker) {
                SystemContactPicker { contact in
                    selection = model.addOrFindContact(contact).id
                }
                .ignoresSafeArea()
            }
    }
}
