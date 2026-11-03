package com.vainraich.finance.screens

import android.app.Activity
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import com.vainraich.core.*
import com.vainraich.core.ai.*
import com.vainraich.finance.*
import com.vainraich.finance.services.*
import com.vainraich.finance.ui.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Import balances and transactions from a statement, balance confirmation, receipt or screenshot. */
@Composable
fun ImportScreen(vm: AppViewModel) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val ai = remember { AiSettings(ctx) }
    var accountId by remember { mutableStateOf(vm.defaultAccountId) }
    var picked by remember { mutableStateOf(vm.sharedDocument) }
    var working by remember { mutableStateOf(false) }
    var plan by remember { mutableStateOf<ImportPlan?>(null) }
    var pasteOpen by remember { mutableStateOf(false) }
    var pasted by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { vm.sharedDocument = null }

    val pickImages = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(6)) { uris ->
        val bmps = uris.mapNotNull { u -> ctx.contentResolver.openInputStream(u)?.use { BitmapFactory.decodeStream(it) } }
        if (bmps.isNotEmpty()) picked = PickedDoc.Images(bmps)
    }
    val pickFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri != null) picked = runCatching { DocumentPrep.load(ctx, uri, null) }.getOrNull() ?: run { vm.error = "לא הצלחתי לפתוח את הקובץ."; null }
    }
    val scanner = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { res ->
        if (res.resultCode == Activity.RESULT_OK) {
            val r = GmsDocumentScanningResult.fromActivityResultIntent(res.data)
            r?.pdf?.uri?.let { u -> picked = DocumentPrep.load(ctx, u, "application/pdf") }
                ?: r?.pages?.mapNotNull { p -> ctx.contentResolver.openInputStream(p.imageUri)?.use { BitmapFactory.decodeStream(it) } }?.takeIf { it.isNotEmpty() }?.let { picked = PickedDoc.Images(it) }
        }
    }

    plan?.let { p -> ImportReview(vm, p) { plan = null; picked = null; vm.pop() }; return }

    ScreenScaffold("ייבוא ממסמך", onBack = vm::pop) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp)) {
            item { DemoBanner(vm) }
            item { Text("צלם או בחר מסמך — אישור יתרה, דף תנועות, פירוט אשראי, קבלה או צילום מסך מביט. הנתונים יוצגו לבדיקה ורק אחרי האישור שלך יישמרו.", modifier = Modifier.padding(vertical = 8.dp)) }
            item {
                FormSection("1. לאיזה חשבון") {
                    if (vm.activeAccounts.isEmpty()) TextButton(onClick = { vm.push(Route.EditAccount(null)) }) { Text("קודם צריך להוסיף חשבון") }
                    else Picker("חשבון", vm.activeAccounts, vm.data.account(accountId), { it.name }, { accountId = it.id })
                }
            }
            item {
                FormSection("2. המסמך", "טיפ: אפשר גם לשתף קובץ PDF או צילום ישירות מוואטסאפ או מהמייל אל \"הכספים שלי\".") {
                    NavRow(Icons.Outlined.DocumentScanner, "סריקה במצלמה", {
                        val opts = GmsDocumentScannerOptions.Builder().setGalleryImportAllowed(true).setPageLimit(6)
                            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG, GmsDocumentScannerOptions.RESULT_FORMAT_PDF)
                            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL).build()
                        GmsDocumentScanning.getClient(opts).getStartScanIntent(ctx as Activity)
                            .addOnSuccessListener { scanner.launch(IntentSenderRequest.Builder(it).build()) }
                            .addOnFailureListener { vm.error = "הסורק לא זמין במכשיר הזה (דורש שירותי Google Play). אפשר לבחור תמונה או קובץ." }
                    })
                    NavRow(Icons.Outlined.Image, "תמונה או צילום מסך", { pickImages.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) })
                    NavRow(Icons.Outlined.Folder, "קובץ PDF / תמונה / טקסט", { pickFile.launch(arrayOf("application/pdf", "image/*", "text/*")) })
                    NavRow(Icons.Outlined.ContentPaste, "הדבקת טקסט", { pasteOpen = true })
                    picked?.let { Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Outlined.CheckCircle, null, tint = Palette.actual); Spacer(Modifier.width(6.dp)); Text(it.description, color = Palette.actual) } }
                }
            }
            item {
                FormSection("3. קריאה") {
                    ValueRow("מנוע קריאה", ai.provider.title) { vm.push(Route.AiSettings) }
                    Text(ai.provider.price, style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText)
                    if (ai.textOnly && ai.provider.remote) Text("מצב פרטיות: יישלח טקסט בלבד, מספרי זהות וחשבון יוסתרו", style = MaterialTheme.typography.labelSmall, color = Palette.brand)
                    Spacer(Modifier.height(6.dp))
                }
            }
            item {
                Button(onClick = {
                    val doc = picked ?: return@Button
                    val acc = accountId ?: return@Button
                    working = true
                    scope.launch {
                        try {
                            val result = withContext(Dispatchers.IO) { DocumentPrep.extract(ctx, doc, ai.extractor(), ai.textOnly && ai.provider.remote) }
                            plan = ImportPlanner.plan(result, acc, vm.data, vm.today)
                        } catch (e: AIError) { vm.error = e.hebrew } catch (e: Exception) { vm.error = "לא הצלחתי לקרוא: ${e.message}" }
                        working = false
                    }
                }, enabled = picked != null && accountId != null && !working, modifier = Modifier.fillMaxWidth().height(52.dp)) {
                    if (working) { CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp); Spacer(Modifier.width(8.dp)); Text("קורא את המסמך…") }
                    else { Icon(Icons.Outlined.AutoAwesome, null); Spacer(Modifier.width(8.dp)); Text("קריאת המסמך", fontWeight = FontWeight.SemiBold) }
                }
            }
        }
    }
    if (pasteOpen) AlertDialog(onDismissRequest = { pasteOpen = false }, title = { Text("הדבקת טקסט") },
        text = { OutlinedTextField(pasted, { pasted = it }, minLines = 6, modifier = Modifier.fillMaxWidth()) },
        confirmButton = { TextButton(onClick = { if (pasted.isNotBlank()) picked = PickedDoc.Text(pasted); pasteOpen = false }) { Text("שימוש") } },
        dismissButton = { TextButton(onClick = { pasteOpen = false }) { Text("ביטול") } })
}

@Composable
private fun ImportReview(vm: AppViewModel, plan: ImportPlan, onDone: () -> Unit) {
    val candidates = remember(plan) { mutableStateListOf<ImportCandidate>().apply { addAll(plan.candidates) } }
    val applyBalance = remember(plan) { mutableStateListOf<Int>() }
    val selected = candidates.filter { it.include }
    val appBalance = vm.balance(plan.targetAccountId) + selected.sumOfMoney { Ledger.effect(it.transaction, plan.targetAccountId) }
    ScreenScaffold("בדיקה לפני שמירה", onBack = onDone, bottomBar = {
        BottomActionBar(listOfNotNull(selected.size.takeIf { it > 0 }?.let { "הוספת $it תנועות" }, "עדכון יתרה".takeIf { applyBalance.isNotEmpty() }).joinToString(" + ").ifEmpty { "לא נבחר דבר" },
            enabled = selected.isNotEmpty() || applyBalance.isNotEmpty()) {
            val adjustments = applyBalance.mapNotNull { i -> plan.balances.getOrNull(i)?.let { ImportPlanner.adjustment(it.copy(appBalance = appBalance.m2()), plan.targetAccountId, vm.today) } }
            var n = 0
            if (vm.attempt { n = vm.applyImport(selected.map { it.transaction }, adjustments) }) {
                val matches = vm.paymentQuestions.count { it.kind == PaymentQuestion.Kind.POSSIBLE_MATCH }
                vm.show(if (matches > 0) "נוספו $n רשומות · $matches אירועים מחכים לאישור תשלום" else "נוספו $n רשומות")
                onDone()
            }
        }
    }) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp)) {
            item {
                FormSection {
                    ValueRow("סוג מסמך", plan.result.kind.hebrew)
                    plan.result.institution?.let { ValueRow("מוסד", it) }
                    plan.result.accountHint?.let { ValueRow("חשבון / כרטיס", it) }
                    plan.result.statementDate?.let { ValueRow("נכון לתאריך", it.il) }
                    plan.result.producedBy?.let { Text("נקרא על ידי: $it", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText, modifier = Modifier.padding(bottom = 6.dp)) }
                }
            }
            if (plan.warnings.isNotEmpty()) item { FormSection { plan.warnings.forEach { Text("⚠ $it", color = Palette.expected, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(vertical = 4.dp)) } } }
            if (plan.balances.isNotEmpty()) item {
                FormSection("יתרות") {
                    plan.balances.forEachIndexed { i, s ->
                        Column(Modifier.padding(vertical = 6.dp)) {
                            Text(s.label, fontWeight = FontWeight.SemiBold)
                            LabelAmount("לפי המסמך", s.amount)
                            LabelAmount("באפליקציה (אחרי הייבוא)", appBalance)
                            val diff = (s.amount - appBalance).m2()
                            if (diff.signum() != 0) SwitchRow("לעדכן את היתרה לפי המסמך (הפרש ${diff.ils(true)})", i in applyBalance) { if (it) applyBalance.add(i) else applyBalance.remove(i) }
                            else Text("✓ היתרה תואמת", color = Palette.actual)
                        }
                    }
                }
            }
            item {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 8.dp)) {
                    Text("תנועות (${selected.size} מתוך ${candidates.size})", style = MaterialTheme.typography.labelLarge, color = Palette.secondaryText, modifier = Modifier.weight(1f))
                    TextButton(onClick = { val all = selected.size != candidates.size; for (i in candidates.indices) candidates[i] = candidates[i].copy(include = all) }) { Text(if (selected.size == candidates.size) "ביטול הכל" else "בחירת הכל") }
                }
            }
            if (candidates.isEmpty()) item { Text("לא נמצאו תנועות.", color = Palette.secondaryText) }
            itemsIndexed(candidates) { i, c ->
                Row(Modifier.fillMaxWidth().padding(vertical = 3.dp).clip(RoundedCornerShape(14.dp)).background(Palette.card).padding(horizontal = 10.dp).alpha(if (c.include) 1f else 0.55f), verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(c.include, { candidates[i] = c.copy(include = it) })
                    Column(Modifier.weight(1f).clickable { candidates[i] = c.copy(include = !c.include) }) {
                        TransactionRow(vm, c.transaction)
                        c.note?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = if (c.duplicateOf != null) Palette.expected else Palette.secondaryText, modifier = Modifier.padding(bottom = 6.dp)) }
                    }
                }
            }
            item { Text("שורות שנראות כפולות לא מסומנות כברירת מחדל. אפשר לערוך כל תנועה אחרי השמירה.", style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText, modifier = Modifier.padding(vertical = 8.dp)) }
        }
    }
}
