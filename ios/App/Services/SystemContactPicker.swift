import SwiftUI
import ContactsUI
import FinanceCore

/// Apple's contact picker. Needs no address-book permission: the user picks one person
/// and only that person's name/phone/e-mail is shared with the app.
struct SystemContactPicker: UIViewControllerRepresentable {
    let onPick: (Contact) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let vc = CNContactPickerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: SystemContactPicker
        init(_ parent: SystemContactPicker) { self.parent = parent }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let c = Contact(
                name: name.isEmpty ? (contact.organizationName.isEmpty ? "ללא שם" : contact.organizationName) : name,
                phone: contact.phoneNumbers.first?.value.stringValue,
                email: contact.emailAddresses.first.map { String($0.value) },
                systemContactID: contact.identifier
            )
            parent.onPick(c)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {}
    }
}
