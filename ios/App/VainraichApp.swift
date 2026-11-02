import SwiftUI
import FinanceCore

@main
struct VainraichApp: App {
    @State private var model: AppModel
    @State private var lock = BiometricLock()
    @State private var notifications = NotificationService()
    @State private var calendar = CalendarService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // `-uiDemo YES` (UI tests / screenshots) starts in clearly-labelled demo mode.
        let demo = UserDefaults.standard.bool(forKey: "uiDemo")
        _model = State(initialValue: AppModel(startInDemo: demo))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(lock)
                .environment(notifications)
                .environment(calendar)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .tint(Theme.brand)
                .onAppear {
                    model.onDataChanged = { [weak model, weak notifications] in
                        guard let model, let notifications else { return }
                        notifications.scheduleSoon(for: model.data, today: model.today, isDemo: model.mode == .demo)
                    }
                    notifications.scheduleSoon(for: model.data, today: model.today, isDemo: model.mode == .demo)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.reloadIfChangedExternally()
                model.refreshDay()
            case .background:
                model.persistNow()
                lock.lockIfEnabled()
            default:
                break
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(BiometricLock.self) private var lock
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        ZStack {
            if hasOnboarded || model.mode == .demo {
                MainTabView()
            } else {
                OnboardingView()
            }
            if lock.isLocked {
                LockScreen().transition(.opacity)
            }
            if let toast = model.toast {
                VStack {
                    Spacer()
                    ToastView(text: toast).padding(.bottom, 90)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .onAppear { if model.hasPersonalData { hasOnboarded = true } }
        .animation(.spring(duration: 0.35), value: model.toast)
        .animation(.easeInOut, value: lock.isLocked)
        .alert("שגיאה", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("הבנתי", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

enum AppTab: String, Hashable {
    case home, calendar, transactions, debts, more
}

struct MainTabView: View {
    @State private var tab: AppTab = .home
    @State private var morePath = NavigationPath()

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { DashboardView() }
                .tabItem { Label("בית", systemImage: "house") }
                .tag(AppTab.home)
            NavigationStack { CalendarScreen() }
                .tabItem { Label("יומן", systemImage: "calendar") }
                .tag(AppTab.calendar)
            NavigationStack { TransactionsView() }
                .tabItem { Label("תנועות", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.transactions)
            NavigationStack { DebtsView() }
                .tabItem { Label("חובות", systemImage: "person.2") }
                .tag(AppTab.debts)
            NavigationStack(path: $morePath) { MoreView() }
                .tabItem { Label("עוד", systemImage: "ellipsis.circle") }
                .tag(AppTab.more)
        }
        .onAppear(perform: applyStartScreen)
    }

    /// `-startScreen <name>` launch argument used by automated screenshots.
    private func applyStartScreen() {
        guard let s = UserDefaults.standard.string(forKey: "startScreen") else { return }
        switch s {
        case "calendar": tab = .calendar
        case "transactions": tab = .transactions
        case "debts": tab = .debts
        case "more": tab = .more
        case "accounts": tab = .more; morePath.append(MoreDestination.accounts)
        case "reports": tab = .more; morePath.append(MoreDestination.reports)
        case "settings": tab = .more; morePath.append(MoreDestination.settings)
        case "import": tab = .more; morePath.append(MoreDestination.importDocuments)
        case "forecast": tab = .more; morePath.append(MoreDestination.forecast)
        default: tab = .home
        }
    }
}

enum MoreDestination: Hashable {
    case accounts, reports, settings, importDocuments, recurring, contacts, forecast, categories
}

struct MoreView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if model.mode == .demo {
                Section { DemoBanner().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            }
            Section("הכסף שלי") {
                NavigationLink(value: MoreDestination.accounts) { Label("חשבונות", systemImage: "building.columns") }
                NavigationLink(value: MoreDestination.forecast) { Label("תחזית תזרים", systemImage: "chart.line.uptrend.xyaxis") }
                NavigationLink(value: MoreDestination.reports) { Label("דוחות וניתוחים", systemImage: "chart.pie") }
                NavigationLink(value: MoreDestination.recurring) { Label("תשלומים קבועים", systemImage: "repeat") }
            }
            Section("הכנסת נתונים") {
                NavigationLink(value: MoreDestination.importDocuments) { Label("ייבוא ממסמך או צילום", systemImage: "doc.viewfinder") }
                NavigationLink(value: MoreDestination.contacts) { Label("אנשי קשר", systemImage: "person.crop.circle") }
                NavigationLink(value: MoreDestination.categories) { Label("קטגוריות", systemImage: "tag") }
            }
            Section {
                NavigationLink(value: MoreDestination.settings) { Label("הגדרות", systemImage: "gearshape") }
            }
        }
        .navigationTitle("עוד")
        .navigationDestination(for: MoreDestination.self) { d in
            switch d {
            case .accounts: AccountsView()
            case .reports: ReportsView()
            case .settings: SettingsView()
            case .importDocuments: DocumentImportView()
            case .recurring: RecurringListView()
            case .contacts: ContactsListView()
            case .forecast: ForecastView()
            case .categories: CategoriesView()
            }
        }
    }
}

struct LockScreen: View {
    @Environment(BiometricLock.self) private var lock

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(Theme.brand)
                Text("האפליקציה נעולה").font(.title2.weight(.semibold))
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("פתיחה", systemImage: "faceid").frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                if let e = lock.lastError { Text(e).font(.footnote).foregroundStyle(Theme.liability) }
            }
        }
        .task { await lock.unlock() }
    }
}
