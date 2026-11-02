import SwiftUI
import UniformTypeIdentifiers
import FinanceCore
import DocumentAI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(BiometricLock.self) private var lock
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var share: ShareItem?
    @State private var importingBackup = false
    @State private var pendingBackup: FinanceData?
    @State private var confirmErase = false
    @State private var lockOn = UserDefaults.standard.bool(forKey: "appLockEnabled")

    var body: some View {
        Form {
            Section("נתונים") {
                LabeledContent("מצב", value: model.mode == .demo ? "הדגמה (לא נשמר)" : "הנתונים שלי")
                if model.mode == .demo {
                    Button("מעבר לנתונים שלי") { model.exitDemo() }
                } else {
                    Button("צפייה בהדגמה") { model.enterDemo() }
                }
                LabeledContent("חשבונות", value: "\(model.data.accounts.count)")
                LabeledContent("תנועות", value: "\(model.data.transactions.count)")
            }

            Section("חיבורים") {
                NavigationLink { AISettingsView() } label: { Label("בינה מלאכותית לקריאת מסמכים", systemImage: "sparkles") }
                NavigationLink { CalendarSettingsView() } label: { Label("יומן האייפון", systemImage: "calendar") }
                NavigationLink { NotificationSettingsView() } label: { Label("התראות ותזכורות", systemImage: "bell") }
                NavigationLink { IntegrationsInfoView() } label: { Label("בנקים, אשראי וביט", systemImage: "link") }
            }

            Section {
                Toggle(isOn: Binding(get: { lockOn }, set: { on in
                    if on { Task { lockOn = await lock.enable() } } else { lock.disable(); lockOn = false }
                })) {
                    Label("נעילה עם \(BiometricLock.biometryName)", systemImage: "faceid")
                }
                .disabled(!BiometricLock.canAuthenticate)
            } header: { Text("אבטחה") } footer: {
                Text("הנתונים נשמרים מוצפנים במכשיר בלבד. מפתחות API נשמרים ב-Keychain.")
            }

            Section("תחזית") {
                Toggle("לכלול חובות אליי בתחזית", isOn: Binding(
                    get: { model.data.settings.includeReceivablesInForecast },
                    set: { var s = model.data.settings; s.includeReceivablesInForecast = $0; model.updateSettings(s) }))
                Toggle("לכלול חובות שלי בתחזית", isOn: Binding(
                    get: { model.data.settings.includePayablesInForecast },
                    set: { var s = model.data.settings; s.includePayablesInForecast = $0; model.updateSettings(s) }))
                Stepper("תזכורת \(model.data.settings.reminderLeadDays) ימים לפני מועד", value: Binding(
                    get: { model.data.settings.reminderLeadDays },
                    set: { var s = model.data.settings; s.reminderLeadDays = $0; model.updateSettings(s) }), in: 0...14)
            }

            Section {
                Button { exportBackup() } label: { Label("גיבוי מלא (קובץ)", systemImage: "externaldrive.badge.icloud") }
                Button { importingBackup = true } label: { Label("שחזור מגיבוי", systemImage: "arrow.counterclockwise") }
                Button { exportCSV() } label: { Label("ייצוא כל התנועות (CSV)", systemImage: "tablecells") }
            } header: { Text("גיבוי וייצוא") } footer: {
                Text("מומלץ לשמור גיבוי ב-iCloud Drive או בקבצים מדי פעם. הגיבוי כולל את כל הנתונים (ללא מפתחות API).")
            }

            Section {
                Button("מחיקת כל הנתונים", role: .destructive) { confirmErase = true }
                    .disabled(model.mode == .demo)
            }

            Section("אודות") {
                LabeledContent("גרסה", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                Text("האפליקציה לא מתחברת לבנקים ולא שומרת סיסמאות. נתונים נכנסים ידנית או ממסמכים שאתה בוחר לייבא. האפליקציה אינה מספקת ייעוץ פיננסי.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
        }
        .navigationTitle("הגדרות")
        .sheet(item: $share) { ShareSheet(items: [$0.url]) }
        .fileImporter(isPresented: $importingBackup, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { pendingBackup = try FinanceFileStore.decode(Data(contentsOf: url)) }
            catch { model.errorMessage = "הקובץ אינו גיבוי תקין של האפליקציה." }
        }
        .confirmationDialog("לשחזר מהגיבוי?", isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } }), titleVisibility: .visible) {
            Button("שחזור (יחליף את הנתונים הנוכחיים)", role: .destructive) {
                if let b = pendingBackup { model.replaceAll(with: b); hasOnboarded = true; model.show("הנתונים שוחזרו") }
                pendingBackup = nil
            }
        } message: {
            if let b = pendingBackup { Text("בגיבוי: \(b.accounts.count) חשבונות, \(b.transactions.count) תנועות.") }
        }
        .confirmationDialog("למחוק את כל הנתונים?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("מחיקה לצמיתות", role: .destructive) {
                model.eraseAllPersonalData()
                hasOnboarded = false
            }
        } message: { Text("כל החשבונות, התנועות, האירועים והחובות יימחקו מהמכשיר. אי אפשר לבטל.") }
    }

    private func exportBackup() {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("גיבוי-כספים-\(model.today.isoString).json")
            try model.backupData().write(to: url, options: .atomic)
            share = ShareItem(url: url)
        } catch { model.errorMessage = "הגיבוי נכשל." }
    }

    private func exportCSV() {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("כל-התנועות-\(model.today.isoString).csv")
            try CSVExporter.transactions(model.data.transactions, data: model.data).write(to: url, atomically: true, encoding: .utf8)
            share = ShareItem(url: url)
        } catch { model.errorMessage = "הייצוא נכשל." }
    }
}

// MARK: - AI

struct AISettingsView: View {
    @State private var provider = AISettings.provider
    @State private var key = ""
    @State private var model = ""
    @State private var baseURL = AISettings.customBaseURL
    @State private var textOnly = AISettings.textOnlyRedacted
    @State private var models: [String] = []
    @State private var freeOnly = true
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOK = false

    var body: some View {
        Form {
            Section {
                Picker("מנוע", selection: $provider) {
                    ForEach(AIProviderID.allCases) { p in
                        if p != .appleIntelligence || AISettings.appleIntelligenceAvailable {
                            VStack(alignment: .leading) {
                                Text(p.name)
                                Text(p.priceNote).font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            .tag(p)
                        }
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: provider) { _, p in
                    AISettings.provider = p
                    loadFields()
                }
            } header: { Text("מי יקרא את המסמכים") } footer: {
                Text("כל הספקים מקבלים מפתח API אישי שלך — האפליקציה לא גובה כסף ולא שולחת לשרת שלה. אפשר להחליף ספק בכל רגע.")
            }

            if provider.needsKey || provider == .custom {
                Section {
                    if provider == .custom {
                        TextField("כתובת השרת (…/v1)", text: $baseURL)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .environment(\.layoutDirection, .leftToRight)
                            .onSubmit { AISettings.customBaseURL = baseURL }
                    }
                    SecureField("מפתח API", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                        .onSubmit { AISettings.setAPIKey(key, for: provider) }
                    if let url = provider.keyURL {
                        Link(destination: url) { Label("איך משיגים מפתח (נפתח באתר הספק)", systemImage: "key") }
                    }
                } header: { Text("חיבור") } footer: {
                    Text("המפתח נשמר ב-Keychain של האייפון בלבד ולא נכלל בגיבויים.")
                }
            }

            if provider.isRemote {
                Section {
                    TextField("מודל", text: $model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                        .onSubmit { AISettings.setModel(model, for: provider) }
                    Button {
                        Task { await loadModels() }
                    } label: {
                        HStack { Label("טעינת רשימת מודלים ובדיקת חיבור", systemImage: "arrow.triangle.2.circlepath"); if testing { Spacer(); ProgressView() } }
                    }
                    .disabled(testing)
                    if let testResult {
                        Label(testResult, systemImage: testOK ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(testOK ? Theme.actual : Theme.liability).font(.footnote)
                    }
                    if !models.isEmpty {
                        if provider == .openRouter { Toggle("רק מודלים חינמיים", isOn: $freeOnly) }
                        let shown = provider == .openRouter && freeOnly ? models.filter { $0.hasSuffix(":free") || $0.hasPrefix("openrouter/") } : models
                        Picker("בחירה מהרשימה", selection: Binding(get: { model }, set: { model = $0; AISettings.setModel($0, for: provider) })) {
                            if !shown.contains(model) { Text(model.isEmpty ? "לא נבחר" : model).tag(model) }
                            ForEach(shown, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.navigationLink)
                    }
                } header: { Text("מודל") } footer: {
                    Text("בחר מודל שתומך בתמונות כדי לקרוא צילומים. אם המודל לא תומך — הפעל את מצב הטקסט בלבד למטה.")
                }

                Section {
                    Toggle("שליחת טקסט בלבד עם הסתרת מספרים", isOn: $textOnly)
                        .onChange(of: textOnly) { _, v in AISettings.textOnlyRedacted = v }
                } header: { Text("פרטיות") } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("במצב הזה המסמך הופך לטקסט על האייפון, ומספרי ת.ז., חשבון וכרטיס מוחלפים בארבע הספרות האחרונות לפני השליחה. הדיוק בטבלאות מורכבות עשוי לרדת.")
                        if !DocumentPreprocessor.ocrSupportsHebrew {
                            Text("שים לב: זיהוי טקסט בעברית מתמונה לא נתמך בגרסת iOS הזו. קובצי PDF דיגיטליים עדיין יעבדו.").foregroundStyle(Theme.expected)
                        }
                        if let note = provider.privacyNote { Text(note) }
                    }
                }
            } else {
                Section {
                    Text(provider == .onDevice
                         ? "קורא קובצי PDF דיגיטליים, טקסט מודבק וצילומים (בשפות שזיהוי הטקסט במכשיר תומך בהן). לא נשלח שום דבר לאינטרנט. מתאים לדפי תנועות פשוטים; לצילומים מורכבים מומלץ ספק בינה מלאכותית."
                         : "המודל של Apple רץ על האייפון עצמו, בחינם ובלי לשלוח נתונים. עובד על טקסט — PDF דיגיטלי או טקסט שזוהה מתמונה.")
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("בינה מלאכותית")
        .onAppear(perform: loadFields)
        .onDisappear {
            AISettings.setAPIKey(key, for: provider)
            AISettings.setModel(model, for: provider)
            if provider == .custom { AISettings.customBaseURL = baseURL }
        }
    }

    private func loadFields() {
        key = AISettings.apiKey(for: provider)
        model = AISettings.model(for: provider)
        models = []
        testResult = nil
    }

    private func loadModels() async {
        AISettings.setAPIKey(key, for: provider)
        AISettings.setModel(model, for: provider)
        if provider == .custom { AISettings.customBaseURL = baseURL }
        guard let remote = AISettings.remote(for: provider) else { return }
        testing = true
        defer { testing = false }
        do {
            models = try await remote.listModels()
            testOK = true
            testResult = "החיבור תקין — נמצאו \(models.count) מודלים."
            if model.isEmpty, let first = models.first(where: { $0.hasSuffix(":free") }) ?? models.first {
                model = first
                AISettings.setModel(first, for: provider)
            }
        } catch {
            testOK = false
            testResult = hebrewMessage(for: error)
        }
    }
}

// MARK: - Calendar

struct CalendarSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(CalendarService.self) private var calendar
    @State private var selectedCalendars: Set<String> = []
    @State private var start = LocalDate.today()
    @State private var end = LocalDate.today().adding(months: 3)
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("הרשאה", value: calendar.statusText)
                if calendar.status == .notDetermined || calendar.status == .writeOnly {
                    Button("לאפשר ייבוא וייצוא (גישה מלאה)") { Task { _ = await calendar.requestFullAccess() } }
                }
                if calendar.status == .notDetermined {
                    Button("לאפשר ייצוא בלבד") { Task { _ = await calendar.requestWriteOnlyAccess() } }
                }
                if calendar.status == .denied {
                    Button("פתיחת הגדרות האייפון") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                }
            } footer: {
                Text("האפליקציה ניגשת ליומן רק כשאתה מבקש. אירועים מיובאים לא מקבלים הכנסה אוטומטית — אתה מחליט לאילו מהם להוסיף סכום.")
            }

            if calendar.canRead {
                Section("ייבוא אירועים מהיומן") {
                    ForEach(calendar.calendars(), id: \.calendarIdentifier) { c in
                        Button {
                            if selectedCalendars.contains(c.calendarIdentifier) { selectedCalendars.remove(c.calendarIdentifier) } else { selectedCalendars.insert(c.calendarIdentifier) }
                        } label: {
                            HStack {
                                Circle().fill(Color(cgColor: c.cgColor)).frame(width: 10, height: 10)
                                Text(c.title).foregroundStyle(.primary)
                                Spacer()
                                if selectedCalendars.contains(c.calendarIdentifier) { Image(systemName: "checkmark").foregroundStyle(Theme.brand) }
                            }
                        }
                    }
                    DatePicker("מתאריך", selection: $start.asDate, displayedComponents: .date)
                    DatePicker("עד", selection: $end.asDate, displayedComponents: .date)
                    Button("ייבוא") {
                        let events = calendar.importableEvents(calendarIDs: selectedCalendars, range: DateRange(start: start, end: end))
                        let n = model.importEvents(events)
                        message = n == 0 ? "לא נמצאו אירועים חדשים." : "יובאו \(n) אירועים. אפשר להוסיף להם הכנסה צפויה במסך היומן."
                    }
                    .disabled(selectedCalendars.isEmpty)
                }
            }

            if calendar.canWrite {
                Section {
                    Button("ייצוא כל האירועים העתידיים ליומן") {
                        var n = 0
                        for e in model.data.events where e.date >= model.today {
                            if let id = try? calendar.export(e), !id.isEmpty { model.setCalendarIdentifier(id, for: e.id); n += 1 }
                        }
                        message = "יוצאו \(n) אירועים ליומן."
                    }
                } footer: {
                    Text(calendar.canRead ? "האירועים יישמרו ביומן נפרד בשם \"\(CalendarService.appCalendarTitle)\"." : "האירועים יישמרו ביומן ברירת המחדל.")
                }
            }
        }
        .navigationTitle("יומן האייפון")
        .onAppear { calendar.refresh() }
        .alert("יומן", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("אישור", role: .cancel) {}
        } message: { Text(message ?? "") }
    }
}

// MARK: - Notifications

struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(NotificationService.self) private var notifications
    @State private var toggles: [NotificationService.Kind: Bool] = [:]
    @State private var hour = NotificationService.reminderHour

    var body: some View {
        Form {
            Section {
                switch notifications.authorization {
                case .authorized, .provisional, .ephemeral:
                    Label("התראות מאושרות", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.actual)
                    LabeledContent("תזכורות מתוזמנות", value: "\(notifications.scheduledCount)")
                case .denied:
                    Label("ההתראות חסומות", systemImage: "bell.slash").foregroundStyle(Theme.liability)
                    Button("פתיחת הגדרות האייפון") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                default:
                    Button("הפעלת התראות") { Task { if await notifications.requestPermission() { reschedule() } } }
                }
            } footer: {
                Text("התזכורות נוצרות על האייפון עצמו — בלי שרת ובלי לשלוח נתונים. במצב הדגמה לא נשלחות תזכורות.")
            }
            Section("מה להזכיר") {
                ForEach(NotificationService.Kind.allCases) { k in
                    Toggle(k.title, isOn: Binding(get: { toggles[k] ?? true }, set: { toggles[k] = $0; NotificationService.setEnabled(k, $0); reschedule() }))
                }
            }
            Section("שעה") {
                Stepper("תזכורות בשעה \(ltr(String(format: "%02d:00", hour)))", value: $hour, in: 6...22)
                    .onChange(of: hour) { _, h in NotificationService.reminderHour = h; reschedule() }
            }
        }
        .navigationTitle("התראות")
        .task {
            await notifications.refreshAuthorization()
            for k in NotificationService.Kind.allCases { toggles[k] = NotificationService.isEnabled(k) }
        }
    }

    private func reschedule() {
        Task { await notifications.reschedule(for: model.data, today: model.today, isDemo: model.mode == .demo) }
    }
}

// MARK: - Integrations info (honest status)

struct IntegrationsInfoView: View {
    var body: some View {
        List {
            Section {
                status("ייבוא ממסמכים וצילומים", "פעיל", Theme.actual, "אישורי יתרה, דפי תנועות, פירוטי אשראי, קבלות וצילומי ביט.")
                status("הזנה ידנית", "פעיל", Theme.actual, "כל סוגי התנועות, חובות, אירועים ותשלומים קבועים.")
                status("יומן האייפון", "פעיל", Theme.actual, "ייבוא וייצוא אירועים, בהרשאתך.")
                status("Siri וקיצורים", "פעיל", Theme.actual, "\"כמה כסף יש לי\" ו\"הוספת הוצאה\" באפליקציית קיצורים.")
            } header: { Text("עובד עכשיו") }
            Section {
                status("חיבור ישיר לבנקים ולחברות אשראי", "לא זמין", Theme.neutral,
                       "בישראל רק גוף בעל רישיון \"נותן שירות מידע פיננסי\" מרשות ניירות ערך רשאי למשוך נתונים מהבנקים. האפליקציה לא מתחזה לחיבור כזה ולא מבקשת סיסמת בנק.")
                status("ביט", "ידני / ממסמך", Theme.expected,
                       "אין ממשק פתוח לקריאת היסטוריית ביט של אדם פרטי. אפשר לרשום ידנית, לייבא צילום מסך, ותנועות \"ביט\" בדף הבנק מזוהות כדי למנוע כפילות.")
            } header: { Text("מגבלות") } footer: {
                Text("פירוט מלא במסמך API_INTEGRATIONS.md של הפרויקט.")
            }
        }
        .navigationTitle("בנקים, אשראי וביט")
    }

    private func status(_ title: String, _ badge: String, _ color: Color, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.body.weight(.medium)); Spacer(); StatusBadge(text: badge, color: color) }
            Text(text).font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 2)
    }
}
