package com.vainraich.finance.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vainraich.core.*
import com.vainraich.finance.AppViewModel
import com.vainraich.finance.Mode
import java.time.LocalDate

// ---------- text helpers ----------

fun Money.ils(plus: Boolean = false) = MoneyFormatter.format(this, showPlus = plus)
fun LocalDate.weekdayAndDay() = "יום ${Labels.weekdayLong[weekdaySun1 - 1]}, $dayOfMonth ב${Labels.month(monthValue)}"
fun LocalDate.long() = "$dayOfMonth ב${Labels.month(monthValue)} $year"
fun LocalDate.relative(today: LocalDate): String = when (val d = today.daysUntil(this)) {
    0L -> "היום"; 1L -> "מחר"; -1L -> "אתמול"; in 2..6 -> "בעוד $d ימים"; else -> il
}

// ---------- layout ----------

@Composable
fun Card(modifier: Modifier = Modifier, padding: Dp = 16.dp, onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Palette.card)
            .border(0.5.dp, Palette.separator, shape)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(padding),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        content = content,
    )
}

@Composable
fun Amount(amount: Money, style: TextStyle = MaterialTheme.typography.bodyLarge, color: Color? = null, bySign: Boolean = false, plus: Boolean = false, modifier: Modifier = Modifier) {
    val c = color ?: if (bySign) (if (amount.isNeg) Palette.liability else if (amount.isPos) Palette.actual else MaterialTheme.colorScheme.onSurface) else MaterialTheme.colorScheme.onSurface
    val spoken = (if (amount.isNeg) "מינוס " else "") + MoneyFormatter.format(amount.abs()).replace("₪", "") + " שקלים"
    Text(amount.ils(plus), style = style.merge(AmountStyle), color = c, maxLines = 1, modifier = modifier.semantics { contentDescription = spoken })
}

@Composable
fun Badge(text: String, color: Color, icon: ImageVector? = null) {
    Row(
        Modifier.clip(CircleShape).background(color.copy(alpha = 0.14f)).padding(horizontal = 8.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        if (icon != null) Icon(icon, null, tint = color, modifier = Modifier.size(12.dp))
        Text(text, color = color, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun IconBubble(icon: ImageVector, color: Color, size: Dp = 36.dp) {
    Box(Modifier.size(size).clip(RoundedCornerShape(size * 0.3f)).background(color.copy(alpha = 0.14f)), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = color, modifier = Modifier.size(size * 0.55f))
    }
}

@Composable
fun StatTile(title: String, amount: Money, icon: ImageVector, color: Color, subtitle: String? = null, modifier: Modifier = Modifier) {
    Card(modifier, padding = 14.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            IconBubble(icon, color, 26.dp)
            Text(title, style = MaterialTheme.typography.labelMedium, color = Palette.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Amount(amount, MaterialTheme.typography.titleLarge, color = color)
        if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun SectionTitle(title: String, action: String? = null, onAction: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
        if (action != null && onAction != null) TextButton(onClick = onAction) { Text(action) }
    }
}

@Composable
fun EmptyState(icon: ImageVector, title: String, message: String, action: String? = null, onAction: (() -> Unit)? = null) {
    Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(80.dp).clip(CircleShape).background(Palette.brandSoft), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = Palette.brand, modifier = Modifier.size(40.dp))
        }
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Text(message, style = MaterialTheme.typography.bodyMedium, color = Palette.secondaryText, textAlign = TextAlign.Center)
        if (action != null && onAction != null) Button(onClick = onAction) { Text(action) }
    }
}

@Composable
fun DemoBanner(vm: AppViewModel) {
    if (vm.mode != Mode.DEMO) return
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Palette.expected).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Outlined.TheaterComedy, null, tint = Color.White)
        Column(Modifier.weight(1f)) {
            Text("מצב הדגמה", color = Color.White, fontWeight = FontWeight.Bold)
            Text("הנתונים כאן לדוגמה בלבד ואינם נשמרים.", color = Color.White, style = MaterialTheme.typography.labelSmall)
        }
        OutlinedButton(onClick = { vm.exitDemo() }, colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White)) { Text("לנתונים שלי", fontSize = 12.sp) }
    }
}

// ---------- screens scaffolding ----------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScreenScaffold(
    title: String, onBack: (() -> Unit)? = null, actions: @Composable RowScope.() -> Unit = {},
    fab: @Composable () -> Unit = {}, bottomBar: @Composable () -> Unit = {}, content: @Composable (PaddingValues) -> Unit,
) {
    Scaffold(
        containerColor = Palette.background,
        topBar = {
            TopAppBar(
                title = { Text(title, fontWeight = FontWeight.Bold) },
                navigationIcon = { if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "חזרה") } },
                actions = actions,
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Palette.background),
            )
        },
        floatingActionButton = fab,
        bottomBar = bottomBar,
        content = content,
    )
}

/** Form row wrapper (grouped list look). */
@Composable
fun FormSection(title: String? = null, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        if (title != null) Text(title, style = MaterialTheme.typography.labelLarge, color = Palette.secondaryText, modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp))
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Palette.card).padding(horizontal = 14.dp, vertical = 6.dp), content = content)
        if (footer != null) Text(footer, style = MaterialTheme.typography.labelSmall, color = Palette.secondaryText, modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp))
    }
}

@Composable
fun MoneyField(label: String, value: String, onChange: (String) -> Unit, large: Boolean = false, modifier: Modifier = Modifier) {
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        OutlinedTextField(
            value = value, onValueChange = { s -> onChange(s.filter { it.isDigit() || it == '.' || it == ',' || it == '-' }) },
            label = { Text(label) }, prefix = { Text("₪") }, singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            textStyle = (if (large) MaterialTheme.typography.headlineSmall else MaterialTheme.typography.bodyLarge).merge(AmountStyle),
            modifier = modifier.fillMaxWidth().padding(vertical = 4.dp),
        )
    }
}

@Composable
fun Field(label: String, value: String, onChange: (String) -> Unit, singleLine: Boolean = true, modifier: Modifier = Modifier) {
    OutlinedTextField(value, onChange, label = { Text(label) }, singleLine = singleLine, modifier = modifier.fillMaxWidth().padding(vertical = 4.dp))
}

@Composable
fun SwitchRow(label: String, checked: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(enabled = enabled) { onChange(!checked) }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, modifier = Modifier.weight(1f))
        Switch(checked, onChange, enabled = enabled)
    }
}

@Composable
fun ValueRow(label: String, value: String, onClick: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, modifier = Modifier.weight(1f))
        Text(value, color = Palette.secondaryText)
        if (onClick != null) Icon(Icons.Outlined.ChevronLeft, null, tint = Palette.secondaryText)
    }
}

@Composable
fun NavRow(icon: ImageVector, label: String, onClick: () -> Unit, trailing: String? = null) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, null, tint = Palette.brand)
        Text(label, modifier = Modifier.weight(1f))
        if (trailing != null) Text(trailing, color = Palette.secondaryText)
        Icon(Icons.Outlined.ChevronLeft, null, tint = Palette.secondaryText)
    }
}

/** Generic dropdown picker. */
@Composable
fun <T> Picker(label: String, options: List<T>, selected: T?, text: (T) -> String, onSelect: (T) -> Unit, noneText: String? = null, onNone: (() -> Unit)? = null) {
    var open by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().clickable { open = true }.padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(label, modifier = Modifier.weight(1f))
            Text(selected?.let(text) ?: noneText ?: "לא נבחר", color = Palette.brand)
            Icon(Icons.Outlined.UnfoldMore, null, tint = Palette.brand, modifier = Modifier.size(18.dp))
        }
        DropdownMenu(open, onDismissRequest = { open = false }) {
            if (noneText != null && onNone != null) DropdownMenuItem(text = { Text(noneText) }, onClick = { onNone(); open = false })
            options.forEach { o -> DropdownMenuItem(text = { Text(text(o)) }, onClick = { onSelect(o); open = false }) }
        }
    }
}

@Composable
fun <T> Segmented(options: List<T>, selected: T, text: (T) -> String, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth()) {
        options.forEachIndexed { i, o ->
            SegmentedButton(selected = o == selected, onClick = { onSelect(o) }, shape = SegmentedButtonDefaults.itemShape(i, options.size)) { Text(text(o), maxLines = 1) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateField(label: String, date: LocalDate, onChange: (LocalDate) -> Unit) {
    var open by remember { mutableStateOf(false) }
    ValueRow(label, date.il) { open = true }
    if (open) {
        val state = rememberDatePickerState(initialSelectedDateMillis = date.toEpochDay() * 86_400_000L)
        DatePickerDialog(onDismissRequest = { open = false }, confirmButton = {
            TextButton(onClick = { state.selectedDateMillis?.let { onChange(LocalDate.ofEpochDay(it / 86_400_000L)) }; open = false }) { Text("אישור") }
        }, dismissButton = { TextButton(onClick = { open = false }) { Text("ביטול") } }) { DatePicker(state) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimeField(label: String, time: TimeOfDay, onChange: (TimeOfDay) -> Unit) {
    var open by remember { mutableStateOf(false) }
    ValueRow(label, time.toString()) { open = true }
    if (open) {
        val state = rememberTimePickerState(time.hour, time.minute, is24Hour = true)
        AlertDialog(onDismissRequest = { open = false }, confirmButton = { TextButton(onClick = { onChange(TimeOfDay(state.hour, state.minute)); open = false }) { Text("אישור") } },
            dismissButton = { TextButton(onClick = { open = false }) { Text("ביטול") } }, text = { TimePicker(state) })
    }
}

@Composable
fun ConfirmDialog(title: String, message: String? = null, confirm: String, destructive: Boolean = true, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, title = { Text(title) }, text = message?.let { { Text(it) } },
        confirmButton = { TextButton(onClick = { onConfirm(); onDismiss() }) { Text(confirm, color = if (destructive) Palette.liability else Palette.brand) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("ביטול") } })
}

@Composable
fun BottomActionBar(text: String, enabled: Boolean = true, onClick: () -> Unit) {
    Surface(color = Palette.background) {
        Button(onClick = onClick, enabled = enabled, modifier = Modifier.fillMaxWidth().navigationBarsPadding().padding(16.dp).height(52.dp)) { Text(text, fontWeight = FontWeight.SemiBold) }
    }
}
