package com.vainraich.finance

import android.app.Application
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.vainraich.finance.screens.*
import com.vainraich.finance.services.DocumentPrep
import com.vainraich.finance.services.Reminders
import com.vainraich.finance.ui.*

class FinanceApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Reminders.createChannel(this)
        Reminders.schedule(this)
    }
}

class MainActivity : FragmentActivity() {
    private val vm: AppViewModel by viewModels()
    private val lockPrefs by lazy { getSharedPreferences("lock", 0) }
    private var locked by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        locked = lockEnabled
        handleShare(intent)
        handleLaunchExtras(intent)
        lifecycle.addObserver(LifecycleEventObserver { _, e ->
            when (e) {
                Lifecycle.Event.ON_START -> { vm.reloadIfChanged(); vm.refreshDay(); if (locked) authenticate() }
                Lifecycle.Event.ON_STOP -> { vm.persistNow(); if (lockEnabled) locked = true }
                else -> {}
            }
        })
        setContent {
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                VainraichTheme {
                    Root(vm, locked, onUnlock = { authenticate() })
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShare(intent)
        handleLaunchExtras(intent)
    }

    /** Used by automated screenshots: `--ez uiDemo true --es startScreen calendar` (labelled demo data only). */
    private fun handleLaunchExtras(intent: Intent?) {
        if (intent?.getBooleanExtra("uiDemo", false) == true && vm.mode != Mode.DEMO) vm.enterDemo()
        val screen = intent?.getStringExtra("startScreen") ?: return
        vm.stack.clear()
        when (screen) {
            "calendar" -> vm.tab = Tab.CALENDAR
            "transactions" -> vm.tab = Tab.TRANSACTIONS
            "debts" -> vm.tab = Tab.DEBTS
            "more" -> vm.tab = Tab.MORE
            "accounts" -> { vm.tab = Tab.MORE; vm.push(Route.Accounts) }
            "reports" -> { vm.tab = Tab.MORE; vm.push(Route.Reports) }
            "settings" -> { vm.tab = Tab.MORE; vm.push(Route.Settings) }
            "ai" -> { vm.tab = Tab.MORE; vm.push(Route.AiSettings) }
            "import" -> { vm.tab = Tab.MORE; vm.push(Route.Import) }
            "forecast" -> { vm.tab = Tab.MORE; vm.push(Route.Forecast) }
            "review" -> { vm.tab = Tab.CALENDAR; vm.push(Route.PaymentReview) }
            "newExpense" -> { vm.tab = Tab.TRANSACTIONS; vm.push(Route.EditTransaction(null)) }
            "newEvent" -> { vm.tab = Tab.CALENDAR; vm.push(Route.EditEvent(null)) }
            "chat" -> { vm.tab = Tab.HOME; vm.push(Route.Chat) }
            else -> vm.tab = Tab.HOME
        }
    }

    /** A PDF / image / text shared from WhatsApp, mail or files opens the import screen. */
    private fun handleShare(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        val doc = if (intent.type == "text/plain" && intent.getStringExtra(Intent.EXTRA_TEXT) != null) {
            com.vainraich.finance.services.PickedDoc.Text(intent.getStringExtra(Intent.EXTRA_TEXT)!!)
        } else {
            @Suppress("DEPRECATION") val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return
            runCatching { DocumentPrep.load(this, uri, intent.type) }.getOrNull()
        } ?: return
        vm.sharedDocument = doc
        if (vm.stack.lastOrNull() != Route.Import) vm.push(Route.Import)
    }

    val lockEnabled get() = lockPrefs.getBoolean("enabled", false)
    fun setLockEnabled(v: Boolean) { lockPrefs.edit().putBoolean("enabled", v).apply() }
    val canAuthenticate get() = BiometricManager.from(this).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK or BiometricManager.Authenticators.DEVICE_CREDENTIAL) == BiometricManager.BIOMETRIC_SUCCESS

    fun authenticate(onResult: (Boolean) -> Unit = {}) {
        val prompt = BiometricPrompt(this, ContextCompat.getMainExecutor(this), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) { locked = false; onResult(true) }
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) { onResult(false) }
        })
        prompt.authenticate(BiometricPrompt.PromptInfo.Builder().setTitle("פתיחת הכספים שלי")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK or BiometricManager.Authenticators.DEVICE_CREDENTIAL).build())
    }
}

@Composable
fun Root(vm: AppViewModel, locked: Boolean, onUnlock: () -> Unit) {
    Box(Modifier.fillMaxSize().background(Palette.background)) {
        if (!vm.hasOnboarded && vm.mode != Mode.DEMO) {
            OnboardingScreen(vm)
        } else {
            val top = vm.stack.lastOrNull()
            BackHandler(enabled = top != null) { vm.pop() }
            if (top == null) Tabs(vm) else RouteScreen(vm, top)
        }
        AnimatedVisibility(vm.toast != null, Modifier.align(Alignment.BottomCenter).padding(bottom = 110.dp), enter = fadeIn(), exit = fadeOut()) {
            Row(Modifier.shadow(8.dp, CircleShape).clip(CircleShape).background(MaterialTheme.colorScheme.surface).padding(horizontal = 18.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Outlined.CheckCircle, null, tint = Palette.actual)
                Text(vm.toast ?: "")
            }
        }
        if (locked) {
            Column(Modifier.fillMaxSize().background(Palette.background), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                Icon(Icons.Outlined.Lock, null, tint = Palette.brand, modifier = Modifier.size(48.dp))
                Spacer(Modifier.height(16.dp))
                Text("האפליקציה נעולה", style = MaterialTheme.typography.titleLarge)
                Spacer(Modifier.height(16.dp))
                Button(onClick = onUnlock) { Icon(Icons.Outlined.Fingerprint, null); Spacer(Modifier.width(8.dp)); Text("פתיחה") }
            }
        }
        vm.error?.let { msg ->
            AlertDialog(onDismissRequest = { vm.error = null }, title = { Text("שגיאה") }, text = { Text(msg) },
                confirmButton = { TextButton(onClick = { vm.error = null }) { Text("הבנתי") } })
        }
    }
}

@Composable
fun Tabs(vm: AppViewModel) {
    Scaffold(
        containerColor = Palette.background,
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                listOf(
                    Triple(Tab.HOME, "בית", Icons.Outlined.Home), Triple(Tab.CALENDAR, "יומן", Icons.Outlined.CalendarMonth),
                    Triple(Tab.TRANSACTIONS, "תנועות", Icons.Outlined.ReceiptLong), Triple(Tab.DEBTS, "חובות", Icons.Outlined.People),
                    Triple(Tab.MORE, "עוד", Icons.Outlined.MoreHoriz),
                ).forEach { (t, label, icon) ->
                    NavigationBarItem(selected = vm.tab == t, onClick = { vm.tab = t }, icon = {
                        if (t == Tab.CALENDAR && vm.paymentQuestions.isNotEmpty()) BadgedBox(badge = { Badge { Text("${vm.paymentQuestions.size}") } }) { Icon(icon, label) }
                        else Icon(icon, label)
                    }, label = { Text(label) })
                }
            }
        },
    ) { pad ->
        Box(Modifier.padding(bottom = pad.calculateBottomPadding())) {
            when (vm.tab) {
                Tab.HOME -> HomeScreen(vm)
                Tab.CALENDAR -> CalendarScreen(vm)
                Tab.TRANSACTIONS -> TransactionsScreen(vm)
                Tab.DEBTS -> DebtsScreen(vm)
                Tab.MORE -> MoreScreen(vm)
            }
        }
    }
}

@Composable
fun RouteScreen(vm: AppViewModel, r: Route) {
    when (r) {
        Route.Forecast -> ForecastScreen(vm)
        Route.Accounts -> AccountsScreen(vm)
        is Route.AccountDetail -> AccountDetailScreen(vm, r.id)
        is Route.EditAccount -> AccountEditor(vm, r.id)
        is Route.EditTransaction -> TransactionEditor(vm, r.id, r.kind, r.eventId)
        Route.Recurring -> RecurringScreen(vm)
        is Route.EditRule -> RuleEditor(vm, r.id)
        is Route.EventDetail -> EventDetailScreen(vm, r.id)
        is Route.EditEvent -> EventEditor(vm, r.id, r.date)
        Route.PaymentReview -> PaymentReviewScreen(vm)
        is Route.DebtDetail -> DebtDetailScreen(vm, r.id)
        is Route.EditDebt -> DebtEditor(vm, r.id, r.direction)
        Route.Contacts -> ContactsScreen(vm)
        is Route.ContactDetail -> ContactDetailScreen(vm, r.id)
        Route.Reports -> ReportsScreen(vm)
        Route.Import -> ImportScreen(vm)
        Route.Categories -> CategoriesScreen(vm)
        Route.Settings -> SettingsScreen(vm)
        Route.AiSettings -> AiSettingsScreen(vm)
        Route.CalendarSettings -> CalendarSettingsScreen(vm)
        Route.NotificationSettings -> NotificationSettingsScreen(vm)
        Route.Integrations -> IntegrationsScreen(vm)
        Route.Chat -> ChatScreen(vm)
    }
}
