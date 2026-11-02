import SwiftUI
import PhotosUI
import VisionKit
import UniformTypeIdentifiers
import FinanceCore
import DocumentAI

/// Import balances and transactions from a statement, balance confirmation, receipt or screenshot.
struct DocumentImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var preselectedAccountID: UUID? = nil

    @State private var accountID: UUID?
    @State private var picked: PickedDocument?
    @State private var pickedDescription = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showScanner = false
    @State private var showFileImporter = false
    @State private var showPaste = false
    @State private var pastedText = ""
    @State private var isWorking = false
    @State private var plan: PlanBox?
    @State private var error: String?
    @State private var provider = AISettings.provider
    @State private var addingAccount = false

    var body: some View {
        Form {
            if model.mode == .demo {
                Section { Text("במצב הדגמה הייבוא נשמר רק לזמן ההדגמה.").font(.footnote).foregroundStyle(Theme.expected) }
            }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("צלם או בחר מסמך — אישור יתרה, דף תנועות, פירוט אשראי, קבלה או צילום מסך מביט. הנתונים יוצגו לבדיקה ורק אחרי האישור שלך יישמרו.")
                        .font(.subheadline)
                }
            }

            Section("1. לאיזה חשבון") {
                if model.activeAccounts.isEmpty {
                    Button { addingAccount = true } label: { Label("קודם צריך להוסיף חשבון", systemImage: "plus.circle") }
                } else {
                    AccountPicker(title: "חשבון", selection: $accountID)
                }
            }

            Section("2. המסמך") {
                if VNDocumentCameraViewController.isSupported {
                    Button { showScanner = true } label: { Label("סריקה במצלמה", systemImage: "doc.viewfinder") }
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: 6, matching: .images) {
                    Label("תמונה או צילום מסך", systemImage: "photo.on.rectangle")
                }
                Button { showFileImporter = true } label: { Label("קובץ PDF / תמונה מהקבצים", systemImage: "folder") }
                Button { showPaste = true } label: { Label("הדבקת טקסט", systemImage: "doc.on.clipboard") }
                if picked != nil {
                    Label(pickedDescription, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.actual)
                }
            }

            Section {
                NavigationLink { AISettingsView() } label: {
                    HStack {
                        Text("מנוע קריאה")
                        Spacer()
                        Text(provider.name).foregroundStyle(Theme.textSecondary)
                    }
                }
                Text(provider.priceNote).font(.caption).foregroundStyle(Theme.textSecondary)
                if AISettings.textOnlyRedacted && provider.isRemote {
                    Label("מצב פרטיות: יישלח טקסט בלבד, מספרי זהות וחשבון יוסתרו", systemImage: "eye.slash").font(.caption).foregroundStyle(Theme.brand)
                }
            } header: { Text("3. קריאה") }

            Section {
                Button(action: run) {
                    HStack {
                        Spacer()
                        if isWorking { ProgressView().padding(.trailing, 6); Text("קורא את המסמך…") } else { Label("קריאת המסמך", systemImage: "sparkles") }
                        Spacer()
                    }
                }
                .disabled(picked == nil || accountID == nil || isWorking)
                .fontWeight(.semibold)
            }
        }
        .navigationTitle("ייבוא ממסמך")
        .onAppear {
            provider = AISettings.provider
            if accountID == nil { accountID = preselectedAccountID ?? model.defaultAccountID }
        }
        .onChange(of: photoItems) { _, items in loadPhotos(items) }
        .sheet(isPresented: $showScanner) {
            DocumentScanner { images in
                picked = .images(images)
                pickedDescription = "נסרקו \(images.count) עמודים"
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .image, .plainText, .commaSeparatedText]) { result in
            loadFile(result)
        }
        .sheet(isPresented: $showPaste) { pasteSheet }
        .sheet(isPresented: $addingAccount) { AccountEditor(account: nil) }
        .navigationDestination(item: $plan) { box in
            ImportReviewView(plan: box.plan) { dismissAll() }
        }
        .alert("לא הצלחתי לקרוא", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("הבנתי", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private var pasteSheet: some View {
        NavigationStack {
            TextEditor(text: $pastedText)
                .padding()
                .navigationTitle("הדבקת טקסט")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("ביטול") { showPaste = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("שימוש") {
                            if !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                picked = .text(pastedText)
                                pickedDescription = "טקסט מודבק (\(pastedText.count) תווים)"
                            }
                            showPaste = false
                        }
                    }
                }
        }
    }

    private func dismissAll() {
        plan = nil
        picked = nil
        dismiss()
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { images.append(img) }
            }
            if !images.isEmpty {
                picked = .images(images)
                pickedDescription = images.count == 1 ? "נבחרה תמונה" : "נבחרו \(images.count) תמונות"
            }
            photoItems = []
        }
    }

    private func loadFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { error = "לא הצלחתי לפתוח את הקובץ."; return }
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .pdf) == true {
            picked = .pdf(data)
        } else if type?.conforms(to: .image) == true, let img = UIImage(data: data) {
            picked = .images([img])
        } else if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1255) {
            picked = .text(text)
        } else {
            error = "סוג הקובץ לא נתמך."
            return
        }
        pickedDescription = url.lastPathComponent
    }

    private func run() {
        guard let picked, let accountID else { return }
        isWorking = true
        let p = AISettings.provider
        provider = p
        let extractor = AISettings.extractor(for: p)
        let textOnly = AISettings.textOnlyRedacted && p.isRemote
        Task {
            defer { isWorking = false }
            do {
                let result = try await DocumentPreprocessor.extract(picked, using: extractor, textOnlyRedacted: textOnly)
                plan = PlanBox(plan: ImportPlanner.plan(result: result, targetAccountID: accountID, data: model.data, today: model.today))
            } catch {
                self.error = hebrewMessage(for: error)
            }
        }
    }
}

extension String.Encoding {
    /// Hebrew Windows code page used by some Israeli bank exports.
    static let windowsCP1255 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsHebrew.rawValue)))
}

/// Hashable wrapper so a plan can drive `navigationDestination(item:)`.
struct PlanBox: Hashable {
    let plan: ImportPlan
    let id = UUID()
    static func == (l: PlanBox, r: PlanBox) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// VisionKit document camera (edge detection, perspective correction, multi-page).
struct DocumentScanner: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ p: DocumentScanner) { parent = p }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onScan(images)
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.dismiss() }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.dismiss() }
    }
}
