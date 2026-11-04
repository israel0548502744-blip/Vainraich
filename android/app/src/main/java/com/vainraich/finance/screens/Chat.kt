package com.vainraich.finance.screens

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.speech.RecognizerIntent
import android.speech.tts.TextToSpeech
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Send
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.vainraich.core.ai.Assistant
import com.vainraich.core.ai.ChatRole
import com.vainraich.finance.*
import com.vainraich.finance.services.AiProvider
import com.vainraich.finance.services.AiSettings
import com.vainraich.finance.ui.*
import com.vainraich.finance.ui.Card
import java.util.Locale

/** Chat with the user's own AI about their money — by typing or by voice. */
@Composable
fun ChatScreen(vm: AppViewModel) {
    val ctx = LocalContext.current
    val ai = remember { AiSettings(ctx) }
    val provider = ai.provider
    val prefs = remember { ctx.getSharedPreferences("chat", 0) }
    var speakAnswers by remember { mutableStateOf(prefs.getBoolean("speak", false)) }
    var input by remember { mutableStateOf("") }
    val list = rememberLazyListState()

    // Text-to-speech (the phone's own engine, offline when a Hebrew voice is installed).
    var tts by remember { mutableStateOf<TextToSpeech?>(null) }
    var ttsReady by remember { mutableStateOf(false) }
    DisposableEffect(Unit) {
        lateinit var engine: TextToSpeech
        engine = TextToSpeech(ctx) { status -> ttsReady = status == TextToSpeech.SUCCESS }
        tts = engine
        onDispose { engine.stop(); engine.shutdown() }
    }
    fun speak(text: String) {
        val e = tts ?: return
        if (!ttsReady) return
        val res = e.setLanguage(Locale.forLanguageTag("he-IL"))
        if (res == TextToSpeech.LANG_MISSING_DATA || res == TextToSpeech.LANG_NOT_SUPPORTED) {
            vm.show("אין קול עברי בטלפון — אפשר להתקין בהגדרות ← המרת טקסט לדיבור"); return
        }
        e.speak(text.replace("*", "").replace("#", ""), TextToSpeech.QUEUE_FLUSH, null, "answer")
    }

    fun send(text: String, viaVoice: Boolean = false) {
        tts?.stop()
        vm.sendChat(text) { answer -> if (speakAnswers || viaVoice) speak(answer) }
        input = ""
    }

    // Speech-to-text (the phone's own Google/Samsung recognizer, Hebrew).
    val voice = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        val said = r.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
        if (r.resultCode == Activity.RESULT_OK && !said.isNullOrBlank()) send(said, viaVoice = true)
    }
    fun listen() {
        tts?.stop()
        val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "he-IL")
            .putExtra(RecognizerIntent.EXTRA_PROMPT, "דבר — אני מקשיב")
        try { voice.launch(i) } catch (_: ActivityNotFoundException) { vm.error = "לא נמצא בטלפון זיהוי דיבור. אפשר להתקין את אפליקציית Google או להקליד." }
    }

    LaunchedEffect(vm.chat.size, vm.chatBusy) { if (vm.chat.isNotEmpty()) list.animateScrollToItem(list.layoutInfo.totalItemsCount.coerceAtLeast(1) - 1) }

    ScreenScaffold("העוזר שלי", onBack = { tts?.stop(); vm.pop() }, actions = {
        IconButton(onClick = { speakAnswers = !speakAnswers; prefs.edit().putBoolean("speak", speakAnswers).apply(); if (!speakAnswers) tts?.stop() }) {
            Icon(if (speakAnswers) Icons.Outlined.VolumeUp else Icons.Outlined.VolumeOff, if (speakAnswers) "הקראת תשובות פעילה" else "הקראת תשובות כבויה",
                tint = if (speakAnswers) Palette.brand else Palette.secondaryText)
        }
        if (vm.chat.isNotEmpty()) IconButton(onClick = { tts?.stop(); vm.clearChat() }, enabled = !vm.chatBusy) { Icon(Icons.Outlined.DeleteSweep, "שיחה חדשה") }
    }, bottomBar = {
        Surface(color = Palette.card, tonalElevation = 2.dp) {
            Row(Modifier.fillMaxWidth().navigationBarsPadding().imePadding().padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilledIconButton(onClick = ::listen, enabled = !vm.chatBusy, modifier = Modifier.size(48.dp)) { Icon(Icons.Outlined.Mic, "דיבור") }
                OutlinedTextField(input, { input = it }, placeholder = { Text("שאל אותי משהו על הכסף שלך…") }, modifier = Modifier.weight(1f), maxLines = 4, shape = RoundedCornerShape(24.dp))
                IconButton(onClick = { send(input) }, enabled = input.isNotBlank() && !vm.chatBusy) {
                    Icon(Icons.AutoMirrored.Outlined.Send, "שליחה", tint = if (input.isNotBlank() && !vm.chatBusy) Palette.brand else Palette.secondaryText)
                }
            }
        }
    }) { pad ->
        LazyColumn(Modifier.padding(pad).fillMaxSize(), state = list, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item { DemoBanner(vm) }
            if (!provider.remote) item {
                Card {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Outlined.AutoAwesome, null, tint = Palette.brand)
                        Text("כדי לדבר איתי צריך לחבר בינה מלאכותית. Gemini של Google חינמי — לוקח דקה.", modifier = Modifier.weight(1f))
                    }
                    Button(onClick = { vm.push(Route.AiSettings) }) { Text("לחיבור בינה מלאכותית") }
                }
            }
            if (vm.chat.isEmpty()) item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("היי! 👋", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text("אני מכיר את החשבונות, התנועות, החובות והאירועים שלך. אפשר לשאול אותי שאלות, או לבקש שארשום משהו — ואני אציע, ואתה תאשר. אפשר גם ללחוץ על המיקרופון ולדבר.",
                        color = Palette.secondaryText)
                    Text("נסה למשל:", style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(top = 4.dp))
                    Assistant.examples.forEach { ex ->
                        SuggestionChip(onClick = { send(ex) }, label = { Text(ex) }, enabled = provider.remote && !vm.chatBusy)
                    }
                    Text("כדי לענות, נשלח לספק שבחרת (${provider.title}) סיכום של הנתונים שלך: יתרות, תנועות מ-90 הימים האחרונים, חובות ואירועים — בלי מספרי חשבון ובלי סיסמאות. " +
                        "שום דבר לא נשמר בלי שתאשר." + (if (provider == AiProvider.GEMINI || provider == AiProvider.OPENROUTER) " במסלולים חינמיים הספק עשוי להשתמש בתוכן לשיפור המודלים." else ""),
                        style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText, modifier = Modifier.padding(top = 8.dp))
                }
            }
            items(vm.chat, key = { it.id }) { m -> ChatBubble(vm, m, onSpeak = ::speak) }
            if (vm.chatBusy) item {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp); Text("חושב…", color = Palette.secondaryText)
                }
            }
        }
    }
}

@Composable
private fun ChatBubble(vm: AppViewModel, m: AppViewModel.ChatEntry, onSpeak: (String) -> Unit) {
    val mine = m.role == ChatRole.USER
    Column(Modifier.fillMaxWidth(), horizontalAlignment = if (mine) Alignment.End else Alignment.Start) {
        Box(Modifier.widthIn(max = 320.dp).clip(RoundedCornerShape(18.dp))
            .background(when { mine -> Palette.brand; m.isError -> Palette.liability.copy(alpha = 0.12f); else -> Palette.card })
            .clickable(enabled = !mine && !m.isError) { onSpeak(m.text) }
            .padding(horizontal = 14.dp, vertical = 10.dp)) {
            Text(if (mine) AnnotatedString(m.text) else markdownLite(m.text),
                color = when { mine -> MaterialTheme.colorScheme.onPrimary; m.isError -> Palette.liability; else -> MaterialTheme.colorScheme.onSurface })
        }
        if (m.isError && m.text.contains("הגדרות")) TextButton(onClick = { vm.push(Route.AiSettings) }) { Text("להגדרות הבינה המלאכותית") }
        m.actions.forEachIndexed { i, a ->
            Card(Modifier.widthIn(max = 340.dp).padding(top = 6.dp), padding = 12.dp) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Outlined.EditNote, null, tint = Palette.brand)
                    Text(a.summary, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                }
                val done = m.resolved[i]
                if (done == null) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { vm.confirmAction(m.id, i) }) { Icon(Icons.Outlined.Check, null); Spacer(Modifier.width(4.dp)); Text("אישור ושמירה") }
                    OutlinedButton(onClick = { vm.dismissAction(m.id, i) }) { Text("לא") }
                } else Text(done, color = if (done == "בוטל") Palette.secondaryText else Palette.actual, style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

/** Renders **bold** and strips simple markdown headings/bullets from model answers. */
private fun markdownLite(s: String): AnnotatedString = buildAnnotatedString {
    val text = s.lines().joinToString("\n") { it.replace(Regex("^#{1,6}\\s*"), "").replace(Regex("^\\s*[*-]\\s+"), "• ") }
    text.split("**").forEachIndexed { i, part -> if (i % 2 == 1) withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(part) } else append(part) }
}
